package PageCamel::CMDLine::WebFrontend::HTTP2Handler;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
use autodie qw( close );
use utf8;
#---AUTOPRAGMAEND---

no warnings 'experimental::args_array_with_signatures';

use Protocol::HTTP2::Server;
use Protocol::HTTP2::Constants qw(:frame_types :flags :states :settings);
use IO::Socket::UNIX;
use IO::Select;
use PageCamel::Helpers::DateStrings;

sub new($class, %config) {
    my $self = bless \%config, $class;

    # Required parameters
    foreach my $key (qw[clientSocket backendSocketPath pagecamelInfo]) {
        if(!defined($self->{$key})) {
            croak("HTTP2Handler: Setting $key is required but not set!");
        }
    }

    # Stream to backend connection mapping
    $self->{streamBackends} = {};
    # Stream to response buffer mapping
    $self->{streamResponses} = {};
    # Stream states
    $self->{streamStates} = {};
    # Stream objects for streaming responses (Protocol::HTTP2::Server::Stream)
    $self->{streamStreams} = {};
    # Tunnel objects for WebSocket (Protocol::HTTP2::Server::Tunnel)
    $self->{streamTunnels} = {};
    # Per-stream buffers for data going to backends
    $self->{tobackendbuffers} = {};
    # Per-stream backend disconnect flags
    $self->{backenddisconnects} = {};
    # Counter for streams handled (used for exit detection)
    $self->{streamsHandled} = 0;
    # Per-stream content-length tracking for streaming mode
    $self->{streamContentLength} = {};
    $self->{streamBytesSent} = {};

    return $self;
}

