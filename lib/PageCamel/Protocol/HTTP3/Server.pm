package PageCamel::Protocol::HTTP3::Server;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 5.0;
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use PageCamel::XS::NGHTTP3 qw(:constants);
use PageCamel::XS::NGHTTP3::Headers;
use PageCamel::Protocol::QUIC::Connection;
use PageCamel::Helpers::DateStrings;
use Scalar::Util qw(weaken);


sub new($class, %config) {
    # Debug: print all config keys
    print STDERR "DEBUG Server.pm new() config keys: " . join(", ", sort keys %config) . "\n";
    print STDERR "DEBUG Server.pm new() send_callback defined: " . (defined($config{send_callback}) ? "YES" : "NO") . "\n";

    # Handle both quic_conn and quic_connection for compatibility
    my $quic = $config{quic_conn} // $config{quic_connection} // croak("quic_conn or quic_connection required");

    my $self = bless {
        # QUIC connection
        quic_conn          => $quic,

        # Settings (increased from RFC minimums for better performance)
        # max_field_section_size: 64KB allows larger header blocks without fragmentation
        # qpack_max_table_capacity: 64KB enables better header compression for repeated headers
        max_field_section_size => $config{max_field_section_size} // 65536,
        qpack_max_table_capacity => $config{qpack_max_table_capacity} // 65536,
        qpack_blocked_streams => $config{qpack_blocked_streams} // 100,
        enable_connect_protocol => $config{enable_connect_protocol} // 1,

        # State
        state              => 'init',  # init, ready, closing, closed
        http3_conn         => undef,
        control_stream_id  => undef,
        qpack_enc_stream_id => undef,
        qpack_dec_stream_id => undef,

        # Request tracking
        requests           => {},  # stream_id -> request state
        pending_responses  => {},  # stream_id -> response data

        # Callbacks
        on_request         => $config{on_request},
        on_request_body    => $config{on_request_body},
        on_request_end     => $config{on_request_end},
        on_connect_request => $config{on_connect_request},
        on_error           => $config{on_error},
        send_callback      => $config{send_callback},  # For sending packets immediately

        # Metrics
        requests_received  => 0,
        responses_sent     => 0,
    }, $class;

    $self->_init_http3();

    return $self;
}

sub _init_http3($self) {
    # Create HTTP/3 settings
    my $settings = PageCamel::XS::NGHTTP3::Settings->new();
    $settings->set_max_field_section_size($self->{max_field_section_size});
    $settings->set_qpack_max_dtable_capacity($self->{qpack_max_table_capacity});
    $settings->set_qpack_blocked_streams($self->{qpack_blocked_streams});
    $settings->set_enable_connect_protocol($self->{enable_connect_protocol});

    # Create HTTP/3 connection
    $self->{http3_conn} = PageCamel::XS::NGHTTP3::Connection->server_new(
        settings => $settings,
        on_recv_header => sub { $self->_on_recv_header(@_) },
        on_end_headers => sub { $self->_on_end_headers(@_) },
        on_recv_data   => sub { $self->_on_recv_data(@_) },
        on_end_stream  => sub { $self->_on_end_stream(@_) },
        on_reset_stream => sub { $self->_on_reset_stream(@_) },
        on_stop_sending => sub { $self->_on_stop_sending(@_) },
    );

    # CRITICAL: Hook into QUIC ACK notifications to tell nghttp3 about ACKed data.
    # Without this, nghttp3 thinks its send buffer is full of unACKed data and
    # stops calling read_data for more body data, causing large file transfers to stall.
    my $quic = $self->{quic_conn};
    my $http3 = $self->{http3_conn};
    $quic->set_on_acked_stream_data(sub {
        my ($conn, $stream_id, $datalen) = @_;
        # Tell nghttp3 that $datalen bytes on $stream_id have been ACKed
        my $rv = $http3->add_ack_offset($stream_id, $datalen);
        # Debug: log occasionally
        $self->{_ackCount} //= 0;
        $self->{_ackCount}++;
        if ($self->{_ackCount} <= 10 || $self->{_ackCount} % 1000 == 0) {
            print STDERR PageCamel::Helpers::DateStrings::getISODate() .
                " DEBUG HTTP3::Server: add_ack_offset stream=$stream_id datalen=$datalen rv=$rv (ack #$self->{_ackCount})\n";
        }
        return 0;
    });

    # Open control streams
    $self->_open_control_streams();

    $self->{state} = 'ready';
}

