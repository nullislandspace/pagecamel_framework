package PageCamel::CMDLine::WebFrontend::HTTP3Handler;
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

no warnings 'experimental::args_array_with_signatures';

use base 'PageCamel::CMDLine::WebFrontend::BaseHTTPHandler';

use PageCamel::Protocol::HTTP3::Server;
use PageCamel::Protocol::HTTP3::QPACK::Encoder;
use PageCamel::Protocol::HTTP3::QPACK::Decoder;
use IO::Socket::UNIX;
use IO::Select;
use Socket qw(MSG_PEEK);
use Time::HiRes qw(time);
use PageCamel::Helpers::DateStrings;

sub new($class, %config) {
    my $self = bless \%config, $class;

    # Required parameters
    foreach my $key (qw[quicConnection backendSocketPath pagecamelInfo]) {
        if(!defined($self->{$key})) {
            croak("HTTP3Handler: Setting $key is required but not set!");
        }
    }

    # Initialize backend connection pooling (from base class)
    $self->initPooling();

    # Stream to response buffer mapping
    $self->{streamResponses} = {};
    # Stream states
    $self->{streamStates} = {};
    # Stream objects for streaming responses
    $self->{streamStreams} = {};
    # Tunnel objects for WebSocket
    $self->{streamTunnels} = {};
    # Per-stream buffers for data going to backends
    $self->{tobackendbuffers} = {};
    # Per-stream backend disconnect flags
    $self->{backenddisconnects} = {};
    # Counter for streams handled
    $self->{streamsHandled} = 0;
    # Per-stream content-length tracking
    $self->{streamContentLength} = {};
    $self->{streamBytesSent} = {};
    # Per-stream congestion-blocked flag (for back-pressure)
    $self->{streamCongestionBlocked} = {};
    # Per-stream pending flush flag (for buffered responses awaiting nghttp3 drain)
    $self->{streamPendingFlush} = {};

    return $self;
}

sub protocolVersion($self) {
    return 'HTTP/3';
}

