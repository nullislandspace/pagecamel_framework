package PageCamel::Protocol::HTTP3::Server;
use v5.38;
use strict;
use warnings;

use PageCamel::XS::NGHTTP3 qw(:constants);
use PageCamel::XS::NGHTTP3::Headers;
use PageCamel::Protocol::QUIC::Connection;
use Carp qw(croak);
use Scalar::Util qw(weaken);

our $VERSION = '0.01';

# HTTP/3 stream types
use constant {
    STREAM_TYPE_CONTROL        => 0x00,
    STREAM_TYPE_PUSH           => 0x01,
    STREAM_TYPE_QPACK_ENCODER  => 0x02,
    STREAM_TYPE_QPACK_DECODER  => 0x03,
};

sub new($class, %config) {
    my $self = bless {
        # QUIC connection
        quic_conn          => $config{quic_conn} // croak("quic_conn required"),

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

# Flush pending HTTP/3 data from nghttp3 to QUIC streams
# This is critical after binding control streams (SETTINGS must be sent)
# and after submitting responses
sub flush_pending_data($self) {
    my $quic = $self->{quic_conn};
    my $http3 = $self->{http3_conn};

    # Loop until nghttp3 has no more data to send
    # writev_stream returns (actual_stream_id, data, fin) - the stream_id tells us
    # which stream the data belongs to (nghttp3 decides, not us)
    my $max_iterations = 100;  # Safety limit
    my $sent_streams = {};  # Track which streams we've sent data for

    for my $iter (1..$max_iterations) {
        # Pass -1 to let nghttp3 tell us which stream has data
        my ($actual_stream_id, $data, $fin) = $http3->writev_stream(-1);

        # No more data to send
        last unless defined $actual_stream_id && defined $data && length($data);

        # Avoid infinite loop - if we've seen this stream, nghttp3 should have consumed it
        if ($sent_streams->{$actual_stream_id}++) {
            # We've already sent data for this stream in this flush
            # Call add_write_offset and try again
            $http3->add_write_offset($actual_stream_id, length($data));
            next;
        }

        # Debug: hex dump what we're sending
        my $hex = unpack('H*', $data);
        print STDERR "HTTP3::Server: stream $actual_stream_id sending " . length($data) . " bytes: $hex\n";

        # Write to QUIC
        $quic->write_stream($actual_stream_id, $data, $fin // 0);

        # Acknowledge we consumed this data from nghttp3
        $http3->add_write_offset($actual_stream_id, length($data));
    }
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
    # First byte is stream type
    return unless length($data);

    my $type = unpack('C', substr($data, 0, 1));
    my $payload = substr($data, 1);

    if ($type == STREAM_TYPE_CONTROL) {
        # Client control stream
        return $self->{http3_conn}->read_stream($stream_id, $payload, $fin);
    }
    elsif ($type == STREAM_TYPE_QPACK_ENCODER) {
        # Client QPACK encoder stream
        return $self->{http3_conn}->read_stream($stream_id, $payload, $fin);
    }
    elsif ($type == STREAM_TYPE_QPACK_DECODER) {
        # Client QPACK decoder stream
        return $self->{http3_conn}->read_stream($stream_id, $payload, $fin);
    }
    elsif ($type == STREAM_TYPE_PUSH) {
        # Push streams are server-initiated, client should not send these
        warn "HTTP/3: Unexpected push stream from client\n";
        return NGHTTP3_ERR_H3_STREAM_CREATION_ERROR();
    }
    else {
        # Unknown stream type - ignore per RFC 9114
        return 0;
    }
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

    # Add content-length if body provided
    if (defined $body && length($body)) {
        unless (grep { lc($_) eq 'content-length' } @header_array) {
            push @header_array, 'content-length' => length($body);
        }
    }

    # Submit response headers
    my $rv = $self->{http3_conn}->submit_response($stream_id, \@header_array);
    if ($rv < 0) {
        warn "HTTP/3: Failed to submit response: " .
             PageCamel::XS::NGHTTP3::strerror($rv) . "\n";
        return $rv;
    }

    $self->{responses_sent}++;

    # Check if we have body data to send
    my $has_body = defined $body && length($body);

    # Flush HEADERS frame from nghttp3 to QUIC
    # If we have body data, force fin=0 on the HEADERS frame
    $self->flush_stream_data($stream_id, $has_body ? 0 : undef);

    # Write response body to QUIC if provided
    if ($has_body) {
        $self->_write_response_data($stream_id, $body, 1);
    }

    return 0;
}

# Flush pending data for a specific stream from nghttp3 to QUIC
# $force_fin: undef = use nghttp3's fin, 0 = force no fin, 1 = force fin
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

        # Write to QUIC
        $quic->write_stream($actual_stream_id, $data, $actual_fin);

        # Acknowledge we consumed this data
        $http3->add_write_offset($actual_stream_id, length($data));
    }
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

    my $rv = $self->{http3_conn}->submit_response($stream_id, \@header_array);
    if ($rv < 0) {
        warn "HTTP/3: Failed to submit streaming response: " .
             PageCamel::XS::NGHTTP3::strerror($rv) . "\n";
        return;
    }

    $self->{responses_sent}++;

    # Flush HEADERS frame from nghttp3 to QUIC
    # Force fin=0 since body data will follow
    $self->flush_stream_data($stream_id, 0);

    # Return a stream object for sending body chunks
    return PageCamel::Protocol::HTTP3::ResponseStream->new(
        server    => $self,
        stream_id => $stream_id,
    );
}

sub send_body_chunk($self, $stream_id, $data, $fin = 0) {
    return $self->_write_response_data($stream_id, $data, $fin);
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

    my $rv = $self->{http3_conn}->submit_response($stream_id, \@header_array);
    if ($rv < 0) {
        return;
    }

    # Flush HEADERS frame from nghttp3 to QUIC
    # Force fin=0 since tunnel data will follow
    $self->flush_stream_data($stream_id, 0);

    # Return tunnel object for bidirectional data
    return PageCamel::Protocol::HTTP3::Tunnel->new(
        server    => $self,
        stream_id => $stream_id,
    );
}

sub _write_response_data($self, $stream_id, $data, $fin) {
    # HTTP/3 body data must be wrapped in DATA frames
    # DATA frame format: type (0x00) + length (varint) + payload
    return 0 unless defined $data && length($data);

    my $framed_data = $self->_frame_data($data);
    return $self->{quic_conn}->write_stream($stream_id, $framed_data, $fin);
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
use v5.38;

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
use v5.38;

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