sub _open_control_streams($self) {
    my $quic = $self->{quic_conn};

    # Open server-initiated unidirectional streams for HTTP/3
    # Control stream
    my $control_id = $quic->{quic_conn}->open_uni_stream();
    if ($control_id >= 0) {
        $self->{control_stream_id} = $control_id;
        $self->{http3_conn}->bind_control_stream($control_id);
        # NOTE: nghttp3 includes the stream type byte for control stream
    }

    # QPACK streams - must open both and bind together
    my $enc_id = $quic->{quic_conn}->open_uni_stream();
    my $dec_id = $quic->{quic_conn}->open_uni_stream();

    if ($enc_id >= 0 && $dec_id >= 0) {
        $self->{qpack_enc_stream_id} = $enc_id;
        $self->{qpack_dec_stream_id} = $dec_id;

        # Bind both QPACK streams together (nghttp3 requires this)
        # NOTE: nghttp3 includes the stream type byte, so don't prepend
        $self->{http3_conn}->bind_qpack_streams($enc_id, $dec_id);
    }

    # CRITICAL: Flush pending SETTINGS data from nghttp3 to QUIC
    # After binding streams, nghttp3 generates SETTINGS frames that must be sent
    $self->flush_pending_data();
}

# Set callback for sending packets immediately after data is written to QUIC
# This prevents RTT inflation from packets sitting in queues
sub set_send_callback($self, $callback) {
    print STDERR "DEBUG Server.pm: set_send_callback called with " . (defined($callback) ? "callback" : "undef") . "\n";
    $self->{send_callback} = $callback;
    return;
}

