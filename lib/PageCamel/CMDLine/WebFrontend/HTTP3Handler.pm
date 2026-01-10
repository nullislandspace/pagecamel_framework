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

    # Stream to backend connection mapping
    $self->{streamBackends} = {};
    # Reverse lookup: backend socket → stream ID (for O(1) lookup)
    $self->{backendToStream} = {};
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

    # Backend connection pool (Keep-Alive reuse)
    $self->{backendPool} = [];           # Available connections ready for reuse
    $self->{maxPoolSize} = 8;            # Max connections to keep in pool
    $self->{waitingForBackend} = [];     # Queue of [streamId, request, isWebSocket] waiting for backend

    return $self;
}

sub run($self) {
    my $quicConn = $self->{quicConnection};

    # Create HTTP/3 server instance over the QUIC connection
    my $http3Server;
    $http3Server = PageCamel::Protocol::HTTP3::Server->new(
        quic_connection => $quicConn,
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
            print STDERR getISODate() . " HTTP3Handler: Buffer drain timeout, closing\n";
            $done = 1;
        }
    }

    # Cleanup
    $self->cleanup();

    return;
}

sub handleRequest($self, $server, $streamId, $headers, $data) {
    $self->{streamsHandled}++;
    print STDERR getISODate() . " HTTP3Handler::handleRequest: streamId=$streamId\n";

    # Convert HTTP/3 headers to HTTP/1.1 request (without PAGECAMEL overhead)
    my $request = $self->translateRequest($streamId, $headers, $data);
    print STDERR getISODate() . " HTTP3Handler::handleRequest: request translated, " . length($request) . " bytes\n";

    # Try to acquire backend from pool
    my $backend = $self->acquireBackend($streamId);
    print STDERR getISODate() . " HTTP3Handler::handleRequest: acquireBackend returned " . (defined($backend) ? "socket" : "undef") . "\n";
    if(!defined($backend)) {
        # Check if we're at capacity (queue) or backend unavailable (error)
        my $activeBackends = scalar(keys %{$self->{streamBackends}});
        if($activeBackends >= $self->{maxPoolSize}) {
            # At capacity, queue the request for later
            push @{$self->{waitingForBackend}}, [$streamId, $request, 0];
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
            # At capacity, queue the request for later (WebSocket flag = 1)
            push @{$self->{waitingForBackend}}, [$streamId, $request, 1];
            return;
        }

        # Backend truly unavailable - send 590
        $server->response($streamId, 590, ['content-type', 'text/html'], '');
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
    # Handle incoming data on a stream (for tunnels/WebSocket)
    my $state = $self->{streamStates}->{$streamId} // '';

    if($state eq 'tunnel_active') {
        # Forward data to backend
        my $backend = $self->{streamBackends}->{$streamId};
        if(defined($backend)) {
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

    for(my $i = 0; $i < scalar(@{$headers}); $i += 2) {
        my $name = $headers->[$i];
        my $value = $headers->[$i + 1];

        if($name =~ /^:/) {
            $h{$name} = $value;
        } else {
            push @otherHeaders, "$name: $value";
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

    # Add other headers
    foreach my $hdr (@otherHeaders) {
        $request .= "$hdr\r\n";
    }

    # Add Content-Length if body present
    if(defined($body) && length($body)) {
        $request .= "Content-Length: " . length($body) . "\r\n";
    }

    $request .= "\r\n";

    # Add body
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

sub connectBackend($self, $streamId) {
    my $socketPath = $self->{backendSocketPath};

    my $startTime = time();

    my $backend = IO::Socket::UNIX->new(
        Type => SOCK_STREAM,
        Peer => $socketPath,
    );

    if(!defined($backend)) {
        print STDERR getISODate() . " HTTP3Handler: Cannot connect to backend: $ERRNO\n";
        return;
    }

    my $elapsed = time() - $startTime;
    if($elapsed > 0.001) {  # Log if > 1ms
        print STDERR getISODate() . " HTTP3Handler: connectBackend took ${elapsed}s for stream $streamId\n";
    }

    $backend->blocking(0);
    $self->{streamBackends}->{$streamId} = $backend;
    $self->{backendToStream}->{$backend} = $streamId;  # Reverse mapping for O(1) lookup

    return $backend;
}

# Backend connection pooling methods

sub createPooledBackend($self) {
    # Create a new backend connection and send PAGECAMEL overhead immediately
    my $socketPath = $self->{backendSocketPath};

    my $startTime = time();

    my $backend = IO::Socket::UNIX->new(
        Type => SOCK_STREAM,
        Peer => $socketPath,
    );

    if(!defined($backend)) {
        print STDERR getISODate() . " HTTP3Handler: createPooledBackend failed: $ERRNO\n";
        return;
    }

    # Send PAGECAMEL overhead immediately (once per connection, not per request)
    my $info = $self->{pagecamelInfo};
    my $overhead = "PAGECAMEL $info->{lhost} $info->{lport} $info->{peerhost} $info->{peerport} 1 $PID HTTP/3\r\n";

    my $written = syswrite($backend, $overhead);
    if(!defined($written) || $written != length($overhead)) {
        print STDERR getISODate() . " HTTP3Handler: Failed to send overhead: $ERRNO\n";
        close($backend);
        return;
    }

    my $elapsed = time() - $startTime;
    if($elapsed > 0.001) {  # Log if > 1ms
        print STDERR getISODate() . " HTTP3Handler: createPooledBackend took ${elapsed}s\n";
    }

    $backend->blocking(0);
    return $backend;
}

sub isBackendAlive($self, $backend) {
    # Check if connection is still open using select() + MSG_PEEK
    return 0 if(!defined($backend));

    my $select = IO::Select->new($backend);
    my @ready = $select->can_read(0);

    if(@ready) {
        # Socket has data or is closed - check with MSG_PEEK
        my $buf;
        my $rc = recv($backend, $buf, 1, MSG_PEEK);

        if(!defined($rc)) {
            return 0;  # Error - connection dead
        }
        if(length($buf) == 0) {
            return 0;  # Connection closed (EOF)
        }
        # Unexpected data on backend (shouldn't happen in normal flow)
        return 0;
    }

    return 1;  # No data waiting, connection healthy
}

sub acquireBackend($self, $streamId) {
    print STDERR getISODate() . " HTTP3Handler::acquireBackend: streamId=$streamId, pool=" . scalar(@{$self->{backendPool}}) . " active=" . scalar(keys %{$self->{streamBackends}}) . "\n";

    # Try to get a connection from the pool
    while(scalar(@{$self->{backendPool}}) > 0) {
        my $backend = pop @{$self->{backendPool}};

        if($self->isBackendAlive($backend)) {
            $self->{streamBackends}->{$streamId} = $backend;
            $self->{backendToStream}->{$backend} = $streamId;
            print STDERR getISODate() . " HTTP3Handler::acquireBackend: reusing pooled connection\n";
            return $backend;
        } else {
            # Connection dead, close it
            eval { close($backend); };
        }
    }

    # Check if we're at capacity
    my $activeBackends = scalar(keys %{$self->{streamBackends}});
    if($activeBackends >= $self->{maxPoolSize}) {
        print STDERR getISODate() . " HTTP3Handler::acquireBackend: at capacity ($activeBackends >= $self->{maxPoolSize})\n";
        return;  # At capacity, caller should queue the request
    }

    # Create new connection
    print STDERR getISODate() . " HTTP3Handler::acquireBackend: creating new backend to $self->{backendSocketPath}\n";
    my $backend = $self->createPooledBackend();
    if(!defined($backend)) {
        print STDERR getISODate() . " HTTP3Handler::acquireBackend: createPooledBackend failed!\n";
        return;
    }

    $self->{streamBackends}->{$streamId} = $backend;
    $self->{backendToStream}->{$backend} = $streamId;
    print STDERR getISODate() . " HTTP3Handler::acquireBackend: created new connection, now active=" . scalar(keys %{$self->{streamBackends}}) . "\n";

    return $backend;
}

sub releaseBackend($self, $streamId, $reusable = 1) {
    my $backend = $self->{streamBackends}->{$streamId};
    return if(!defined($backend));

    # Remove from stream mappings
    delete $self->{streamBackends}->{$streamId};
    delete $self->{backendToStream}->{$backend};

    # Return to pool if reusable and healthy
    if($reusable && $self->isBackendAlive($backend) &&
       scalar(@{$self->{backendPool}}) < $self->{maxPoolSize}) {
        push @{$self->{backendPool}}, $backend;
    } else {
        eval { close($backend); };
    }
}

sub processWaitingStreams($self, $server) {
    return if(scalar(@{$self->{waitingForBackend}}) == 0);

    my @stillWaiting;
    while(my $waiting = shift @{$self->{waitingForBackend}}) {
        my ($streamId, $request, $isWebSocket) = @{$waiting};

        my $backend = $self->acquireBackend($streamId);
        if(!defined($backend)) {
            # Still at capacity, re-queue this and stop processing
            push @stillWaiting, $waiting;
            last;
        }

        # Got a backend, send the request
        $self->{tobackendbuffers}->{$streamId} = $request;
        $self->{streamStates}->{$streamId} = $isWebSocket ? 'tunnel_pending' : 'waiting_response';
        $self->{streamResponses}->{$streamId} = '';
    }

    # Re-add any still-waiting streams
    unshift @{$self->{waitingForBackend}}, @stillWaiting;
}

sub handleBackendData($self, $server, $socket, $toclientbufferRef, $maxBufferSize) {
    # Find which stream this backend belongs to (O(1) reverse lookup)
    if(!defined($self->{backendToStream}->{$socket})) {
        return;
    }
    my $streamId = $self->{backendToStream}->{$socket};

    # Skip if buffer is too large (back-pressure)
    return if(length(${$toclientbufferRef}) >= $maxBufferSize);

    my $buf;
    my $bytesRead = $socket->sysread($buf, 16_384);

    if(!defined($bytesRead) || $bytesRead == 0) {
        # Backend disconnected
        $self->{backenddisconnects}->{$streamId} = 1;
        $self->processBackendResponse($server, $streamId);
        return;
    }

    # Track total bytes read from backend
    $self->{backendBytesRead}->{$streamId} //= 0;
    $self->{backendBytesRead}->{$streamId} += $bytesRead;

    # Check for 15736 boundary
    my $prevTotal = $self->{backendBytesRead}->{$streamId} - $bytesRead;
    my $newTotal = $self->{backendBytesRead}->{$streamId};
    if($prevTotal <= 15736 && $newTotal > 15736) {
        my $offset = 15736 - $prevTotal;
        print STDERR "HTTP3Handler: *** BACKEND BOUNDARY 15736 *** stream=$streamId prev=$prevTotal read=$bytesRead offset_in_buf=$offset\n";
        if($offset >= 3 && $offset + 3 <= length($buf)) {
            my @bytes = map { sprintf("%02x", ord($_)) } split(//, substr($buf, $offset - 3, 6));
            print STDERR "HTTP3Handler: backend bytes around 15736: [@bytes[0..2] | @bytes[3..5]]\n";
        }
    }

    # Append to response buffer
    $self->{streamResponses}->{$streamId} .= $buf;

    # Try to process response
    $self->processBackendResponse($server, $streamId);

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
                # Check for 15736 boundary in first body chunk
                my $prevSent = $self->{streamBytesSent}->{$streamId};
                my $newSent = $prevSent + length($body);
                if($prevSent <= 15736 && $newSent > 15736) {
                    my $offset = 15736 - $prevSent;
                    print STDERR "HTTP3Handler: *** SEND BOUNDARY 15736 *** stream=$streamId prevSent=$prevSent bodyLen=" . length($body) . " offset=$offset\n";
                    if($offset >= 3 && $offset + 3 <= length($body)) {
                        my @bytes = map { sprintf("%02x", ord($_)) } split(//, substr($body, $offset - 3, 6));
                        print STDERR "HTTP3Handler: send bytes around 15736: [@bytes[0..2] | @bytes[3..5]]\n";
                    }
                }

                my $bytesWritten = $stream->send($body);
                if(defined($bytesWritten) && $bytesWritten > 0) {
                    $self->{streamBytesSent}->{$streamId} += $bytesWritten;
                    if($bytesWritten < length($body)) {
                        # Partial write - keep unsent portion in buffer
                        $self->{streamResponses}->{$streamId} = substr($body, $bytesWritten);
                    } else {
                        $self->{streamResponses}->{$streamId} = '';
                    }
                } else {
                    # Flow control blocked - keep entire body in buffer
                    $self->{streamResponses}->{$streamId} = $body;
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
            # Check for 15736 boundary in streaming chunk
            my $prevSent = $self->{streamBytesSent}->{$streamId} // 0;
            my $newSent = $prevSent + length($response);
            if($prevSent <= 15736 && $newSent > 15736) {
                my $offset = 15736 - $prevSent;
                print STDERR "HTTP3Handler: *** STREAM BOUNDARY 15736 *** stream=$streamId prevSent=$prevSent respLen=" . length($response) . " offset=$offset\n";
                if($offset >= 3 && $offset + 3 <= length($response)) {
                    my @bytes = map { sprintf("%02x", ord($_)) } split(//, substr($response, $offset - 3, 6));
                    print STDERR "HTTP3Handler: stream bytes around 15736: [@bytes[0..2] | @bytes[3..5]]\n";
                }
            }

            my $bytesWritten = $stream->send($response);

            if(defined($bytesWritten) && $bytesWritten > 0) {
                # Successfully sent some bytes
                $self->{streamBytesSent}->{$streamId} += $bytesWritten;

                if($bytesWritten >= length($response)) {
                    # All data sent - clear buffer
                    $self->{streamResponses}->{$streamId} = '';
                } else {
                    # Partial write (flow control) - keep unsent portion
                    $self->{streamResponses}->{$streamId} = substr($response, $bytesWritten);
                }
            }
            # If bytesWritten is 0 or negative (flow control blocked), keep buffer as-is
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

            # Skip if already congestion-blocked, unless ACKs have opened the cwnd
            if($self->{streamCongestionBlocked}->{$streamId}) {
                # Check if cwnd has space now (ACKs may have opened it)
                my $cwndLeft = $self->{quicConnection}->{quic_conn}->get_cwnd_left();
                if($cwndLeft < 1200) {
                    # Still blocked, skip this stream
                    next;
                }
                # cwnd has space, clear the flag and try again
                delete $self->{streamCongestionBlocked}->{$streamId};
            }

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

                    # Send packets every few writes to keep congestion window open
                    if($sendPacketsCallback && $writeCount % 5 == 0) {
                        $sendPacketsCallback->();
                    }
                } else {
                    # Congestion blocked (or error) - send any pending packets and exit
                    # Don't retry immediately - we need to wait for ACKs from the network
                    # The main loop will process ACKs and call flushPendingStreams again
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

    # Return true if we made progress but are still blocked (caller should loop)
    # Return false if nothing to do or all data sent
    my $hasBlockedStreams = scalar(keys %{$self->{streamCongestionBlocked}}) > 0;
    my $hasPendingData = 0;
    foreach my $streamId (keys %{$self->{streamResponses}}) {
        if(length($self->{streamResponses}->{$streamId} // '') > 0) {
            $hasPendingData = 1;
            last;
        }
    }

    # Also check for pending flush streams (nghttp3 buffer not yet drained)
    my $hasPendingFlush = scalar(keys %{$self->{streamPendingFlush}}) > 0;

    return ($hasPendingData || $hasPendingFlush) && !$hasBlockedStreams;  # true = call again
}

sub cleanupStream($self, $streamId) {
    my $bytesSent = $self->{streamBytesSent}->{$streamId} // 0;
    my $contentLength = $self->{streamContentLength}->{$streamId} // 'unknown';
    my $bufLen = length($self->{streamResponses}->{$streamId} // '');
    print STDERR "HTTP3Handler::cleanupStream($streamId) bytesSent=$bytesSent contentLength=$contentLength bufferLeft=$bufLen\n";

    # Debug: print call stack
    my $i = 0;
    while(my @caller = caller($i++)) {
        print STDERR "  caller[$i]: $caller[0] line $caller[2] sub $caller[3]\n";
        last if $i > 5;
    }

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