sub run($self) {
    my $client = $self->{clientSocket};
    my $select = IO::Select->new();
    $select->add($client);

    # Create HTTP/2 server instance with extended CONNECT enabled (RFC 8441)
    # Note: SETTINGS_ENABLE_CONNECT_PROTOCOL must be passed in constructor
    # because the initial SETTINGS frame is queued during construction
    my $server;
    $server = Protocol::HTTP2::Server->new(
        settings => {
            &SETTINGS_ENABLE_CONNECT_PROTOCOL => 1,
        },
        on_request => sub ($streamId, $headers, $data) {
            $self->handleRequest($server, $streamId, $headers, $data);
        },
        on_connect_request => sub ($streamId, $headers, $data = undef) {
            $self->handleConnectRequest($server, $streamId, $headers);
        },
    );

    # Buffering variables - same names as HTTP/1.1 implementation
    my $toclientbuffer = '';
    my $clientdisconnect = 0;
    my $finishcountdown = 0;
    my $max_buffer_size = 50_000_000;  # 50MB buffer limit
    my $blocksize = 16_384;            # SSL/TLS block size limit

    # Queue initial SETTINGS frame
    while(my $chunk = $server->next_frame()) {
        $toclientbuffer .= $chunk;
    }

    # Main event loop
    my $done = 0;
    while(!$done) {
        # Build list of sockets to monitor
        # Note: Don't use connected() check - socket may have buffered data even after peer closes
        my @monitorSockets = ($client);
        foreach my $streamId (keys %{$self->{streamBackends}}) {
            my $backend = $self->{streamBackends}->{$streamId};
            if(defined($backend)) {
                push @monitorSockets, $backend;
            }
        }

        # Calculate total backend buffer size for back-pressure
        my $totalBackendBufferSize = 0;
        foreach my $streamId (keys %{$self->{tobackendbuffers}}) {
            $totalBackendBufferSize += length($self->{tobackendbuffers}->{$streamId} // '');
        }

        # Adaptive wait time - short when buffers have data, longer when empty
        my $waittime = 0.1;
        if(length($toclientbuffer) || $totalBackendBufferSize) {
            $waittime = 0.001;
        }

        $select = IO::Select->new(@monitorSockets);
        $ERRNO = 0;
        my @ready = $select->can_read($waittime);

        # Handle EINTR (signal interrupted call) - just continue
        if(!@ready && $!{EINTR}) {
            next;
        }

        # Only send PING if we have active streams (don't keep connection alive after response)
        my $activeStreamsForPing = scalar(keys %{$self->{streamBackends}}) +
                                   scalar(keys %{$self->{streamStreams}}) +
                                   scalar(keys %{$self->{streamTunnels}});
        if(!@ready && !length($toclientbuffer) && !$totalBackendBufferSize && $activeStreamsForPing > 0) {
            # True timeout with no pending data but active streams - send PING to keep connection alive
            $server->ping();
            while(my $chunk = $server->next_frame()) {
                $toclientbuffer .= $chunk;
            }
        }

        foreach my $socket (@ready) {
            if($socket == $client) {
                # Skip reading from client if toclientbuffer is too large (back-pressure)
                next if(length($toclientbuffer) >= $max_buffer_size);

                # Data from HTTP/2 client
                my $buf;
                my $bytesRead = $client->sysread($buf, 16384);

                if(!defined($bytesRead) || $bytesRead == 0) {
                    # Client disconnected
                    $clientdisconnect = 1;
                } else {
                    # Feed data to HTTP/2 parser
                    $server->feed($buf);

                    # Queue any pending response frames to buffer
                    while(my $chunk = $server->next_frame()) {
                        $toclientbuffer .= $chunk;
                    }
                }
            } else {
                # Data from a backend connection
                $self->handleBackendData($server, $socket, \$toclientbuffer, $max_buffer_size);
            }
        }

        # Write to client from buffer with proper partial write handling
        my $loopcount = int(10_000_000 / $blocksize);  # Write at max ~10MB in one loop
        my $sendcount = $loopcount;
        my $client_offset = 0;

        while($sendcount) {
            my $remaining = length($toclientbuffer) - $client_offset;
            if($remaining > 0 && !$clientdisconnect) {
                my $written;
                my $towrite = $remaining < $blocksize ? $remaining : $blocksize;

                eval {
                    $written = syswrite($client, $toclientbuffer, $towrite, $client_offset);
                };
                if($EVAL_ERROR) {
                    print STDERR "HTTP2Handler: Write error to client: $EVAL_ERROR\n";
                } else {
                    if($finishcountdown) {
                        # Reset countdown if we're still sending data
                        $finishcountdown = time + 20;
                    }
                }
                if(defined($written) && $written) {
                    $client_offset += $written;
                } else {
                    last;
                }
            } else {
                last;
            }
            $sendcount--;
        }
        # Remove written data from buffer
        if($client_offset > 0) {
            $toclientbuffer = substr($toclientbuffer, $client_offset);
        }

        # Write to backends from per-stream buffers
        $self->writeToBackends($blocksize, $loopcount, $finishcountdown);

        # Handle client disconnect
        if($clientdisconnect) {
            $done = 1;
        }

        # Check if all streams are complete (no active backends/streams/tunnels)
        my $activeStreams = scalar(keys %{$self->{streamBackends}}) +
                            scalar(keys %{$self->{streamStreams}}) +
                            scalar(keys %{$self->{streamTunnels}});

        # Start finish countdown when all streams complete but client buffer has data
        if(!$finishcountdown && $self->{streamsHandled} > 0 && $activeStreams == 0) {
            if(!length($toclientbuffer)) {
                $done = 1;
            } else {
                $finishcountdown = time + 20;
            }
        }

        # Handle finish countdown
        if($finishcountdown > 0) {
            if(!length($toclientbuffer)) {
                $done = 1;
            } elsif($finishcountdown <= time) {
                $done = 1;
            }
        }
    }

    # Debug: log exit reason
    print STDERR getISODate() . " HTTP2Handler [$self->{pagecamelInfo}->{peerhost}]: Exiting main loop (streamsHandled=$self->{streamsHandled}, clientdisconnect=$clientdisconnect, bufferLen=" . length($toclientbuffer) . ")\n";

    # Cleanup all backend connections
    $self->cleanup();

    return;
}

sub handleRequest($self, $server, $streamId, $headers, $data) {
    # Track that we've handled a request
    $self->{streamsHandled}++;

    # Convert HTTP/2 headers to HTTP/1.1 request
    my $request = $self->translateRequest($streamId, $headers, $data);

    # Connect to backend
    my $backend = $self->connectBackend($streamId);
    if(!defined($backend)) {
        # Send 502 Bad Gateway
        $server->response(
            ':status' => 502,
            stream_id => $streamId,
        );
        return;
    }

    # Buffer request for backend (will be written in writeToBackends)
    $self->{tobackendbuffers}->{$streamId} = $request;

    # Mark stream as waiting for response
    $self->{streamStates}->{$streamId} = 'waiting_response';
    $self->{streamResponses}->{$streamId} = '';

    return;
}

sub handleConnectRequest($self, $server, $streamId, $headers) {
    # Track that we've handled a request
    $self->{streamsHandled}++;

    # Extended CONNECT for WebSocket over HTTP/2
    my %h;
    # Headers come as flat list: [key, value, key, value, ...]
    for(my $i = 0; $i < scalar(@{$headers}); $i += 2) {
        $h{$headers->[$i]} = $headers->[$i + 1];
    }

    my $protocol = $h{':protocol'} // '';
    if($protocol ne 'websocket') {
        # Only WebSocket CONNECT is supported
        $server->response(
            ':status' => 501,
            stream_id => $streamId,
        );
        return;
    }

    # Translate to HTTP/1.1 WebSocket upgrade
    my $request = $self->translateWebsocketUpgrade($streamId, $headers);

    # Connect to backend
    my $backend = $self->connectBackend($streamId);
    if(!defined($backend)) {
        $server->response(
            ':status' => 502,
            stream_id => $streamId,
        );
        return;
    }

    # Buffer WebSocket upgrade request for backend
    $self->{tobackendbuffers}->{$streamId} = $request;

    # Mark stream as tunnel pending
    $self->{streamStates}->{$streamId} = 'tunnel_pending';
    $self->{streamResponses}->{$streamId} = '';

    return;
}

sub translateRequest($self, $streamId, $headers, $data) {
    my %h;
    my @orderHeaders;
    # Headers come as flat list: [key, value, key, value, ...]
    for(my $i = 0; $i < scalar(@{$headers}); $i += 2) {
        my $name = $headers->[$i];
        my $value = $headers->[$i + 1];
        $h{$name} = $value;
        if($name !~ /^:/) {
            push @orderHeaders, [$name, $value];
        }
    }

    my $method = $h{':method'} // 'GET';
    my $path = $h{':path'} // '/';
    my $authority = $h{':authority'} // 'localhost';

    # Build PAGECAMEL overhead header
    my $info = $self->{pagecamelInfo};
    my $overhead = "PAGECAMEL $info->{lhost} $info->{lport} $info->{peerhost} $info->{peerport} $info->{usessl} $info->{pid} HTTP/2\r\n";

    # Build HTTP/1.1 request
    my $request = "$method $path HTTP/1.1\r\n";
    $request .= "Host: $authority\r\n";

    # Add other headers
    foreach my $pair (@orderHeaders) {
        my ($name, $value) = @{$pair};
        # Skip pseudo-headers and connection-specific headers
        next if($name =~ /^:/);
        next if(lc($name) eq 'connection');
        next if(lc($name) eq 'keep-alive');
        next if(lc($name) eq 'transfer-encoding');
        next if(lc($name) eq 'upgrade');
        $request .= "$name: $value\r\n";
    }

    # Add content-length if we have data
    if(defined($data) && length($data)) {
        $request .= "Content-Length: " . length($data) . "\r\n";
    }

    $request .= "\r\n";

    # Prepend PAGECAMEL overhead
    $request = $overhead . $request;

    # Add body if present
    if(defined($data) && length($data)) {
        $request .= $data;
    }

    return $request;
}

sub translateWebsocketUpgrade($self, $streamId, $headers) {
    my %h;
    my @orderHeaders;
    # Headers come as flat list: [key, value, key, value, ...]
    for(my $i = 0; $i < scalar(@{$headers}); $i += 2) {
        my $name = $headers->[$i];
        my $value = $headers->[$i + 1];
        $h{$name} = $value;
        if($name !~ /^:/) {
            push @orderHeaders, [$name, $value];
        }
    }

    my $path = $h{':path'} // '/';
    my $authority = $h{':authority'} // 'localhost';

    # Build PAGECAMEL overhead header
    my $info = $self->{pagecamelInfo};
    my $overhead = "PAGECAMEL $info->{lhost} $info->{lport} $info->{peerhost} $info->{peerport} $info->{usessl} $info->{pid} HTTP/2\r\n";

    # Generate Sec-WebSocket-Key
    my $key = $self->generateWebsocketKey();

    # Build HTTP/1.1 WebSocket upgrade request
    my $request = "GET $path HTTP/1.1\r\n";
    $request .= "Host: $authority\r\n";
    $request .= "Upgrade: websocket\r\n";
    $request .= "Connection: Upgrade\r\n";
    $request .= "Sec-WebSocket-Key: $key\r\n";
    $request .= "Sec-WebSocket-Version: 13\r\n";

    # Add other headers from the CONNECT request
    foreach my $pair (@orderHeaders) {
        my ($name, $value) = @{$pair};
        next if($name =~ /^:/);
        next if(lc($name) eq 'host');
        $request .= "$name: $value\r\n";
    }

    $request .= "\r\n";

    # Prepend PAGECAMEL overhead
    $request = $overhead . $request;

    # Store key for validation
    $self->{streamWebsocketKey}->{$streamId} = $key;

    return $request;
}

sub generateWebsocketKey($self) {
    my @chars = ('A'..'Z', 'a'..'z', '0'..'9', '+', '/');
    my $key = '';
    for(my $i = 0; $i < 16; $i++) {
        $key .= $chars[int(rand(scalar @chars))];
    }
    require MIME::Base64;
    return MIME::Base64::encode_base64($key, '');
}

sub connectBackend($self, $streamId) {
    my $backend = IO::Socket::UNIX->new(
        Peer    => $self->{backendSocketPath},
        Timeout => 15,
    );

    if(!defined($backend)) {
        carp("HTTP2Handler: Failed to connect to backend: $ERRNO");
        return;
    }

    $self->{streamBackends}->{$streamId} = $backend;

    return $backend;
}

sub handleBackendData($self, $server, $backend, $toclientbufferRef, $max_buffer_size) {
    # Find which stream this backend belongs to
    my $streamId;
    foreach my $sid (keys %{$self->{streamBackends}}) {
        if($self->{streamBackends}->{$sid} == $backend) {
            $streamId = $sid;
            last;
        }
    }

    if(!defined($streamId)) {
        return;
    }

    # Back-pressure: skip reading if client buffer is too large
    if(length($$toclientbufferRef) >= $max_buffer_size) {
        return;
    }

    my $buf;
    my $bytesRead = $backend->sysread($buf, 65536);

    if(!defined($bytesRead) || $bytesRead == 0) {
        # Backend closed connection
        print STDERR getISODate() . " HTTP2Handler [$self->{pagecamelInfo}->{peerhost}]: Backend closed for stream=$streamId (bytesRead=" . ($bytesRead // 'undef') . ")\n";
        $self->{backenddisconnects}->{$streamId} = 1;
        $self->cleanupStream($server, $streamId, $toclientbufferRef);
        return;
    }

    my $state = $self->{streamStates}->{$streamId} // 'waiting_response';

    if($state eq 'tunnel') {
        # Tunnel mode - forward raw data as DATA frames via Tunnel object
        my $tunnel = $self->{streamTunnels}->{$streamId};
        if(defined($tunnel)) {
            $tunnel->send($buf);
            while(my $chunk = $server->next_frame()) {
                $$toclientbufferRef .= $chunk;
            }
        }
    } elsif($state eq 'tunnel_pending' || $state eq 'waiting_response') {
        # Accumulate response
        $self->{streamResponses}->{$streamId} .= $buf;

        # Check if we have complete headers
        if($self->{streamResponses}->{$streamId} =~ /\r\n\r\n/) {
            $self->processBackendResponse($server, $streamId, $toclientbufferRef);
        }
    } elsif($state eq 'streaming') {
        # Streaming response body - send as DATA frames via Stream object
        print STDERR getISODate() . " HTTP2Handler [$self->{pagecamelInfo}->{peerhost}]: Streaming data for stream=$streamId, bytes=" . length($buf) . "\n";
        my $stream = $self->{streamStreams}->{$streamId};
        if(defined($stream)) {
            $stream->send($buf);
            $self->{streamBytesSent}->{$streamId} += length($buf);
            while(my $chunk = $server->next_frame()) {
                $$toclientbufferRef .= $chunk;
            }

            # Check if we've sent all content-length bytes - if so, send END_STREAM now
            my $contentLength = $self->{streamContentLength}->{$streamId};
            my $bytesSent = $self->{streamBytesSent}->{$streamId};
            if(defined($contentLength) && $bytesSent >= $contentLength) {
                print STDERR getISODate() . " HTTP2Handler [$self->{pagecamelInfo}->{peerhost}]: Content-length reached for stream=$streamId ($bytesSent >= $contentLength), sending END_STREAM\n";
                $self->cleanupStream($server, $streamId, $toclientbufferRef);
            }
        }
    }

    return;
}

sub processBackendResponse($self, $server, $streamId, $toclientbufferRef) {
    my $response = $self->{streamResponses}->{$streamId};
    my $state = $self->{streamStates}->{$streamId};

    # Split headers from body
    my ($headerPart, $bodyPart) = split(/\r\n\r\n/, $response, 2);

    # Parse status line and headers
    my @lines = split(/\r\n/, $headerPart);
    my $statusLine = shift @lines;

    my ($proto, $status, $reason) = split(/\s+/, $statusLine, 3);

    # Ensure status is defined (default to 500 if malformed response)
    $status //= 500;

    # Build flat array of headers for Protocol::HTTP2: [name, value, name, value, ...]
    # Note: :status is passed separately to response(), don't include it here
    my @responseHeaders;
    my $contentLength;
    foreach my $line (@lines) {
        my ($name, $value) = split(/:\s*/, $line, 2);
        next if(!defined($name) || !defined($value));
        # Skip hop-by-hop headers
        next if(lc($name) eq 'connection');
        next if(lc($name) eq 'keep-alive');
        next if(lc($name) eq 'transfer-encoding');
        next if(lc($name) eq 'upgrade');
        my $lcname = lc($name);
        push @responseHeaders, $lcname, $value;
        if($lcname eq 'content-length') {
            $contentLength = $value;
        }
    }

    # Debug: log response processing
    print STDERR getISODate() . " HTTP2Handler [$self->{pagecamelInfo}->{peerhost}]: processBackendResponse stream=$streamId status=$status contentLength=" . ($contentLength // 'undef') . " bodyLen=" . length($bodyPart // '') . " state=$state\n";

    if($state eq 'tunnel_pending') {
        # Check if WebSocket upgrade succeeded
        if($status eq '101') {
            # Filter out content-length for tunnel - data flows indefinitely
            my @tunnelHeaders;
            for(my $i = 0; $i < scalar(@responseHeaders); $i += 2) {
                next if(lc($responseHeaders[$i]) eq 'content-length');
                push @tunnelHeaders, $responseHeaders[$i], $responseHeaders[$i + 1];
            }

            # Send HTTP/2 200 OK to client for tunnel using tunnel_response
            my $tunnel = $server->tunnel_response(
                ':status'  => 200,
                stream_id  => $streamId,
                headers    => \@tunnelHeaders,
            );
            $self->{streamTunnels}->{$streamId} = $tunnel;
            $self->{streamStates}->{$streamId} = 'tunnel';
        } else {
            # Upgrade failed, send error response
            $server->response(
                ':status'  => $status,
                stream_id  => $streamId,
                headers    => \@responseHeaders,
                data       => $bodyPart // '',
            );
            $self->cleanupStream($server, $streamId, $toclientbufferRef, 0);  # response() already sent END_STREAM
        }
    } else {
        # Regular HTTP response
        # $contentLength was already extracted during header parsing above
        if(defined($contentLength) && defined($bodyPart) && length($bodyPart) >= $contentLength) {
            # Complete response - use response() which handles END_STREAM
            print STDERR getISODate() . " HTTP2Handler [$self->{pagecamelInfo}->{peerhost}]: Using response() for complete response (stream=$streamId)\n";
            $server->response(
                ':status'  => $status,
                stream_id  => $streamId,
                headers    => \@responseHeaders,
                data       => $bodyPart,
            );
            $self->cleanupStream($server, $streamId, $toclientbufferRef, 0);  # Don't send END_STREAM, response() does it
        } else {
            # Send headers, switch to streaming mode for body using response_stream()
            print STDERR getISODate() . " HTTP2Handler [$self->{pagecamelInfo}->{peerhost}]: Using response_stream() for streaming response (stream=$streamId)\n";
            my $stream = $server->response_stream(
                ':status'  => $status,
                stream_id  => $streamId,
                headers    => \@responseHeaders,
            );
            $self->{streamStreams}->{$streamId} = $stream;
            $self->{streamStates}->{$streamId} = 'streaming';
            # Track content-length for END_STREAM detection
            $self->{streamContentLength}->{$streamId} = $contentLength;
            $self->{streamBytesSent}->{$streamId} = 0;
            # Send any body data we already have
            if(defined($bodyPart) && length($bodyPart)) {
                $stream->send($bodyPart);
                $self->{streamBytesSent}->{$streamId} += length($bodyPart);
            }
        }
    }

    # Queue pending frames to buffer
    while(my $chunk = $server->next_frame()) {
        $$toclientbufferRef .= $chunk;
    }

    # Clear response buffer
    $self->{streamResponses}->{$streamId} = '';

    return;
}

sub cleanupStream($self, $server, $streamId, $toclientbufferRef, $sendEndStream = 1) {
    print STDERR getISODate() . " HTTP2Handler [$self->{pagecamelInfo}->{peerhost}]: cleanupStream stream=$streamId sendEndStream=$sendEndStream\n";

    # Close backend connection
    if(defined($self->{streamBackends}->{$streamId})) {
        eval {
            close($self->{streamBackends}->{$streamId});
        };
        delete $self->{streamBackends}->{$streamId};
    }

    # Send END_STREAM if needed via Stream or Tunnel object
    if($sendEndStream) {
        if(defined($self->{streamStreams}->{$streamId})) {
            $self->{streamStreams}->{$streamId}->close();
        } elsif(defined($self->{streamTunnels}->{$streamId})) {
            $self->{streamTunnels}->{$streamId}->close();
        }
        while(my $chunk = $server->next_frame()) {
            $$toclientbufferRef .= $chunk;
        }
    }

    # Clear state
    delete $self->{streamStates}->{$streamId};
    delete $self->{streamResponses}->{$streamId};
    delete $self->{streamWebsocketKey}->{$streamId};
    delete $self->{streamStreams}->{$streamId};
    delete $self->{streamTunnels}->{$streamId};
    delete $self->{tobackendbuffers}->{$streamId};
    delete $self->{backenddisconnects}->{$streamId};
    delete $self->{streamContentLength}->{$streamId};
    delete $self->{streamBytesSent}->{$streamId};

    return;
}

sub cleanup($self) {
    # Close all backend connections
    foreach my $streamId (keys %{$self->{streamBackends}}) {
        if(defined($self->{streamBackends}->{$streamId})) {
            eval {
                close($self->{streamBackends}->{$streamId});
            };
        }
    }

    $self->{streamBackends} = {};
    $self->{streamStates} = {};
    $self->{streamResponses} = {};
    $self->{streamWebsocketKey} = {};
    $self->{streamStreams} = {};
    $self->{streamTunnels} = {};
    $self->{tobackendbuffers} = {};
    $self->{backenddisconnects} = {};
    $self->{streamContentLength} = {};
    $self->{streamBytesSent} = {};

    return;
}

sub writeToBackends($self, $blocksize, $loopcount, $finishcountdown) {
    # Write from per-stream buffers to backends with proper partial write handling
    foreach my $streamId (keys %{$self->{tobackendbuffers}}) {
        my $backend = $self->{streamBackends}->{$streamId};
        next if(!defined($backend));
        next if($self->{backenddisconnects}->{$streamId});

        my $tobackendbuffer = \$self->{tobackendbuffers}->{$streamId};
        next if(!defined($$tobackendbuffer) || !length($$tobackendbuffer));

        my $sendcount = $loopcount;
        my $backend_offset = 0;

        while($sendcount) {
            my $remaining = length($$tobackendbuffer) - $backend_offset;
            if($remaining > 0) {
                my $written;
                my $towrite = $remaining < $blocksize ? $remaining : $blocksize;

                eval {
                    $written = syswrite($backend, $$tobackendbuffer, $towrite, $backend_offset);
                };
                if($EVAL_ERROR) {
                    print STDERR "HTTP2Handler: Write error to backend (stream $streamId): $EVAL_ERROR\n";
                    $self->{backenddisconnects}->{$streamId} = 1;
                    last;
                }
                if(defined($written) && $written) {
                    $backend_offset += $written;
                } else {
                    last;
                }
            } else {
                last;
            }
            $sendcount--;
        }
        # Remove written data from buffer
        if($backend_offset > 0) {
            $$tobackendbuffer = substr($$tobackendbuffer, $backend_offset);
        }
    }

    return;
}

1;
__END__

=head1 NAME

PageCamel::CMDLine::WebFrontend::HTTP2Handler - HTTP/2 to HTTP/1.1 translation handler

=head1 SYNOPSIS

    use PageCamel::CMDLine::WebFrontend::HTTP2Handler;

    my $handler = PageCamel::CMDLine::WebFrontend::HTTP2Handler->new(
        clientSocket      => $sslSocket,
        backendSocketPath => '/var/run/pagecamel.sock',
        pagecamelInfo     => {
            lhost    => '192.168.1.1',
            lport    => 443,
            peerhost => '10.0.0.1',
            peerport => 54321,
            usessl   => 1,
            pid      => $$,
        },
    );

    $handler->run();

=head1 DESCRIPTION

This module handles HTTP/2 connections for PageCamel WebFrontend. It translates
HTTP/2 requests into HTTP/1.1 requests for the backend, and translates HTTP/1.1
responses back to HTTP/2 for the client.

Each HTTP/2 stream gets a separate backend Unix socket connection for simplicity.

=head2 WebSocket over HTTP/2

Supports RFC 8441 extended CONNECT method for WebSocket bootstrapping. When a
client sends an extended CONNECT with C<:protocol: websocket>, this handler
translates it to an HTTP/1.1 WebSocket upgrade request and establishes a
bidirectional tunnel.

=head1 METHODS

=over 4

=item new(%config)

Creates a new HTTP2Handler instance. Required parameters:

=over 8

=item clientSocket

The SSL-wrapped client socket (IO::Socket::SSL).

=item backendSocketPath

Path to the backend Unix socket.

=item pagecamelInfo

Hash with connection metadata: lhost, lport, peerhost, peerport, usessl, pid.

=back

=item run()

Main event loop. Runs until the client disconnects.

=back

=head1 SEE ALSO

L<Protocol::HTTP2::Server>, L<PageCamel::CMDLine::WebFrontend>

=cut