# Flush pending HTTP/3 data from nghttp3 to QUIC streams
# This is critical after binding control streams (SETTINGS must be sent)
# and after submitting responses
# Returns: total bytes written to QUIC (0 if congestion blocked)
# Optional $send_callback: called after each successful write to send packets immediately
# If not provided, uses the callback set via set_send_callback()
sub flush_pending_data($self, $send_callback = undef) {
    # Use stored callback if none provided explicitly
    $send_callback //= $self->{send_callback};

    # Debug: check if callback is available (only log occasionally)
    $self->{_flushCallbackCheckCount} //= 0;
    $self->{_flushCallbackCheckCount}++;
    if($self->{_flushCallbackCheckCount} <= 5) {
        print STDERR "DEBUG flush_pending_data: callback_defined=" . (defined($send_callback) ? "YES" : "NO") .
            " stored_callback=" . (defined($self->{send_callback}) ? "YES" : "NO") . "\n";
    }

    my $quic = $self->{quic_conn};
    my $http3 = $self->{http3_conn};

    # Loop until nghttp3 has no more data to send
    # writev_stream returns (actual_stream_id, data, fin) - the stream_id tells us
    # which stream the data belongs to (nghttp3 decides, not us)
    # Use high iteration limit - 1.2MB / 16KB = 75 chunks per stream
    my $max_iterations = 1000;  # Safety limit for very large responses
    my $total_bytes = 0;
    my $iterations_used = 0;

    for my $iter (1..$max_iterations) {
        my ($actual_stream_id, $data, $fin);

        # CRITICAL: First check if we have pending data from a previous blocked write
        if ($self->{_pendingWriteData}) {
            $actual_stream_id = $self->{_pendingWriteData}{stream_id};
            $data = $self->{_pendingWriteData}{data};
            $fin = $self->{_pendingWriteData}{fin};
            # Debug: log when using pending data
            $self->{_pendingUsedCount} //= 0;
            $self->{_pendingUsedCount}++;
            if ($self->{_pendingUsedCount} <= 10 || $self->{_pendingUsedCount} % 1000 == 0) {
                print STDERR "DEBUG flush: USING PENDING #$self->{_pendingUsedCount} stream=$actual_stream_id pending_len=" . length($data) . " fin=$fin\n";
            }
            # Don't clear yet - only clear after successful write
        } else {
            # Pass -1 to let nghttp3 tell us which stream has data
            ($actual_stream_id, $data, $fin) = $http3->writev_stream(-1);
        }

        # No more data to send - nghttp3 returns undef when nothing pending
        # CRITICAL: Handle FIN-only frames - empty data with fin=1 must be processed!
        if (!defined $actual_stream_id || !defined $data) {
            # Debug: why did writev_stream return nothing?
            if ($iter == 1 && $self->{_flushCount} && $self->{_flushCount} % 100 == 0) {
                # Check flow control state
                my $streamDataLeft = $quic->{quic_conn}->get_max_stream_data_left(0) // -1;
                my $connDataLeft = $quic->{quic_conn}->get_max_data_left() // -1;
                my $cwndLeft = $quic->{quic_conn}->get_cwnd_left() // -1;
                print STDERR PageCamel::Helpers::DateStrings::getISODate() .
                    " DEBUG flush: writev_stream empty on iter=1 streamDataLeft=$streamDataLeft connDataLeft=$connDataLeft cwndLeft=$cwndLeft\n";
            }
            # CRITICAL: Send any pending packets even when no more data
            if($send_callback) {
                print STDERR "DEBUG flush: invoking send_callback (empty data path)\n";
                $send_callback->();
            }
            last;
        }

        # Check for empty data without FIN - nothing meaningful to send
        if (!length($data) && !$fin) {
            # No data and no FIN - nghttp3 is done for now
            $send_callback->() if($send_callback);
            last;
        }

        # Log FIN-only frames (important for debugging stream completion)
        if (!length($data) && $fin) {
            print STDERR PageCamel::Helpers::DateStrings::getISODate() .
                " DEBUG flush: FIN-ONLY frame for stream=$actual_stream_id\n";
        }

        $iterations_used = $iter;

        # Write to QUIC - returns bytes actually consumed (may be less than length if blocked)
        my $bytes_written = $quic->write_stream($actual_stream_id, $data, $fin // 0);

        # Handle write errors or partial writes
        if (!defined($bytes_written) || $bytes_written < 0) {
            # Error - don't acknowledge any data to nghttp3
            print STDERR "DEBUG flush_pending_data: stream=$actual_stream_id ERROR bytes_written=" . ($bytes_written // 'undef') . " data_len=" . length($data) . "\n";
            # CRITICAL: Send any pending packets before exiting on error
            $send_callback->() if($send_callback);
            last;
        }

        if ($bytes_written == 0 && length($data) > 0) {
            # Flow control blocked on DATA - SAVE the data for retry later
            # This is critical! nghttp3's writev_stream already "consumed" this data internally.
            # If we don't save it, the data is lost forever.
            # NOTE: Only do this if we had actual data to send. FIN-only frames (empty data)
            # can legitimately return 0 bytes written.
            $self->{_pendingSaveCount} //= 0;
            $self->{_pendingSaveCount}++;
            if ($self->{_pendingSaveCount} <= 10 || $self->{_pendingSaveCount} % 1000 == 0) {
                print STDERR "DEBUG flush: SAVING PENDING (blocked) #$self->{_pendingSaveCount} stream=$actual_stream_id data_len=" . length($data) . " fin=$fin\n";
            }
            $self->{_pendingWriteData} = {
                stream_id => $actual_stream_id,
                data => $data,
                fin => $fin,
            };
            # Only log occasionally to avoid flooding - but include flow control diagnostics
            $self->{_writeBlockedCount} //= 0;
            $self->{_writeBlockedCount}++;
            if ($self->{_writeBlockedCount} % 100 == 1) {
                # Check all flow control limits and congestion control to diagnose what's blocking
                my $streamDataLeft = $quic->{quic_conn}->get_max_stream_data_left($actual_stream_id) // -1;
                my $connDataLeft = $quic->{quic_conn}->get_max_data_left() // -1;
                my ($cwnd, $in_flight, $ssthresh, $rtt) = $quic->{quic_conn}->get_cong_stat();
                my $cwndLeft = $quic->{quic_conn}->get_cwnd_left() // -1;
                print STDERR "DEBUG flush: BLOCKED #$self->{_writeBlockedCount} stream=$actual_stream_id data_len=" . length($data) .
                    " cwnd=$cwnd in_flight=$in_flight ssthresh=$ssthresh rtt=$rtt cwndLeft=$cwndLeft\n";
            }
            # CRITICAL: Still send any pending packets before exiting!
            # Even if blocked, we may have created packets in previous iterations
            $send_callback->() if($send_callback);
            last;
        }

        # FIN-only frame (empty data with fin=1) - bytes_written=0 is expected and successful
        if ($bytes_written == 0 && length($data) == 0 && $fin) {
            print STDERR PageCamel::Helpers::DateStrings::getISODate() .
                " DEBUG flush: FIN-only frame sent successfully for stream=$actual_stream_id\n";
            # Clear pending if this was from pending data
            delete $self->{_pendingWriteData} if $self->{_pendingWriteData};
            # Continue to next iteration (might be more data/streams)
            # But first send packets to get FIN out immediately
            $send_callback->() if($send_callback);
        }

        # Successfully wrote some data
        $total_bytes += $bytes_written;

        # Always acknowledge written bytes to nghttp3
        $http3->add_write_offset($actual_stream_id, $bytes_written);

        # Handle pending data tracking
        if ($self->{_pendingWriteData}) {
            if ($bytes_written >= length($data)) {
                # Fully written - clear pending
                delete $self->{_pendingWriteData};
            } else {
                # Partial write - keep the remaining data as pending
                $self->{_pendingWriteData}{data} = substr($data, $bytes_written);
            }
        } elsif ($bytes_written < length($data)) {
            # Fresh data from writev_stream, but only partially written - save the rest
            my $remainingLen = length($data) - $bytes_written;
            $self->{_pendingSaveCount} //= 0;
            $self->{_pendingSaveCount}++;
            if ($self->{_pendingSaveCount} <= 10 || $self->{_pendingSaveCount} % 1000 == 0) {
                print STDERR "DEBUG flush: SAVING PENDING (partial) #$self->{_pendingSaveCount} stream=$actual_stream_id remaining=$remainingLen wrote=$bytes_written fin=$fin\n";
            }
            $self->{_pendingWriteData} = {
                stream_id => $actual_stream_id,
                data => substr($data, $bytes_written),
                fin => $fin,
            };
        }

        # Log successful write flow control state occasionally
        $self->{_writeSuccessCount} //= 0;
        $self->{_writeSuccessCount}++;
        if ($self->{_writeSuccessCount} % 500 == 1) {
            my ($cwnd, $in_flight, $ssthresh, $rtt) = $quic->{quic_conn}->get_cong_stat();
            my $cwndLeft = $quic->{quic_conn}->get_cwnd_left() // -1;
            print STDERR "DEBUG flush: SUCCESS #$self->{_writeSuccessCount} stream=$actual_stream_id wrote=$bytes_written" .
                " cwnd=$cwnd in_flight=$in_flight ssthresh=$ssthresh rtt=$rtt cwndLeft=$cwndLeft\n";
        }

        # CRITICAL: Send packets IMMEDIATELY after each write to minimize RTT inflation
        # Without this, packets sit in queue while we generate more, inflating measured RTT
        if($send_callback) {
            $self->{_successCallbackCount} //= 0;
            $self->{_successCallbackCount}++;
            if($self->{_successCallbackCount} <= 10 || $self->{_successCallbackCount} % 1000 == 0) {
                print STDERR "DEBUG flush: invoking send_callback after SUCCESS #$self->{_successCallbackCount}\n";
            }
            $send_callback->();
        }

        # Note: Don't break on partial write. Continue looping - on the next iteration,
        # writev_stream will return more data (nghttp3 tracks the offset), and write_stream
        # will return 0 if truly blocked. Breaking here prevents cwnd from growing properly
        # because we only send 1 packet per flush cycle instead of filling the cwnd.
    }

    # Debug: log flush results periodically
    $self->{_flushCount} //= 0;
    $self->{_flushCount}++;
    if($self->{_flushCount} % 100 == 0) {
        print STDERR PageCamel::Helpers::DateStrings::getISODate() . " DEBUG flush_pending_data: call #$self->{_flushCount} total_bytes=$total_bytes iterations=$iterations_used\n";
    }

    return $total_bytes;
}

# Process incoming stream data from QUIC

sub process_stream_data($self, $stream_id, $data, $fin) {
    return if $self->{state} eq 'closed';

    # Check if this is a unidirectional stream (client-initiated)
    if ($self->_is_client_uni_stream($stream_id)) {
        return $self->_process_uni_stream($stream_id, $data, $fin);
    }

    # Bidirectional stream - HTTP/3 request
    my $rv = $self->{http3_conn}->read_stream($stream_id, $data, $fin);

    if ($rv < 0) {
        warn "HTTP/3: Error processing stream $stream_id: " .
             PageCamel::XS::NGHTTP3::strerror($rv) . "\n";

        if ($self->{on_error}) {
            $self->{on_error}->($self, $stream_id, $rv);
        }
    }

    return $rv;
}

sub _process_uni_stream($self, $stream_id, $data, $fin) {
    return unless length($data);

    # nghttp3 expects to receive the stream type byte itself - it will parse
    # the varint stream type and handle the stream accordingly.
    # We should NOT strip the type byte - just pass all data directly.
    return $self->{http3_conn}->read_stream($stream_id, $data, $fin);
}

# Get data to write to QUIC streams

sub get_stream_data($self, $stream_id) {
    # writev_stream returns (actual_stream_id, data, fin)
    my ($actual_stream_id, $data, $fin) = $self->{http3_conn}->writev_stream($stream_id);
    return ($actual_stream_id, $data, $fin);
}

# Response methods

sub response($self, $stream_id, $status, $headers, $body = undef) {
    return unless $self->{state} eq 'ready';

    # Build headers array with :status
    my @header_array = (':status' => "$status");

    if (ref($headers) eq 'ARRAY') {
        push @header_array, @$headers;
    }
    elsif (ref($headers) eq 'HASH') {
        for my $name (keys %$headers) {
            push @header_array, lc($name) => $headers->{$name};
        }
    }

    # Check if we have body data to send
    my $has_body = defined $body && length($body);

    # Add content-length if body provided
    if ($has_body) {
        unless (grep { lc($_) eq 'content-length' } @header_array) {
            push @header_array, 'content-length' => length($body);
        }
    }

    # Submit response - use submit_response_with_body if we have body data
    my $rv;
    if ($has_body) {
        # Use the new data_reader API for body data
        $rv = $self->{http3_conn}->submit_response_with_body($stream_id, \@header_array);
        if ($rv < 0) {
            warn "HTTP/3: Failed to submit response with body: " .
                 PageCamel::XS::NGHTTP3::strerror($rv) . "\n";
            return $rv;
        }

        # Push body data to nghttp3's internal buffer
        my $data_rv = $self->{http3_conn}->set_stream_body_data($stream_id, $body);
        if ($data_rv < 0) {
            warn "HTTP/3: Failed to set body data: $data_rv\n";
            return $data_rv;
        }

        # Mark body as complete
        $self->{http3_conn}->set_stream_eof($stream_id);

        # Tell nghttp3 data is available - it will call read_data callback
        $self->{http3_conn}->resume_stream($stream_id);
    }
    else {
        # No body - use original submit_response (NULL data_reader = no body)
        $rv = $self->{http3_conn}->submit_response($stream_id, \@header_array);
        if ($rv < 0) {
            warn "HTTP/3: Failed to submit response: " .
                 PageCamel::XS::NGHTTP3::strerror($rv) . "\n";
            return $rv;
        }
    }

    $self->{responses_sent}++;

    # Flush all pending data from nghttp3 to QUIC
    # nghttp3 generates HEADERS and DATA frames via writev_stream
    $self->flush_pending_data();

    return 0;
}

# Flush pending data for a specific stream from nghttp3 to QUIC
# $force_fin: undef = use nghttp3's fin, 0 = force no fin, 1 = force fin
# Returns: bytes written (>=0) or negative error code
sub flush_stream_data($self, $target_stream_id, $force_fin = undef) {
    my $quic = $self->{quic_conn};
    my $http3 = $self->{http3_conn};

    # Get pending data from nghttp3
    # writev_stream returns (actual_stream_id, data, fin) - nghttp3 tells us which stream
    my ($actual_stream_id, $data, $fin) = $http3->writev_stream($target_stream_id);

    # Make sure we got data for the stream we asked for
    if (defined $actual_stream_id && defined $data && length($data)) {
        if ($actual_stream_id != $target_stream_id) {
            warn "HTTP/3: flush_stream_data asked for stream $target_stream_id but got $actual_stream_id\n";
        }

        # Determine fin value: use forced value if provided, else use nghttp3's value
        my $actual_fin = defined($force_fin) ? $force_fin : ($fin // 0);

        # Write to QUIC - returns bytes actually consumed
        my $bytes_written = $quic->write_stream($actual_stream_id, $data, $actual_fin);

        if (defined($bytes_written) && $bytes_written > 0) {
            # CRITICAL: Only acknowledge bytes actually written to QUIC
            $http3->add_write_offset($actual_stream_id, $bytes_written);
            return $bytes_written;
        }

        return $bytes_written // -1;
    }

    return 0;
}

sub response_stream($self, $stream_id, $status, $headers) {
    # Start a streaming response (headers only, body sent separately)
    return unless $self->{state} eq 'ready';

    my @header_array = (':status' => "$status");

    if (ref($headers) eq 'ARRAY') {
        push @header_array, @$headers;
    }
    elsif (ref($headers) eq 'HASH') {
        for my $name (keys %$headers) {
            push @header_array, lc($name) => $headers->{$name};
        }
    }

    # Use submit_response_with_body since body data will follow
    my $rv = $self->{http3_conn}->submit_response_with_body($stream_id, \@header_array);
    if ($rv < 0) {
        warn "HTTP/3: Failed to submit streaming response: " .
             PageCamel::XS::NGHTTP3::strerror($rv) . "\n";
        return;
    }

    $self->{responses_sent}++;

    # Flush HEADERS frame from nghttp3 to QUIC
    $self->flush_pending_data();

    # Return a stream object for sending body chunks
    return PageCamel::Protocol::HTTP3::ResponseStream->new(
        server    => $self,
        stream_id => $stream_id,
    );
}

sub send_body_chunk($self, $stream_id, $data, $fin = 0) {
    # Push body data through nghttp3's proper API
    # Returns: length($data) if data was accepted into nghttp3, 0 if blocked
    #
    # IMPORTANT: Once we push data to nghttp3, we return length($data) so the caller
    # clears its buffer. nghttp3 now owns the data. flush_pending_data() will drain
    # nghttp3 → QUIC as the congestion window opens.
    my $hasData = defined($data) && length($data);
    my $dataLen = $hasData ? length($data) : 0;

    # NOTE: Removed pendingUdpPackets check that was causing deadlock.
    # The check prevented new data from being pushed to nghttp3 when UDP was backed up,
    # but this created a circular dependency: no new data → no new packets → pending UDP
    # packets never cleared. The UDP buffering in sendQUICPackets handles the case where
    # packets can't be sent immediately - they'll be queued and retried.

    # CRITICAL: Try to flush existing pending data FIRST to make room
    $self->flush_pending_data();

    # NOTE: We do NOT check cwnd here anymore! The cwnd check was causing a deadlock:
    # - cwnd small → block data → no frames → no packets → no ACKs → cwnd stays small
    # QUIC's write_stream handles cwnd internally - let it decide what to accept.

    # Push data to nghttp3's internal buffer (if any)
    if ($hasData) {
        my $rv = $self->{http3_conn}->set_stream_body_data($stream_id, $data);
        if ($rv < 0) {
            warn "HTTP/3: Failed to push body chunk: $rv\n";
            return $rv;
        }
        # Track that we pushed this much data
        $self->{stream_bytes_pushed}->{$stream_id} += $dataLen;

        # Debug: log data pushes periodically
        $self->{_sendBodyCount} //= 0;
        $self->{_sendBodyCount}++;
        if ($self->{_sendBodyCount} % 100 == 1) {
            my $totalPushed = $self->{stream_bytes_pushed}->{$stream_id};
            print STDERR PageCamel::Helpers::DateStrings::getISODate() .
                " DEBUG send_body_chunk #$self->{_sendBodyCount}: stream=$stream_id pushed=$dataLen total=$totalPushed rv=$rv\n";
        }
    }

    # Mark EOF if this is the last chunk
    if ($fin) {
        my $totalPushed = $self->{stream_bytes_pushed}->{$stream_id} // 0;
        print STDERR PageCamel::Helpers::DateStrings::getISODate() .
            " DEBUG send_body_chunk: FIN=1 stream=$stream_id totalPushed=$totalPushed calling set_stream_eof\n";
        $self->{http3_conn}->set_stream_eof($stream_id);
    }

    # Tell nghttp3 data is available (or EOF status changed)
    if ($hasData || $fin) {
        my $resume_rv = $self->{http3_conn}->resume_stream($stream_id);

        # Try to flush immediately to QUIC
        my $flushed = $self->flush_pending_data();

        # Debug: log when FIN is set
        if ($fin) {
            print STDERR PageCamel::Helpers::DateStrings::getISODate() .
                " DEBUG send_body_chunk: after FIN resume_rv=$resume_rv flushed=$flushed\n";
        }

        # Debug: log when flush doesn't write anything but we have data
        if ($flushed == 0 && $hasData) {
            $self->{_noFlushCount} //= 0;
            $self->{_noFlushCount}++;
            if ($self->{_noFlushCount} % 100 == 1) {
                print STDERR PageCamel::Helpers::DateStrings::getISODate() .
                    " DEBUG send_body_chunk: NO FLUSH #$self->{_noFlushCount} stream=$stream_id pushed=$dataLen resume_rv=$resume_rv flushed=0\n";
            }
        }
    }

    # Data is now in nghttp3's buffer - return length so caller clears its buffer
    # flush_pending_data() will drain nghttp3 → QUIC as ACKs arrive
    return $dataLen;
}

sub send_trailers($self, $stream_id, $headers) {
    my @header_array;

    if (ref($headers) eq 'ARRAY') {
        @header_array = @$headers;
    }
    elsif (ref($headers) eq 'HASH') {
        for my $name (keys %$headers) {
            push @header_array, lc($name) => $headers->{$name};
        }
    }

    return $self->{http3_conn}->submit_trailers($stream_id, \@header_array);
}

sub tunnel_response($self, $stream_id, $status, $headers) {
    # For Extended CONNECT (WebSocket over HTTP/3)
    return unless $self->{state} eq 'ready';

    my @header_array = (':status' => "$status");

    if (ref($headers) eq 'ARRAY') {
        push @header_array, @$headers;
    }
    elsif (ref($headers) eq 'HASH') {
        for my $name (keys %$headers) {
            push @header_array, lc($name) => $headers->{$name};
        }
    }

    # Use submit_response_with_body since tunnel data will follow
    my $rv = $self->{http3_conn}->submit_response_with_body($stream_id, \@header_array);
    if ($rv < 0) {
        return;
    }

    # Flush HEADERS frame from nghttp3 to QUIC
    $self->flush_pending_data();

    # Return tunnel object for bidirectional data
    return PageCamel::Protocol::HTTP3::Tunnel->new(
        server    => $self,
        stream_id => $stream_id,
    );
}

sub _write_response_data($self, $stream_id, $data, $fin) {
    # DEPRECATED: This method bypasses nghttp3's DATA frame handling.
    # Use send_body_chunk() instead which properly uses nghttp3's data_reader API.
    # HTTP/3 body data must be wrapped in DATA frames
    # DATA frame format: type (0x00) + length (varint) + payload
    # Returns: bytes of original data consumed (not including frame overhead),
    #          or negative error code
    return 0 unless defined $data && length($data);

    my $framed_data = $self->_frame_data($data);
    my $frame_overhead = length($framed_data) - length($data);
    my $rv = $self->{quic_conn}->write_stream($stream_id, $framed_data, $fin);

    if($rv < 0) {
        # Error - could be STREAM_DATA_BLOCKED (-8) for flow control
        # print STDERR "HTTP3Server: write_stream error $rv for " . length($framed_data) . " bytes\n";
        return $rv;
    }

    # Convert bytes consumed of framed_data back to bytes of original data
    if($rv <= $frame_overhead) {
        # Only consumed frame header, not the actual data
        return 0;
    }

    return $rv - $frame_overhead;
}

# Frame body data as HTTP/3 DATA frame
sub _frame_data($self, $payload) {
    my $len = length($payload);

    # DATA frame type is 0x00
    my $frame_type = pack('C', 0x00);

    # Encode length as variable-length integer (RFC 9000 Section 16)
    my $frame_len = $self->_encode_varint($len);

    return $frame_type . $frame_len . $payload;
}

# Encode variable-length integer (RFC 9000 Section 16)
sub _encode_varint($self, $value) {
    no warnings 'portable';  # Suppress warning for 64-bit hex constant
    if ($value < 64) {
        # 1 byte: 00xxxxxx
        return pack('C', $value);
    }
    elsif ($value < 16384) {
        # 2 bytes: 01xxxxxx xxxxxxxx
        return pack('n', 0x4000 | $value);
    }
    elsif ($value < 1073741824) {
        # 4 bytes: 10xxxxxx xxxxxxxx xxxxxxxx xxxxxxxx
        return pack('N', 0x80000000 | $value);
    }
    else {
        # 8 bytes: 11xxxxxx ...
        return pack('Q>', 0xC000000000000000 | $value);
    }
}

# Stream management

sub close_stream($self, $stream_id, $error_code = 0) {
    delete $self->{requests}{$stream_id};
    delete $self->{pending_responses}{$stream_id};

    # Clean up stream body buffer
    $self->{http3_conn}->clear_stream_buffer($stream_id);

    $self->{http3_conn}->close_stream($stream_id, $error_code);
    $self->{quic_conn}->close_stream($stream_id, $error_code);
}

sub reset_stream($self, $stream_id, $error_code) {
    $self->close_stream($stream_id, $error_code);
}

# Connection management

sub close($self, $error_code = 0) {
    $self->{state} = 'closing';

    # Close all request streams
    for my $stream_id (keys %{$self->{requests}}) {
        $self->close_stream($stream_id, $error_code);
    }

    $self->{state} = 'closed';
}

sub is_ready($self) { return $self->{state} eq 'ready'; }
sub is_closed($self) { return $self->{state} eq 'closed'; }

# Metrics

sub metrics($self) {
    return {
        state             => $self->{state},
        requests_received => $self->{requests_received},
        responses_sent    => $self->{responses_sent},
        active_requests   => scalar(keys %{$self->{requests}}),
    };
}

# Internal callback handlers

sub _on_recv_header($self, $stream_id, $name, $value, $flags) {
    # Initialize request state if needed
    $self->{requests}{$stream_id} //= {
        headers => PageCamel::XS::NGHTTP3::Headers->new(),
        body    => '',
        state   => 'headers',
    };

    my $req = $self->{requests}{$stream_id};
    $req->{headers}->add($name, $value);

    return 0;
}

sub _on_end_headers($self, $stream_id, $fin) {
    my $req = $self->{requests}{$stream_id};
    return 0 unless $req;

    $req->{state} = 'body';
    $self->{requests_received}++;

    my $headers = $req->{headers};
    my $method = $headers->method() // 'GET';

    # Check for Extended CONNECT (WebSocket)
    if ($method eq 'CONNECT' && $headers->protocol()) {
        if ($self->{on_connect_request}) {
            $self->{on_connect_request}->($self, $stream_id, $headers);
        }
        return 0;
    }

    # Regular HTTP request
    if ($self->{on_request}) {
        $self->{on_request}->($self, $stream_id, $headers, $fin);
    }

    return 0;
}

sub _on_recv_data($self, $stream_id, $data) {
    my $req = $self->{requests}{$stream_id};
    return 0 unless $req;

    $req->{body} .= $data;

    if ($self->{on_request_body}) {
        $self->{on_request_body}->($self, $stream_id, $data);
    }

    return 0;
}

sub _on_end_stream($self, $stream_id) {
    my $req = $self->{requests}{$stream_id};
    return 0 unless $req;

    $req->{state} = 'complete';

    if ($self->{on_request_end}) {
        $self->{on_request_end}->($self, $stream_id, $req->{headers}, $req->{body});
    }

    return 0;
}

sub _on_reset_stream($self, $stream_id, $error_code) {
    delete $self->{requests}{$stream_id};

    if ($self->{on_error}) {
        $self->{on_error}->($self, $stream_id, $error_code);
    }

    return 0;
}

sub _on_stop_sending($self, $stream_id, $error_code) {
    # Client requested we stop sending on this stream
    delete $self->{pending_responses}{$stream_id};

    return 0;
}

# Utility methods

sub _is_client_uni_stream($self, $stream_id) {
    # Client-initiated unidirectional streams have (id & 0x3) == 0x2
    return ($stream_id & 0x3) == 0x2;
}

sub _is_client_bidi_stream($self, $stream_id) {
    # Client-initiated bidirectional streams have (id & 0x3) == 0x0
    return ($stream_id & 0x3) == 0x0;
}


# ResponseStream class for streaming responses

package PageCamel::Protocol::HTTP3::ResponseStream;

sub new($class, %args) {
    my $self = bless {
        server    => $args{server},
        stream_id => $args{stream_id},
        closed    => 0,
    }, $class;

    Scalar::Util::weaken($self->{server});

    return $self;
}

sub send($self, $data) {
    return if $self->{closed};
    return $self->{server}->send_body_chunk($self->{stream_id}, $data, 0);
}

sub last($self, $data = '') {
    return if $self->{closed};
    $self->{closed} = 1;
    return $self->{server}->send_body_chunk($self->{stream_id}, $data, 1);
}

sub close($self) {
    return if $self->{closed};
    $self->{closed} = 1;
    return $self->{server}->send_body_chunk($self->{stream_id}, '', 1);
}

sub stream_id($self) { return $self->{stream_id}; }
sub is_closed($self) { return $self->{closed}; }


# Tunnel class for WebSocket/Extended CONNECT

package PageCamel::Protocol::HTTP3::Tunnel;

sub new($class, %args) {
    my $self = bless {
        server    => $args{server},
        stream_id => $args{stream_id},
        closed    => 0,
        on_data   => undef,
        on_close  => undef,
    }, $class;

    Scalar::Util::weaken($self->{server});

    return $self;
}

sub send($self, $data) {
    return if $self->{closed};
    return $self->{server}->send_body_chunk($self->{stream_id}, $data, 0);
}

sub close($self, $data = '') {
    return if $self->{closed};
    $self->{closed} = 1;

    if (length($data)) {
        $self->{server}->send_body_chunk($self->{stream_id}, $data, 1);
    } else {
        $self->{server}->close_stream($self->{stream_id});
    }

    if ($self->{on_close}) {
        $self->{on_close}->($self);
    }
}

sub on_data($self, $callback = undef) {
    if (defined $callback) {
        $self->{on_data} = $callback;
    }
    return $self->{on_data};
}

sub on_close($self, $callback = undef) {
    if (defined $callback) {
        $self->{on_close} = $callback;
    }
    return $self->{on_close};
}

sub stream_id($self) { return $self->{stream_id}; }
sub is_closed($self) { return $self->{closed}; }

# Internal method called by server when data arrives
sub _receive_data($self, $data, $fin) {
    if ($self->{on_data}) {
        $self->{on_data}->($self, $data);
    }

    if ($fin) {
        $self->{closed} = 1;
        if ($self->{on_close}) {
            $self->{on_close}->($self);
        }
    }
}


1;

__END__

=head1 NAME

PageCamel::Protocol::HTTP3::Server - HTTP/3 protocol server

=head1 SYNOPSIS

    use PageCamel::Protocol::HTTP3::Server;

    my $http3 = PageCamel::Protocol::HTTP3::Server->new(
        quic_conn => $quic_connection,
        on_request => sub {
            my ($server, $stream_id, $headers, $fin) = @_;

            my $method = $headers->method();
            my $path = $headers->path();

            # Send response
            $server->response($stream_id, 200,
                ['content-type' => 'text/html'],
                "<h1>Hello HTTP/3!</h1>"
            );
        },
        on_connect_request => sub {
            my ($server, $stream_id, $headers) = @_;

            # WebSocket upgrade via Extended CONNECT
            my $tunnel = $server->tunnel_response($stream_id, 200, []);

            $tunnel->on_data(sub {
                my ($t, $data) = @_;
                # Handle WebSocket frames
            });
        },
    );

    # In your event loop, process stream data from QUIC:
    $http3->process_stream_data($stream_id, $data, $fin);

=head1 DESCRIPTION

This class implements an HTTP/3 server over a QUIC connection. It handles
HTTP/3 framing, QPACK header compression, and provides a high-level interface
for handling requests and sending responses.

=head1 METHODS

=head2 new(%config)

Create a new HTTP/3 server.

Required:

=over 4

=item quic_conn - PageCamel::Protocol::QUIC::Connection object

=back

Optional:

=over 4

=item max_field_section_size - Max header section size (default: 65536)

=item qpack_max_table_capacity - QPACK dynamic table capacity (default: 65536)

=item qpack_blocked_streams - Max QPACK blocked streams (default: 100)

=item enable_connect_protocol - Enable Extended CONNECT (default: 1)

=back

Callbacks:

=over 4

=item on_request($server, $stream_id, $headers, $fin)

=item on_request_body($server, $stream_id, $data)

=item on_request_end($server, $stream_id, $headers, $body)

=item on_connect_request($server, $stream_id, $headers)

=item on_error($server, $stream_id, $error_code)

=back

=head2 process_stream_data($stream_id, $data, $fin)

Process incoming HTTP/3 stream data from QUIC.

=head2 get_stream_data($stream_id)

Get outgoing data for a QUIC stream.

=head2 response($stream_id, $status, $headers, $body)

Send a complete HTTP/3 response.

=head2 response_stream($stream_id, $status, $headers)

Start a streaming response. Returns a ResponseStream object.

=head2 send_body_chunk($stream_id, $data, $fin)

Send a body chunk for a streaming response.

=head2 send_trailers($stream_id, $headers)

Send HTTP trailers.

=head2 tunnel_response($stream_id, $status, $headers)

Accept an Extended CONNECT request. Returns a Tunnel object.

=head2 close_stream($stream_id, $error_code)

Close a stream.

=head2 close($error_code)

Close the HTTP/3 connection.

=head1 SEE ALSO

L<PageCamel::Protocol::QUIC::Connection>, L<PageCamel::XS::NGHTTP3>

=cut