sub run($self) {
    my $quicConn = $self->{quicConnection};

    # CRITICAL: Define send callback BEFORE creating HTTP/3 server
    # This callback is invoked by flush_pending_data() to send QUIC packets immediately.
    # It MUST be available during Server->new() because the constructor calls flush_pending_data()
    # to send initial SETTINGS frames. Without this, packets sit in queue and get stale timestamps.
    my $sendCallbackCount = 0;
    my $sendCallbackPkts = 0;
    my $sendCallback = sub {
        $sendCallbackCount++;
        my @pkts = $quicConn->get_packets(Time::HiRes::time());
        $sendCallbackPkts += scalar(@pkts);
        if ($sendCallbackCount <= 10 || $sendCallbackCount % 1000 == 0) {
            print STDERR "DEBUG sendCallback #$sendCallbackCount: got " . scalar(@pkts) . " packets (total=$sendCallbackPkts)\n";
        }
        foreach my $pkt (@pkts) {
            if(defined($self->{sendPacketCallback})) {
                $self->{sendPacketCallback}->($pkt->{data}, $pkt->{peer_addr});
            }
        }
    };

    # Create HTTP/3 server instance over the QUIC connection
    # The send_callback is passed here so it's available during initialization
    my $http3Server;
    $http3Server = PageCamel::Protocol::HTTP3::Server->new(
        quic_connection => $quicConn,
        send_callback => $sendCallback,
        on_request => sub($streamId, $headers, $data) {
            $self->handleRequest($http3Server, $streamId, $headers, $data);
        },
        on_connect_request => sub($streamId, $headers, $data = undef) {
            $self->handleConnectRequest($http3Server, $streamId, $headers);
        },
        on_data => sub($streamId, $data, $fin) {
            $self->handleStreamData($http3Server, $streamId, $data, $fin);
        },
    );

    # Buffering variables - same names as HTTP/1.1 and HTTP/2 implementations
    my $toclientbuffer = '';
    my $clientdisconnect = 0;
    my $finishcountdown = 0;
    my $maxBufferSize = 50_000_000;  # 50MB buffer limit
    my $blocksize = 16_384;          # Block size for writes

    # Main event loop
    my $done = 0;
    while(!$done) {
        # Build list of backend sockets to monitor
        my @backendSockets;
        foreach my $streamId (keys %{$self->{streamBackends}}) {
            my $backend = $self->{streamBackends}->{$streamId};
            if(defined($backend)) {
                push @backendSockets, $backend;
            }
        }

        # Calculate total backend buffer size for back-pressure
        my $totalBackendBufferSize = 0;
        foreach my $streamId (keys %{$self->{tobackendbuffers}}) {
            $totalBackendBufferSize += length($self->{tobackendbuffers}->{$streamId} // '');
        }

        # Build select sets for backend I/O
        my $readSet = IO::Select->new(@backendSockets);
        my $writeSet = IO::Select->new();

        # Add backends to write set if we have data to send
        foreach my $streamId (keys %{$self->{tobackendbuffers}}) {
            my $backend = $self->{streamBackends}->{$streamId};
            if(defined($backend) && length($self->{tobackendbuffers}->{$streamId} // '')) {
                $writeSet->add($backend);
            }
        }

        # Get QUIC connection timeout
        my $quicExpiry = $quicConn->get_expiry();
        my $now = Time::HiRes::time();
        my $timeout = $quicExpiry > $now ? ($quicExpiry - $now) : 0.001;
        $timeout = 0.001 if($timeout > 1);  # Cap at 1 second

        $ERRNO = 0;
        my ($canRead, $canWrite, undef) = IO::Select->select($readSet, $writeSet, undef, $timeout);

        # Handle EINTR
        if(!defined($canRead) && $ERRNO{EINTR}) {
            next;
        }

        $canRead //= [];
        $canWrite //= [];

        # Handle QUIC timeouts
        $quicConn->handle_expiry(Time::HiRes::time());

        # Check if QUIC connection is still alive
        if($quicConn->is_closed()) {
            $clientdisconnect = 1;
        }

        # Process any incoming QUIC data (fed by parent process)
        # The parent process calls process_packet() and we handle the callbacks

        # Handle readable backend sockets
        foreach my $socket (@{$canRead}) {
            $self->handleBackendData($http3Server, $socket, \$toclientbuffer, $maxBufferSize);
        }

        # Build hash of writable sockets
        my %canWriteHash = map { $_ => 1 } @{$canWrite};

        # Write to backends from per-stream buffers
        $self->writeToBackends($blocksize, 1000, $finishcountdown, \%canWriteHash);

        # Process any streams waiting for a backend connection
        $self->processWaitingStreams($http3Server);

        # Create packet sender callback for flushPendingStreams
        my $sendPacketsCallback = sub {
            my @pkts = $quicConn->get_packets(Time::HiRes::time());
            foreach my $pkt (@pkts) {
                if(defined($self->{sendPacketCallback})) {
                    $self->{sendPacketCallback}->($pkt->{data}, $pkt->{peer_addr});
                }
            }
        };

        # Flush pending data from nghttp3 to QUIC (critical for large responses)
        # This drains nghttp3's internal buffer after ACKs open the QUIC send window
        $self->flushPendingStreams($http3Server, $sendPacketsCallback);

        # Get outgoing QUIC packets and send them
        my @packets = $quicConn->get_packets(Time::HiRes::time());
        foreach my $pkt (@packets) {
            # Send packet via UDP (handled by parent)
            if(defined($self->{sendPacketCallback})) {
                $self->{sendPacketCallback}->($pkt->{data}, $pkt->{peer_addr});
            }
        }

        # Handle client disconnect
        if($clientdisconnect) {
            $done = 1;
        }

        # Check active streams
        my $activeStreams = scalar(keys %{$self->{streamBackends}}) +
                            scalar(keys %{$self->{streamStreams}}) +
                            scalar(keys %{$self->{streamTunnels}});

        # Handle finish countdown for buffer draining
        if($finishcountdown && !length($toclientbuffer)) {
            $finishcountdown = 0;
        } elsif(!$finishcountdown && length($toclientbuffer) && $activeStreams == 0) {
            $finishcountdown = time + 20;
        }

        if($finishcountdown > 0 && $finishcountdown <= time) {
            $done = 1;
        }
    }

    # Cleanup
    $self->cleanup();

    return;
}

sub handleRequest($self, $server, $streamId, $headers, $data) {
    $self->{streamsHandled}++;

    # Convert HTTP/3 headers to HTTP/1.1 request (without PAGECAMEL overhead)
    my $request = $self->translateRequest($streamId, $headers, $data);

    # Try to acquire backend from pool
    my $backend = $self->acquireBackend($streamId);
    if(!defined($backend)) {
        # Check if we're at capacity (queue) or backend unavailable (error)
        my $activeBackends = scalar(keys %{$self->{streamBackends}});
        if($activeBackends >= $self->{maxPoolSize}) {
            # At capacity, queue the request for later
            push @{$self->{waitingForBackend}}, [$streamId, $request, 'waiting_response'];
            return;
        }

        # Backend truly unavailable - send 590
        $server->response(
            $streamId,
            590,
            ['content-type', 'text/html; charset=UTF-8'],
            $self->{errorPage590Html} // '',
        );
        return;
    }

    # Buffer request for backend
    $self->{tobackendbuffers}->{$streamId} = $request;

    # Mark stream as waiting for response
    $self->{streamStates}->{$streamId} = 'waiting_response';
    $self->{streamResponses}->{$streamId} = '';

    return;
}

sub handleConnectRequest($self, $server, $streamId, $headers) {
    $self->{streamsHandled}++;

    # Check for WebSocket upgrade via extended CONNECT (RFC 9220)
    my %h;
    for(my $i = 0; $i < scalar(@{$headers}); $i += 2) {
        $h{$headers->[$i]} = $headers->[$i + 1];
    }

    my $protocol = $h{':protocol'} // '';
    if($protocol ne 'websocket') {
        # Reject non-WebSocket CONNECT requests
        $server->response($streamId, 400, ['content-type', 'text/plain'], 'Bad Request');
        return;
    }

    # Translate to HTTP/1.1 WebSocket upgrade (without PAGECAMEL overhead)
    my $request = $self->translateWebsocketUpgrade($streamId, $headers);

    # Try to acquire backend from pool
    my $backend = $self->acquireBackend($streamId);
    if(!defined($backend)) {
        # Check if we're at capacity (queue) or backend unavailable (error)
        my $activeBackends = scalar(keys %{$self->{streamBackends}});
        if($activeBackends >= $self->{maxPoolSize}) {
            # At capacity, queue the request for later (WebSocket/tunnel)
            push @{$self->{waitingForBackend}}, [$streamId, $request, 'tunnel_pending'];
            return;
        }

        # Backend truly unavailable - send 590
        $server->response($streamId, 590, ['content-type', 'text/html'], $self->{errorPage590Html} // '');
        return;
    }

    # Buffer request for backend
    $self->{tobackendbuffers}->{$streamId} = $request;

    # Mark as tunnel pending
    $self->{streamStates}->{$streamId} = 'tunnel_pending';
    $self->{streamResponses}->{$streamId} = '';

    return;
}

sub handleStreamData($self, $server, $streamId, $data, $fin) {
    # Handle incoming data on a stream (for tunnels/WebSocket AND request bodies)
    my $state = $self->{streamStates}->{$streamId} // '';

    if($state eq 'tunnel_active') {
        # Forward data to backend (WebSocket tunnel)
        my $backend = $self->{streamBackends}->{$streamId};
        if(defined($backend)) {
            $self->{tobackendbuffers}->{$streamId} //= '';
            $self->{tobackendbuffers}->{$streamId} .= $data;
        }
    } elsif($state eq 'waiting_response') {
        # Forward request body data to backend (PUT/POST uploads)
        # Body data arrives in chunks after the initial request headers
        my $backend = $self->{streamBackends}->{$streamId};
        if(defined($backend) && length($data)) {
            $self->{tobackendbuffers}->{$streamId} //= '';
            $self->{tobackendbuffers}->{$streamId} .= $data;
        }
    }

    return;
}

sub translateRequest($self, $streamId, $headers, $body) {
    # Convert HTTP/3 headers to HTTP/1.1 request format
    my %h;
    my @otherHeaders;
    my $hasContentLength = 0;

    for(my $i = 0; $i < scalar(@{$headers}); $i += 2) {
        my $name = $headers->[$i];
        my $value = $headers->[$i + 1];

        if($name =~ /^:/) {
            $h{$name} = $value;
        } else {
            push @otherHeaders, "$name: $value";
            # Track if client already sent content-length
            if(lc($name) eq 'content-length') {
                $hasContentLength = 1;
            }
        }
    }

    my $method = $h{':method'} // 'GET';
    my $path = $h{':path'} // '/';
    my $authority = $h{':authority'} // '';
    my $scheme = $h{':scheme'} // 'https';

    # Build HTTP/1.1 request
    my $request = "$method $path HTTP/1.1\r\n";

    # Add Host header from :authority
    $request .= "Host: $authority\r\n";

    # Add other headers (may include content-length from client)
    foreach my $hdr (@otherHeaders) {
        $request .= "$hdr\r\n";
    }

    # Only add Content-Length if client didn't send one and we have initial body data
    # Note: For streaming uploads, the client's content-length header is authoritative
    if(!$hasContentLength && defined($body) && length($body)) {
        $request .= "Content-Length: " . length($body) . "\r\n";
    }

    $request .= "\r\n";

    # Add initial body chunk (more may arrive via handleStreamData)
    if(defined($body) && length($body)) {
        $request .= $body;
    }

    # Note: PAGECAMEL overhead is sent once per pooled connection in createPooledBackend()
    return $request;
}

sub translateWebsocketUpgrade($self, $streamId, $headers) {
    # Convert HTTP/3 extended CONNECT to HTTP/1.1 WebSocket upgrade
    my %h;
    my @otherHeaders;

    for(my $i = 0; $i < scalar(@{$headers}); $i += 2) {
        my $name = $headers->[$i];
        my $value = $headers->[$i + 1];

        if($name =~ /^:/) {
            $h{$name} = $value;
        } else {
            push @otherHeaders, "$name: $value";
        }
    }

    my $path = $h{':path'} // '/';
    my $authority = $h{':authority'} // '';

    # Build HTTP/1.1 WebSocket upgrade request
    my $request = "GET $path HTTP/1.1\r\n";
    $request .= "Host: $authority\r\n";
    $request .= "Upgrade: websocket\r\n";
    $request .= "Connection: Upgrade\r\n";

    # Generate a dummy Sec-WebSocket-Key (backend will accept it)
    $request .= "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n";
    $request .= "Sec-WebSocket-Version: 13\r\n";

    # Add other headers (skip connection-related ones)
    foreach my $hdr (@otherHeaders) {
        next if($hdr =~ /^(connection|upgrade|sec-websocket)/i);
        $request .= "$hdr\r\n";
    }

    $request .= "\r\n";

    # Note: PAGECAMEL overhead is sent once per pooled connection in createPooledBackend()
    return $request;
}

# Backend connection pooling methods inherited from BaseHTTPHandler
# Note: Each HTTP3Handler instance has its own pool, isolated per-client (per QUIC connection)

sub handleBackendData($self, $server, $socket, $toclientbufferRef, $maxBufferSize) {
    # Find which stream this backend belongs to (O(1) reverse lookup)
    if(!defined($self->{backendToStream}->{$socket})) {
        return;
    }
    my $streamId = $self->{backendToStream}->{$socket};

    # Skip if buffer is too large (back-pressure)
    return if(length(${$toclientbufferRef}) >= $maxBufferSize);

    # CRITICAL: Read in a loop until EAGAIN to avoid 2000+ select iterations for large files
    # Each read is 64KB to reduce syscall overhead while staying under common socket buffer sizes
    my $totalBytesRead = 0;
    my $maxReadPerCall = 4_000_000;  # Cap at 4MB per handleBackendData call to maintain fairness

    while($totalBytesRead < $maxReadPerCall) {
        # Check if congestion-blocked - if so, stop reading until data drains
        if($self->{streamCongestionBlocked}->{$streamId}) {
            last;
        }

        my $buf;
        my $bytesRead = $socket->sysread($buf, 65_536);  # 64KB per read

        if(!defined($bytesRead)) {
            # EAGAIN/EWOULDBLOCK or other error - no more data available
            if($ERRNO{EAGAIN} || $ERRNO{EWOULDBLOCK}) {
                last;  # No more data, exit loop
            }
            # Actual error
            $self->{backenddisconnects}->{$streamId} = 1;
            $self->processBackendResponse($server, $streamId);
            return;
        }

        if($bytesRead == 0) {
            # Backend disconnected
            $self->{backenddisconnects}->{$streamId} = 1;
            $self->processBackendResponse($server, $streamId);
            return;
        }

        $totalBytesRead += $bytesRead;

        # Track total bytes read from backend
        $self->{backendBytesRead}->{$streamId} //= 0;
        $self->{backendBytesRead}->{$streamId} += $bytesRead;

        # Append to response buffer
        $self->{streamResponses}->{$streamId} .= $buf;

        # Process response after each chunk to handle headers and push data to nghttp3
        $self->processBackendResponse($server, $streamId);
    }

    # Log every 4MB milestone
    my $bytesSent = $self->{streamBytesSent}->{$streamId} // 0;
    my $curMB = int($bytesSent / 4_000_000) * 4;
    my $prevMB = int(($bytesSent - $totalBytesRead) / 4_000_000) * 4;
    if($totalBytesRead > 0 && $curMB > $prevMB) {
        my $responseLen = length($self->{streamResponses}->{$streamId} // '');
        print STDERR "DEBUG handleBackendData: stream=$streamId bytesSent=${bytesSent} buffered=$responseLen readThisCall=$totalBytesRead\n";
    }

    return;
}

sub processBackendResponse($self, $server, $streamId) {
    my $state = $self->{streamStates}->{$streamId} // '';
    my $response = $self->{streamResponses}->{$streamId} // '';

    if($state eq 'waiting_response') {
        # Look for end of headers
        my $headerEnd = index($response, "\r\n\r\n");
        return if($headerEnd < 0);  # Not yet complete

        my $headerBlock = substr($response, 0, $headerEnd);
        my $body = substr($response, $headerEnd + 4);

        # Parse status line and headers
        my @lines = split(/\r\n/, $headerBlock);
        my $statusLine = shift @lines;

        my ($httpVersion, $status, $statusText) = $statusLine =~ m{^HTTP/(\S+)\s+(\d+)\s*(.*)$};
        $status //= 500;

        # Build header array for HTTP/3
        my @responseHeaders;
        my $contentLength;

        foreach my $line (@lines) {
            my ($name, $value) = split(/:\s*/, $line, 2);
            next unless(defined($name) && defined($value));

            $name = lc($name);

            # Skip hop-by-hop headers
            next if($name eq 'connection');
            next if($name eq 'transfer-encoding');
            next if($name eq 'keep-alive');

            if($name eq 'content-length') {
                $contentLength = $value;
            }

            push @responseHeaders, $name, $value;
        }

        # Check for WebSocket upgrade response
        if($self->{streamStates}->{$streamId} eq 'tunnel_pending' ||
           ($status == 101 && grep { $_ eq 'upgrade' } @responseHeaders)) {
            # WebSocket accepted - enter tunnel mode
            $self->{streamStates}->{$streamId} = 'tunnel_active';

            # Send 200 OK for HTTP/3 tunnel (no content-length)
            my @tunnelHeaders = grep { $_ ne 'content-length' } @responseHeaders;
            my $tunnel = $server->tunnel_response($streamId, 200, \@tunnelHeaders);
            $self->{streamTunnels}->{$streamId} = $tunnel;

            # Forward any remaining data
            if(length($body)) {
                my $bytesWritten = $tunnel->send($body);
                if(defined($bytesWritten) && $bytesWritten > 0 && $bytesWritten < length($body)) {
                    # Partial write - keep unsent portion
                    $self->{streamResponses}->{$streamId} = substr($body, $bytesWritten);
                } elsif(!defined($bytesWritten) || $bytesWritten <= 0) {
                    # Flow control blocked - keep entire body
                    $self->{streamResponses}->{$streamId} = $body;
                } else {
                    $self->{streamResponses}->{$streamId} = '';
                }
            } else {
                $self->{streamResponses}->{$streamId} = '';
            }
            return;
        }

        # Determine if we should stream or buffer
        my $shouldStream = 0;
        if(defined($contentLength) && $contentLength > 1_000_000) {
            $shouldStream = 1;
        }

        if($shouldStream) {
            # Streaming mode
            $self->{streamStates}->{$streamId} = 'streaming';
            $self->{streamContentLength}->{$streamId} = $contentLength;
            $self->{streamBytesSent}->{$streamId} = 0;

            my $stream = $server->response_stream($streamId, $status, \@responseHeaders);
            $self->{streamStreams}->{$streamId} = $stream;

            if(length($body)) {
                my $bytesWritten = $stream->send($body);
                if(defined($bytesWritten) && $bytesWritten > 0) {
                    $self->{streamBytesSent}->{$streamId} += $bytesWritten;
                    if($bytesWritten < length($body)) {
                        # Partial write - keep unsent portion in buffer (DON'T set congestion-blocked)
                        $self->{streamResponses}->{$streamId} = substr($body, $bytesWritten);
                    } else {
                        $self->{streamResponses}->{$streamId} = '';
                    }
                } else {
                    # Flow control blocked (0 bytes) - keep entire body in buffer
                    $self->{streamResponses}->{$streamId} = $body;
                    # Only set congestion-blocked when completely blocked (0 bytes)
                    $self->{streamCongestionBlocked}->{$streamId} = 1;
                }
            } else {
                $self->{streamResponses}->{$streamId} = '';
            }
        } else {
            # Buffering mode - wait for complete response or disconnect
            if($self->{backenddisconnects}->{$streamId}) {
                # Send complete response
                $server->response($streamId, $status, \@responseHeaders, $body);
                # Don't cleanup immediately - nghttp3 may still have buffered data
                # Mark as pending flush - cleanupStream will be called when buffer is empty
                $self->{streamPendingFlush}->{$streamId} = 1;
                $self->{streamResponses}->{$streamId} = '';  # Clear handler buffer
            } else {
                # Check if we have complete response
                if(defined($contentLength) && length($body) >= $contentLength) {
                    $body = substr($body, 0, $contentLength);
                    $server->response($streamId, $status, \@responseHeaders, $body);
                    # Don't cleanup immediately - nghttp3 may still have buffered data
                    $self->{streamPendingFlush}->{$streamId} = 1;
                    $self->{streamResponses}->{$streamId} = '';
                }
            }
        }
    } elsif($state eq 'streaming') {
        # Forward data to stream with flow control handling
        my $stream = $self->{streamStreams}->{$streamId};
        if(defined($stream) && length($response)) {
            my $bytesWritten = $stream->send($response);

            if(defined($bytesWritten) && $bytesWritten > 0) {
                # Successfully sent some bytes
                $self->{streamBytesSent}->{$streamId} += $bytesWritten;
                # Clear congestion-blocked since we made progress
                delete $self->{streamCongestionBlocked}->{$streamId};

                if($bytesWritten >= length($response)) {
                    # All data sent - clear buffer
                    $self->{streamResponses}->{$streamId} = '';
                } else {
                    # Partial write - keep unsent portion, but DON'T set congestion-blocked
                    # Partial write means "sent some, buffer full for now" - not "totally blocked"
                    # We should continue reading from backend and let next iteration send more
                    $self->{streamResponses}->{$streamId} = substr($response, $bytesWritten);
                }
            } else {
                # bytesWritten is 0 or negative - completely flow control blocked
                # This is the ONLY case where we set congestion-blocked for back-pressure
                $self->{streamCongestionBlocked}->{$streamId} = 1;
            }
        }

        # Check if complete - only close when buffer is empty
        my $contentLength = $self->{streamContentLength}->{$streamId};
        my $bytesSent = $self->{streamBytesSent}->{$streamId};
        my $bufferEmpty = length($self->{streamResponses}->{$streamId} // '') == 0;

        if($bufferEmpty &&
           ($self->{backenddisconnects}->{$streamId} ||
            (defined($contentLength) && $bytesSent >= $contentLength))) {
            $stream->close() if(defined($stream));
            $self->cleanupStream($streamId);
        }
    } elsif($state eq 'tunnel_active') {
        # Forward data through tunnel with flow control handling
        my $tunnel = $self->{streamTunnels}->{$streamId};
        if(defined($tunnel) && length($response)) {
            my $bytesWritten = $tunnel->send($response);
            if(defined($bytesWritten) && $bytesWritten > 0) {
                if($bytesWritten >= length($response)) {
                    $self->{streamResponses}->{$streamId} = '';
                } else {
                    # Partial write - keep unsent portion
                    $self->{streamResponses}->{$streamId} = substr($response, $bytesWritten);
                }
            }
            # If blocked, keep buffer as-is
        }

        if($self->{backenddisconnects}->{$streamId}) {
            $tunnel->close() if(defined($tunnel));
            $self->cleanupStream($streamId);
        }
    }

    return;
}

sub writeToBackends($self, $blocksize, $loopcount, $finishcountdown, $canWriteHashRef) {
    # Round-robin fair writes: one block (16KB) per stream per pass
    # This ensures all streams make progress, preventing one large stream from starving others
    my $maxBytesPerIteration = 1_000_000;  # 1MB total limit per iteration
    my $totalBytesThisIteration = 0;
    my $madeProgress = 1;

    while($madeProgress && $totalBytesThisIteration < $maxBytesPerIteration) {
        $madeProgress = 0;

        foreach my $streamId (keys %{$self->{tobackendbuffers}}) {
            my $backend = $self->{streamBackends}->{$streamId};
            next unless(defined($backend));

            # Skip disconnected backends
            next if($self->{backenddisconnects}->{$streamId});

            # Only write if socket is writable
            next unless($canWriteHashRef->{$backend});

            my $tobackendbuffer = \$self->{tobackendbuffers}->{$streamId};
            next unless(defined(${$tobackendbuffer}) && length(${$tobackendbuffer}));

            # Write ONE block per stream per pass (fair round-robin)
            my $bufferLen = length(${$tobackendbuffer});
            my $towrite = $bufferLen < $blocksize ? $bufferLen : $blocksize;

            my $written;
            eval {
                $written = syswrite($backend, ${$tobackendbuffer}, $towrite);
            };

            if($EVAL_ERROR || !defined($written)) {
                $self->{backenddisconnects}->{$streamId} = 1;
                next;
            }

            if($written > 0) {
                ${$tobackendbuffer} = substr(${$tobackendbuffer}, $written);
                $totalBytesThisIteration += $written;
                $madeProgress = 1;
            }
        }
    }

    return;
}

sub flushPendingStreams($self, $server, $sendPacketsCallback = undef) {
    # ALWAYS try to send packets first - this ensures any data in QUIC's buffer
    # gets sent out, which triggers ACKs that open the congestion window
    $sendPacketsCallback->() if($sendPacketsCallback);

    # Flush any data buffered in nghttp3 to QUIC
    # This is CRITICAL: data that was pushed to nghttp3 but couldn't be flushed
    # (due to congestion) needs to be drained here when cwnd opens
    # IMPORTANT: Pass sendPacketsCallback so packets are sent immediately after each write
    # This prevents RTT inflation from packets sitting in pending_stream_packets
    my $totalFlushed = $server->flush_pending_data($sendPacketsCallback);

    # ALWAYS send packets after flush attempt - QUIC may have ACKs, probes,
    # or other control frames to send even if we couldn't add new data
    $sendPacketsCallback->() if($sendPacketsCallback);

    # Retry sending buffered data for streams that may have been blocked by flow control
    # Called periodically from main loop after QUIC ACKs open up the send window
    # $sendPacketsCallback: optional callback to send UDP packets during flush
    my @streams = keys %{$self->{streamResponses}};
    foreach my $streamId (@streams) {
        my $response = $self->{streamResponses}->{$streamId};
        my $buflen = defined($response) ? length($response) : 0;
        my $state = $self->{streamStates}->{$streamId} // '';

        next unless($buflen > 0);

        if($state eq 'streaming') {
            my $stream = $self->{streamStreams}->{$streamId};
            next unless(defined($stream));

            # NOTE: Removed cwnd check that was causing deadlock.
            # Previously we checked cwndLeft < 1200 and skipped streams, but this
            # caused a circular dependency: can't send → no packets → no ACKs → cwnd stays small.
            # Now we always try to send and let QUIC's internal flow control handle it.
            # The congestionBlocked flag is cleared here and we try to send below.
            delete $self->{streamCongestionBlocked}->{$streamId};

            # Loop until we can't send more (congestion control blocks)
            # Limit writes per call to prevent overwhelming the receiver's UDP buffer
            my $totalWritten = 0;
            my $writeCount = 0;
            my $maxWritesPerFlush = 10;  # Limit to ~12KB per flush to allow pacing

            while(length($self->{streamResponses}->{$streamId} // '') > 0 && $writeCount < $maxWritesPerFlush) {
                my $toSend = $self->{streamResponses}->{$streamId};
                my $bytesWritten = $stream->send($toSend);

                if(defined($bytesWritten) && $bytesWritten > 0) {
                    $totalWritten += $bytesWritten;
                    $writeCount++;
                    $self->{streamBytesSent}->{$streamId} += $bytesWritten;
                    # Clear congestion-blocked flag since we made progress
                    delete $self->{streamCongestionBlocked}->{$streamId};

                    if($bytesWritten >= length($toSend)) {
                        $self->{streamResponses}->{$streamId} = '';
                    } else {
                        $self->{streamResponses}->{$streamId} = substr($toSend, $bytesWritten);
                    }

                    # CRITICAL: Send packets IMMEDIATELY after EVERY write to minimize RTT inflation
                    # $stream->send() → send_body_chunk() → flush_pending_data() queues packets
                    # but doesn't send them. We must send immediately to get accurate RTT measurements.
                    $sendPacketsCallback->() if($sendPacketsCallback);
                } else {
                    # Congestion blocked (or error) - send any pending packets and exit
                    # Don't retry immediately - we need to wait for ACKs from the network
                    # The main loop will process ACKs and call flushPendingStreams again
                    $self->{_flushBlockedCount} //= 0;
                    $self->{_flushBlockedCount}++;
                    # Only log occasionally to avoid flooding
                    if ($self->{_flushBlockedCount} % 500 == 1) {
                        my $cwndLeft = $self->{quicConnection}->{quic_conn}->get_cwnd_left();
                        print STDERR "DEBUG flushPending: BLOCKED (count=$self->{_flushBlockedCount}) cwndLeft=$cwndLeft toSend=" . length($toSend) . "\n";
                    }
                    $sendPacketsCallback->() if($sendPacketsCallback);

                    # Mark stream as congestion-blocked (for back-pressure)
                    $self->{streamCongestionBlocked}->{$streamId} = 1;
                    last;
                }
            }

            # Check if complete - only close when ALL buffered data has been sent
            my $contentLength = $self->{streamContentLength}->{$streamId};
            my $bytesSent = $self->{streamBytesSent}->{$streamId};
            my $bufferEmpty = length($self->{streamResponses}->{$streamId} // '') == 0;

            # Close stream when buffer is empty AND either:
            # 1. Backend disconnected (finished sending), OR
            # 2. We've sent all content-length bytes
            if($bufferEmpty &&
               ($self->{backenddisconnects}->{$streamId} ||
                (defined($contentLength) && $bytesSent >= $contentLength))) {
                $stream->close() if(defined($stream));
                $self->cleanupStream($streamId);
            }
        } elsif($state eq 'tunnel_active') {
            my $tunnel = $self->{streamTunnels}->{$streamId};
            next unless(defined($tunnel));

            # Loop until we can't send more
            while(length($self->{streamResponses}->{$streamId} // '') > 0) {
                my $toSend = $self->{streamResponses}->{$streamId};
                my $bytesWritten = $tunnel->send($toSend);

                if(defined($bytesWritten) && $bytesWritten > 0) {
                    if($bytesWritten >= length($toSend)) {
                        $self->{streamResponses}->{$streamId} = '';
                    } else {
                        $self->{streamResponses}->{$streamId} = substr($toSend, $bytesWritten);
                    }
                } else {
                    last;
                }
            }

            if($self->{backenddisconnects}->{$streamId}) {
                $tunnel->close() if(defined($tunnel));
                $self->cleanupStream($streamId);
            }
        }
    }

    # Flush nghttp3's internal buffer (for complete responses pushed directly to nghttp3)
    # This drains DATA frames that nghttp3 has queued but not yet sent to QUIC
    $server->flush_pending_data();
    $sendPacketsCallback->() if($sendPacketsCallback);

    # Handle pending flush streams (buffered responses awaiting nghttp3 drain)
    foreach my $streamId (keys %{$self->{streamPendingFlush}}) {
        # Check if nghttp3's buffer for this stream is empty
        my $pendingSize = $server->{http3_conn}->get_stream_buffer_size($streamId);
        if($pendingSize == 0) {
            # Buffer fully drained - cleanup stream
            $self->cleanupStream($streamId);
            delete $self->{streamPendingFlush}->{$streamId};
        }
    }

    # Return true if we should be called again (more work to do)
    # Check if we flushed data from nghttp3 - if so, there might be more
    my $hasPendingData = 0;
    foreach my $streamId (keys %{$self->{streamResponses}}) {
        if(length($self->{streamResponses}->{$streamId} // '') > 0) {
            $hasPendingData = 1;
            last;
        }
    }

    # Also check for pending flush streams (nghttp3 buffer not yet drained)
    my $hasPendingFlush = scalar(keys %{$self->{streamPendingFlush}}) > 0;

    # Return true if:
    # 1. We flushed data from nghttp3 (more might be waiting), OR
    # 2. We have pending data in streamResponses that isn't blocked
    my $hasBlockedStreams = scalar(keys %{$self->{streamCongestionBlocked}}) > 0;
    return $totalFlushed > 0 || (($hasPendingData || $hasPendingFlush) && !$hasBlockedStreams);
}

sub cleanupStream($self, $streamId) {
    my $bytesSent = $self->{streamBytesSent}->{$streamId} // 0;
    # Determine if backend connection is reusable
    # WebSocket tunnels are NOT reusable (bidirectional data flow)
    # Backend disconnects are NOT reusable (connection was closed)
    my $isTunnel = defined($self->{streamTunnels}->{$streamId});
    my $backendClosed = $self->{backenddisconnects}->{$streamId} // 0;
    my $reusable = !$isTunnel && !$backendClosed;

    # Release backend to pool (or close if not reusable)
    my $backend = $self->{streamBackends}->{$streamId};
    if(defined($backend)) {
        $self->releaseBackend($streamId, $reusable);
    } else {
        # No backend - just clean up the mapping
        delete $self->{streamBackends}->{$streamId};
    }

    # Clean up stream state
    delete $self->{streamResponses}->{$streamId};
    delete $self->{streamStates}->{$streamId};
    delete $self->{streamStreams}->{$streamId};
    delete $self->{streamTunnels}->{$streamId};
    delete $self->{tobackendbuffers}->{$streamId};
    delete $self->{backenddisconnects}->{$streamId};
    delete $self->{streamContentLength}->{$streamId};
    delete $self->{streamBytesSent}->{$streamId};
    delete $self->{streamCongestionBlocked}->{$streamId};
    delete $self->{streamPendingFlush}->{$streamId};

    return;
}

sub cleanup($self) {
    # Clean up all active streams
    foreach my $streamId (keys %{$self->{streamBackends}}) {
        $self->cleanupStream($streamId);
    }

    # Clean up pending flush streams (may not have backends)
    foreach my $streamId (keys %{$self->{streamPendingFlush}}) {
        $self->cleanupStream($streamId);
    }

    # Close all pooled backend connections
    while(my $backend = pop @{$self->{backendPool}}) {
        eval { close($backend); };
    }

    # Clear waiting queue
    $self->{waitingForBackend} = [];

    return;
}

1;

__END__

=head1 NAME

PageCamel::CMDLine::WebFrontend::HTTP3Handler - HTTP/3 request handler

=head1 SYNOPSIS

    use PageCamel::CMDLine::WebFrontend::HTTP3Handler;

    my $handler = PageCamel::CMDLine::WebFrontend::HTTP3Handler->new(
        quicConnection    => $quicConn,
        backendSocketPath => '/run/pagecamel/backend.sock',
        pagecamelInfo     => {
            lhost    => '192.168.1.1',
            lport    => 443,
            peerhost => '10.0.0.1',
            peerport => 54321,
        },
        sendPacketCallback => sub($data, $addr) { ... },
    );

    $handler->run();

=head1 DESCRIPTION

This module handles HTTP/3 requests over a QUIC connection, translating
them to HTTP/1.1 for backend processing. It supports:

=over 4

=item * Regular HTTP/3 requests

=item * WebSocket over HTTP/3 (RFC 9220 Extended CONNECT)

=item * Streaming responses for large content

=item * Proper back-pressure handling

=back

=head1 METHODS

=head2 new(%config)

Create a new HTTP/3 handler.

Required configuration:

=over 4

=item quicConnection - PageCamel::Protocol::QUIC::Connection object

=item backendSocketPath - Path to backend Unix socket

=item pagecamelInfo - Hash with lhost, lport, peerhost, peerport

=back

Optional:

=over 4

=item sendPacketCallback - Callback to send UDP packets

=item errorPage590Html - HTML for backend-not-running error

=back

=head2 run()

Run the handler's main event loop.

=head1 SEE ALSO

L<PageCamel::CMDLine::WebFrontend::HTTP2Handler>,
L<PageCamel::Protocol::HTTP3::Server>,
L<PageCamel::Protocol::QUIC::Connection>

=cut
