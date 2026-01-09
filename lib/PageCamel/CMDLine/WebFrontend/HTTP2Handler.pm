package PageCamel::CMDLine::WebFrontend::HTTP2Handler;
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

use PageCamel::Protocol::HTTP2::Server;
use PageCamel::Protocol::HTTP2::Constants qw(:frame_types :flags :states :settings :limits);
use IO::Socket::UNIX;
use IO::Select;
use Socket qw(MSG_PEEK MSG_DONTWAIT);
use Time::HiRes qw(time);
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
    # Reverse lookup: backend socket → stream ID (for O(1) lookup)
    $self->{backendToStream} = {};
    # Stream to response buffer mapping
    $self->{streamResponses} = {};
    # Stream states
    $self->{streamStates} = {};
    # Stream objects for streaming responses (PageCamel::Protocol::HTTP2::Server::Stream)
    $self->{streamStreams} = {};
    # Tunnel objects for WebSocket (PageCamel::Protocol::HTTP2::Server::Tunnel)
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

    # Backend connection pool for Keep-Alive reuse
    $self->{backendPool} = [];              # Available backend connections (ready for reuse)
    $self->{maxPoolSize} = 8;               # Max connections to keep in pool
    $self->{waitingForBackend} = [];        # Queue of [streamId, request, state] waiting for backend

    return $self;
}

sub run($self) {
    my $client = $self->{clientSocket};
    my $select = IO::Select->new();
    $select->add($client);

    # Create HTTP/2 server instance with extended CONNECT enabled (RFC 8441)
    # Note: Settings must be passed in constructor because the initial
    # SETTINGS frame is queued during construction
    my $server;
    $server = PageCamel::Protocol::HTTP2::Server->new(
        settings => {
            &SETTINGS_ENABLE_CONNECT_PROTOCOL => 1,
            &SETTINGS_INITIAL_WINDOW_SIZE     => 1_048_576,  # 1MB (default 64KB) - reduces flow control round-trips
            # Note: MAX_FRAME_SIZE not increased - Protocol::HTTP2 must respect client's advertised size
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

    # Debug timing - set to 1 to diagnose performance issues
    #my $debugTiming = 1;
    #my $loopCount = 0;
    #my $totalSelectTime = 0;
    #my $totalReadTime = 0;
    #my $totalClientWriteTime = 0;
    #my $totalBackendWriteTime = 0;
    #my $lastReportTime = time();

    while(!$done) {
        #my $loopStart = time() if($debugTiming);
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

        # Build select sets for reading and writing
        my $readSet = IO::Select->new(@monitorSockets);
        my $writeSet = IO::Select->new();

        # Add client to write set if we have data to send
        if(length($toclientbuffer)) {
            $writeSet->add($client);
        }

        # Add backends to write set if we have data to send to them
        foreach my $streamId (keys %{$self->{tobackendbuffers}}) {
            my $backend = $self->{streamBackends}->{$streamId};
            if(defined($backend) && length($self->{tobackendbuffers}->{$streamId} // '')) {
                $writeSet->add($backend);
            }
        }

        # Use select() - block until I/O is ready
        # Use short timeout (0.001s) if we have data to send, longer (1s) otherwise
        # This ensures we stay responsive when actively transferring data
        my $timeout = $writeSet->count() > 0 ? 0.001 : 1;
        $ERRNO = 0;
        #my $selectStart = time() if($debugTiming);
        my ($canRead, $canWrite, undef) = IO::Select->select($readSet, $writeSet, undef, $timeout);
        #$totalSelectTime += (time() - $selectStart) if($debugTiming);

        # Handle EINTR (signal interrupted call) - just continue
        if(!defined($canRead) && $ERRNO{EINTR}) {
            next;
        }

        # Default to empty arrays if select returned undef
        $canRead //= [];
        $canWrite //= [];

        # Timeout with no I/O - send PING if we have active streams
        my $activeStreamsForPing = scalar(keys %{$self->{streamBackends}}) +
                                   scalar(keys %{$self->{streamStreams}}) +
                                   scalar(keys %{$self->{streamTunnels}});
        if(!@{$canRead} && !@{$canWrite} && $activeStreamsForPing > 0) {
            $server->ping();
            while(my $chunk = $server->next_frame()) {
                $toclientbuffer .= $chunk;
            }
        }

        # Handle readable sockets
        #my $readStart = time() if($debugTiming);
        foreach my $socket (@{$canRead}) {
            if($socket == $client) {
                # Skip reading from client if toclientbuffer is too large (back-pressure)
                next if(length($toclientbuffer) >= $max_buffer_size);

                # Data from HTTP/2 client
                my $buf;
                my $bytesRead = $client->sysread($buf, 16_384);

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

        #$totalReadTime += (time() - $readStart) if($debugTiming);

        # Build hash of writable sockets for quick lookup
        my %canWriteHash = map { $_ => 1 } @{$canWrite};

        # Fair I/O: limit writes per iteration to allow interleaving client/backend I/O
        # Higher limit = more throughput but less responsiveness to new requests
        my $maxBytesPerDirection = 10_000_000;  # 10MB per direction per iteration

        # Write to client from buffer with proper partial write handling
        #my $clientWriteStart = time() if($debugTiming);
        my $clientBytesWritten = 0;
        while($clientBytesWritten < $maxBytesPerDirection && length($toclientbuffer) && !$clientdisconnect) {
            my $towrite = length($toclientbuffer) < $blocksize ? length($toclientbuffer) : $blocksize;
            my $written;

            eval {
                $written = syswrite($client, $toclientbuffer, $towrite);
            };
            if($EVAL_ERROR) {
                #print STDERR "HTTP2Handler: Write error to client: $EVAL_ERROR\n";
                last;
            }

            if(defined($written) && $written > 0) {
                $toclientbuffer = substr($toclientbuffer, $written);
                $clientBytesWritten += $written;
                if($finishcountdown) {
                    # Reset countdown if we're still sending data
                    $finishcountdown = time + 20;
                }
            } else {
                last;
            }
        }

        #$totalClientWriteTime += (time() - $clientWriteStart) if($debugTiming);

        # Write to backends from per-stream buffers (fair round-robin)
        #my $backendWriteStart = time() if($debugTiming);
        $self->writeToBackends($blocksize, $maxBytesPerDirection, \%canWriteHash);
        #$totalBackendWriteTime += (time() - $backendWriteStart) if($debugTiming);

        # Process waiting streams - assign backends from pool to queued requests
        $self->processWaitingStreams($server, \$toclientbuffer);

        # Debug timing report (every 2 seconds) - uncomment to diagnose performance
        #if($debugTiming) {
        #    $loopCount++;
        #    my $now = time();
        #    if($now - $lastReportTime >= 2) {
        #        my $elapsed = $now - $lastReportTime;
        #        my $activeBackends = scalar(keys %{$self->{streamBackends}});
        #        my $bufLen = length($toclientbuffer);
        #        print STDERR sprintf("%s HTTP2 PERF: loops=%d select=%.3fs read=%.3fs clientWrite=%.3fs backendWrite=%.3fs backends=%d bufLen=%d\n",
        #            getISODate(), $loopCount, $totalSelectTime, $totalReadTime,
        #            $totalClientWriteTime, $totalBackendWriteTime, $activeBackends, $bufLen);
        #        $loopCount = 0;
        #        $totalSelectTime = 0;
        #        $totalReadTime = 0;
        #        $totalClientWriteTime = 0;
        #        $totalBackendWriteTime = 0;
        #        $lastReportTime = $now;
        #    }
        #}

        # Handle client disconnect
        if($clientdisconnect) {
            $done = 1;
        }

        # HTTP/2 connections should stay open for more requests (unlike HTTP/1.1)
        # Only use finish countdown if we're actively sending data and need to drain buffer
        # The connection stays open until client disconnects or idle timeout

        # Check if all streams are complete (no active backends/streams/tunnels)
        my $activeStreams = scalar(keys %{$self->{streamBackends}}) +
                            scalar(keys %{$self->{streamStreams}}) +
                            scalar(keys %{$self->{streamTunnels}});

        # If we have data to send but no active streams, start countdown to drain buffer
        if($finishcountdown && !length($toclientbuffer)) {
            # Buffer drained, reset countdown
            $finishcountdown = 0;
        } elsif(!$finishcountdown && length($toclientbuffer) && $activeStreams == 0) {
            # Data to send but no streams - give time to drain
            $finishcountdown = time + 20;
        }

        # Handle finish countdown (only for buffer draining, not connection close)
        if($finishcountdown > 0 && $finishcountdown <= time) {
            # Timeout waiting to drain buffer - something is wrong
            print STDERR getISODate() . " HTTP2Handler: Buffer drain timeout, closing\n";
            $done = 1;
        }
    }

    # Debug: log exit reason
    #print STDERR getISODate() . " HTTP2Handler [$self->{pagecamelInfo}->{peerhost}]: Exiting main loop (streamsHandled=$self->{streamsHandled}, clientdisconnect=$clientdisconnect, bufferLen=" . length($toclientbuffer) . ")\n";

    # Cleanup all backend connections
    $self->cleanup();

    return;
}

sub handleRequest($self, $server, $streamId, $headers, $data) {
    # Track that we've handled a request
    $self->{streamsHandled}++;

    # Debug: log incoming request
    my %h;
    for(my $i = 0; $i < scalar(@{$headers}); $i += 2) {
        $h{$headers->[$i]} = $headers->[$i + 1];
    }
    #print STDERR getISODate() . " HTTP2 REQ: stream=$streamId activeBackends=" . scalar(keys %{$self->{streamBackends}}) . " poolSize=" . scalar(@{$self->{backendPool}}) . " path=$h{':path'}\n";
    $self->{streamStartTime}->{$streamId} = time();

    # Convert HTTP/2 headers to HTTP/1.1 request
    my $request = $self->translateRequest($streamId, $headers, $data);

    # Try to acquire backend from pool
    my $backend = $self->acquireBackend($streamId);
    if(!defined($backend)) {
        # Check if we're at max capacity (queue) vs backend unavailable (error)
        my $activeBackends = scalar(keys %{$self->{streamBackends}});
        if($activeBackends >= $self->{maxPoolSize}) {
            # At max capacity - queue the stream for later
            #print STDERR getISODate() . " HTTP2 QUEUE: stream=$streamId (active=$activeBackends, waiting=" . scalar(@{$self->{waitingForBackend}}) . ")\n";
            push @{$self->{waitingForBackend}}, [$streamId, $request, 'waiting_response'];
            return;
        }

        # Backend genuinely unavailable - send 590 error
        $server->response(
            ':status'  => 590,
            stream_id  => $streamId,
            headers    => ['content-type', 'text/html; charset=UTF-8'],
            data       => $self->{errorPage590Html} // '',
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

    #print STDERR getISODate() . " HTTP2 WS REQ: stream=$streamId activeBackends=" . scalar(keys %{$self->{streamBackends}}) . " poolSize=" . scalar(@{$self->{backendPool}}) . " path=$h{':path'}\n";
    $self->{streamStartTime}->{$streamId} = time();

    # Translate to HTTP/1.1 WebSocket upgrade
    my $request = $self->translateWebsocketUpgrade($streamId, $headers);

    # Try to acquire backend from pool
    my $backend = $self->acquireBackend($streamId);
    if(!defined($backend)) {
        # Check if we're at max capacity (queue) vs backend unavailable (error)
        my $activeBackends = scalar(keys %{$self->{streamBackends}});
        if($activeBackends >= $self->{maxPoolSize}) {
            # At max capacity - queue the stream for later
            #print STDERR getISODate() . " HTTP2 WS QUEUE: stream=$streamId (active=$activeBackends, waiting=" . scalar(@{$self->{waitingForBackend}}) . ")\n";
            push @{$self->{waitingForBackend}}, [$streamId, $request, 'tunnel_pending'];
            return;
        }

        # Backend genuinely unavailable - send 590 error
        $server->response(
            ':status'  => 590,
            stream_id  => $streamId,
            headers    => ['content-type', 'text/html; charset=UTF-8'],
            data       => $self->{errorPage590Html} // '',
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
    # Translate HTTP/2 request to HTTP/1.1
    # Note: PAGECAMEL overhead is sent once per backend connection in createPooledBackend()
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

    # Build HTTP/1.1 request (no PAGECAMEL overhead - sent on connection creation)
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

    # Add body if present
    if(defined($data) && length($data)) {
        $request .= $data;
    }

    return $request;
}

sub translateWebsocketUpgrade($self, $streamId, $headers) {
    # Translate HTTP/2 extended CONNECT to HTTP/1.1 WebSocket upgrade
    # Note: PAGECAMEL overhead is sent once per backend connection in createPooledBackend()
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

    # Generate Sec-WebSocket-Key
    my $key = $self->generateWebsocketKey();

    # Build HTTP/1.1 WebSocket upgrade request (no PAGECAMEL overhead - sent on connection creation)
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

sub createPooledBackend($self) {
    # Create new backend connection and send PAGECAMEL overhead immediately
    my $startTime = time();

    my $backend = IO::Socket::UNIX->new(
        Peer    => $self->{backendSocketPath},
        Timeout => 15,
    );

    if(!defined($backend)) {
        carp("HTTP2Handler: Failed to connect to backend: $ERRNO");
        return;
    }

    # Send PAGECAMEL overhead header immediately (required within 15 seconds)
    my $info = $self->{pagecamelInfo};
    my $overhead = "PAGECAMEL $info->{lhost} $info->{lport} $info->{peerhost} $info->{peerport} $info->{usessl} $info->{pid} HTTP/2\r\n";

    my $written = syswrite($backend, $overhead);
    if(!defined($written) || $written != length($overhead)) {
        carp("HTTP2Handler: Failed to send overhead to backend: $ERRNO");
        close($backend);
        return;
    }

    my $elapsed = time() - $startTime;
    if($elapsed > 0.001) {  # Log if > 1ms
        print STDERR getISODate() . " HTTP2Handler: createPooledBackend took ${elapsed}s\n";
    }

    return $backend;
}

sub isBackendAlive($self, $backend) {
    # Check if backend connection is still open
    # Use select() with 0 timeout to check for readability without blocking
    # If readable with no data or error, connection is closed
    return 0 if(!defined($backend));

    my $select = IO::Select->new($backend);
    my @ready = $select->can_read(0);

    if(@ready) {
        # Socket is readable - check if there's actually data or if it's EOF
        my $buf;
        my $rc = recv($backend, $buf, 1, MSG_PEEK | MSG_DONTWAIT);
        if(!defined($rc) || length($buf) == 0) {
            # Connection closed or error
            return 0;
        }
        # Has unexpected data - backend sent something we didn't request
        # This shouldn't happen, but treat as unhealthy
        return 0;
    }

    # Not readable = no pending data and not closed = healthy
    return 1;
}

sub acquireBackend($self, $streamId) {
    # Try to get a healthy connection from pool, or create new one

    # First, try to get from pool
    while(scalar(@{$self->{backendPool}}) > 0) {
        my $backend = pop @{$self->{backendPool}};

        if($self->isBackendAlive($backend)) {
            # Connection is healthy, assign to stream
            $self->{streamBackends}->{$streamId} = $backend;
            $self->{backendToStream}->{$backend} = $streamId;
            #print STDERR getISODate() . " HTTP2Handler: acquireBackend stream=$streamId (reused from pool, poolSize=" . scalar(@{$self->{backendPool}}) . ")\n";
            return $backend;
        } else {
            # Connection is dead, close and try next
            #print STDERR getISODate() . " HTTP2Handler: discarding stale pooled connection\n";
            eval { close($backend); };
        }
    }

    # Pool empty, check if we can create a new connection
    my $activeBackends = scalar(keys %{$self->{streamBackends}});
    if($activeBackends >= $self->{maxPoolSize}) {
        # At max capacity, caller should queue the stream
        #print STDERR getISODate() . " HTTP2Handler: acquireBackend stream=$streamId - at max capacity ($activeBackends), queuing\n";
        return;
    }

    # Create new connection
    my $backend = $self->createPooledBackend();
    if(!defined($backend)) {
        return;
    }

    $self->{streamBackends}->{$streamId} = $backend;
    $self->{backendToStream}->{$backend} = $streamId;
    #print STDERR getISODate() . " HTTP2Handler: acquireBackend stream=$streamId (new connection, active=$activeBackends)\n";

    return $backend;
}

sub releaseBackend($self, $streamId, $reusable = 1) {
    # Release backend connection - return to pool if healthy and reusable, else close
    my $backend = $self->{streamBackends}->{$streamId};
    return if(!defined($backend));

    # Clean up mappings
    delete $self->{streamBackends}->{$streamId};
    delete $self->{backendToStream}->{$backend};

    # Check if we should return to pool
    if($reusable && $self->isBackendAlive($backend) && scalar(@{$self->{backendPool}}) < $self->{maxPoolSize}) {
        push @{$self->{backendPool}}, $backend;
        #print STDERR getISODate() . " HTTP2Handler: releaseBackend stream=$streamId (returned to pool, poolSize=" . scalar(@{$self->{backendPool}}) . ")\n";
    } else {
        eval { close($backend); };
        #print STDERR getISODate() . " HTTP2Handler: releaseBackend stream=$streamId (closed, reusable=$reusable)\n";
    }

    return;
}

sub processWaitingStreams($self, $server, $toclientbufferRef) {
    # Process streams waiting for a backend connection
    return if(scalar(@{$self->{waitingForBackend}}) == 0);

    my @stillWaiting;
    while(my $waiting = shift @{$self->{waitingForBackend}}) {
        my ($streamId, $request, $state) = @{$waiting};

        my $backend = $self->acquireBackend($streamId);
        if(!defined($backend)) {
            # Still no backend available, keep waiting
            push @stillWaiting, $waiting;
            last;  # Don't try more if we're at capacity
        }

        # Got a backend, buffer the request
        $self->{tobackendbuffers}->{$streamId} = $request;
        $self->{streamStates}->{$streamId} = $state;
        $self->{streamResponses}->{$streamId} = '';
        #print STDERR getISODate() . " HTTP2Handler: processWaitingStreams - assigned backend to stream=$streamId\n";
    }

    # Put remaining waiting streams back
    unshift @{$self->{waitingForBackend}}, @stillWaiting;

    return;
}

# Legacy method for compatibility - now uses pool
sub connectBackend($self, $streamId) {
    return $self->acquireBackend($streamId);
}

sub handleBackendData($self, $server, $backend, $toclientbufferRef, $max_buffer_size) {
    # Find which stream this backend belongs to (O(1) reverse lookup)
    if(!defined($self->{backendToStream}->{$backend})) {
        return;
    }
    my $streamId = $self->{backendToStream}->{$backend};

    # Back-pressure: skip reading if client buffer is too large
    if(length(${$toclientbufferRef}) >= $max_buffer_size) {
        return;
    }

    my $buf;
    my $bytesRead = $backend->sysread($buf, 65_536);

    if(!defined($bytesRead) || $bytesRead == 0) {
        # Backend closed connection
        #print STDERR getISODate() . " HTTP2Handler [$self->{pagecamelInfo}->{peerhost}]: Backend closed for stream=$streamId (bytesRead=" . ($bytesRead // 'undef') . ")\n";
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
                ${$toclientbufferRef} .= $chunk;
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
        #print STDERR getISODate() . " HTTP2Handler [$self->{pagecamelInfo}->{peerhost}]: Streaming data for stream=$streamId, bytes=" . length($buf) . "\n";
        my $stream = $self->{streamStreams}->{$streamId};
        if(defined($stream)) {
            $stream->send($buf);
            $self->{streamBytesSent}->{$streamId} += length($buf);
            while(my $chunk = $server->next_frame()) {
                ${$toclientbufferRef} .= $chunk;
            }

            # Check if we've sent all content-length bytes - if so, send END_STREAM now
            my $contentLength = $self->{streamContentLength}->{$streamId};
            my $bytesSent = $self->{streamBytesSent}->{$streamId};
            if(defined($contentLength) && $bytesSent >= $contentLength) {
                #print STDERR getISODate() . " HTTP2Handler [$self->{pagecamelInfo}->{peerhost}]: Content-length reached for stream=$streamId ($bytesSent >= $contentLength), sending END_STREAM\n";
                $self->cleanupStream($server, $streamId, $toclientbufferRef);
            }
        }
    }

    return;
}

sub processBackendResponse($self, $server, $streamId, $toclientbufferRef) {
    my $response = $self->{streamResponses}->{$streamId};
    my $state = $self->{streamStates}->{$streamId};
    #print STDERR getISODate() . " HTTP2Handler: processBackendResponse stream=$streamId state=$state responseLen=" . length($response) . "\n";

    # Split headers from body
    my ($headerPart, $bodyPart) = split(/\r\n\r\n/, $response, 2);

    # Parse status line and headers
    my @lines = split(/\r\n/, $headerPart);
    my $statusLine = shift @lines;

    my ($proto, $status, $reason) = split(/\s+/, $statusLine, 3);

    # Ensure status is defined (default to 500 if malformed response)
    $status //= 500;

    # Build flat array of headers for PageCamel::Protocol::HTTP2: [name, value, name, value, ...]
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
    #print STDERR getISODate() . " HTTP2Handler [$self->{pagecamelInfo}->{peerhost}]: processBackendResponse stream=$streamId status=$status contentLength=" . ($contentLength // 'undef') . " bodyLen=" . length($bodyPart // '') . " state=$state\n";

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
            # Set up on_data callback to forward client data to backend
            my $tunnel = $server->tunnel_response(
                ':status'  => 200,
                stream_id  => $streamId,
                headers    => \@tunnelHeaders,
                on_data    => sub {
                    my ($data) = @_;
                    # Forward incoming tunnel data to backend
                    #print STDERR getISODate() . " HTTP2Handler: Tunnel on_data stream=$streamId bytes=" . length($data) . "\n";
                    if(defined($self->{streamBackends}->{$streamId})) {
                        $self->{tobackendbuffers}->{$streamId} //= '';
                        $self->{tobackendbuffers}->{$streamId} .= $data;
                    } else {
                        #print STDERR getISODate() . " HTTP2Handler: WARNING - no backend for tunnel stream=$streamId\n";
                    }
                },
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
            #print STDERR getISODate() . " HTTP2Handler [$self->{pagecamelInfo}->{peerhost}]: Using response() for complete response (stream=$streamId)\n";
            $server->response(
                ':status'  => $status,
                stream_id  => $streamId,
                headers    => \@responseHeaders,
                data       => $bodyPart,
            );
            $self->cleanupStream($server, $streamId, $toclientbufferRef, 0);  # Don't send END_STREAM, response() does it
        } else {
            # Send headers, switch to streaming mode for body using response_stream()
            #print STDERR getISODate() . " HTTP2Handler [$self->{pagecamelInfo}->{peerhost}]: Using response_stream() for streaming response (stream=$streamId)\n";
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
        ${$toclientbufferRef} .= $chunk;
    }

    # Clear response buffer
    $self->{streamResponses}->{$streamId} = '';

    return;
}

sub cleanupStream($self, $server, $streamId, $toclientbufferRef, $sendEndStream = 1) {
    #my $elapsed = $self->{streamStartTime}->{$streamId} ? sprintf("%.3f", time() - $self->{streamStartTime}->{$streamId}) : "?";
    #print STDERR getISODate() . " HTTP2 DONE: stream=$streamId elapsed=${elapsed}s activeBackends=" . scalar(keys %{$self->{streamBackends}}) . " poolSize=" . scalar(@{$self->{backendPool}}) . "\n";
    delete $self->{streamStartTime}->{$streamId};

    # Determine if backend connection is reusable for Keep-Alive pooling:
    # - WebSocket tunnels are NOT reusable (bidirectional data flow)
    # - Backend disconnects are NOT reusable (connection was closed)
    # - Regular completed requests ARE reusable
    my $isTunnel = defined($self->{streamTunnels}->{$streamId});
    my $backendClosed = $self->{backenddisconnects}->{$streamId} // 0;
    my $reusable = !$isTunnel && !$backendClosed;

    # Release backend connection (returns to pool if reusable, closes otherwise)
    $self->releaseBackend($streamId, $reusable);

    # Send END_STREAM if needed via Stream or Tunnel object
    if($sendEndStream) {
        if(defined($self->{streamStreams}->{$streamId})) {
            $self->{streamStreams}->{$streamId}->close();
        } elsif(defined($self->{streamTunnels}->{$streamId})) {
            $self->{streamTunnels}->{$streamId}->close();
        }
        while(my $chunk = $server->next_frame()) {
            ${$toclientbufferRef} .= $chunk;
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
    # Close all active backend connections
    foreach my $streamId (keys %{$self->{streamBackends}}) {
        if(defined($self->{streamBackends}->{$streamId})) {
            eval {
                close($self->{streamBackends}->{$streamId});
            };
        }
    }

    # Close all pooled backend connections
    foreach my $backend (@{$self->{backendPool}}) {
        eval {
            close($backend);
        };
    }

    $self->{streamBackends} = {};
    $self->{backendToStream} = {};
    $self->{backendPool} = [];
    $self->{waitingForBackend} = [];
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

sub writeToBackends($self, $blocksize, $maxBytesPerIteration, $canWriteHashRef) {
    # Write from per-stream buffers to backends using round-robin fairness
    # Each stream gets ONE block per pass, then we cycle through all streams again
    # This ensures all streams make equal progress instead of one stream hogging writes

    my $totalBytesThisIteration = 0;
    my $madeProgress = 1;  # Track if any writes succeeded

    # Round-robin: one block per stream per pass, repeat until nothing left or limit hit
    while($madeProgress && $totalBytesThisIteration < $maxBytesPerIteration) {
        $madeProgress = 0;

        foreach my $streamId (keys %{$self->{tobackendbuffers}}) {
            my $backend = $self->{streamBackends}->{$streamId};
            next if(!defined($backend));
            next if($self->{backenddisconnects}->{$streamId});
            next if(!$canWriteHashRef->{$backend});  # Skip if not writable

            my $tobackendbuffer = \$self->{tobackendbuffers}->{$streamId};
            next if(!defined(${$tobackendbuffer}) || !length(${$tobackendbuffer}));

            # Write ONE block per stream per pass (fair round-robin)
            my $towrite = length(${$tobackendbuffer}) < $blocksize ? length(${$tobackendbuffer}) : $blocksize;
            my $written;

            eval {
                $written = syswrite($backend, ${$tobackendbuffer}, $towrite);
            };
            if($EVAL_ERROR) {
                #print STDERR "HTTP2Handler: Write error to backend (stream $streamId): $EVAL_ERROR\n";
                $self->{backenddisconnects}->{$streamId} = 1;
                next;
            }

            if(defined($written) && $written > 0) {
                ${$tobackendbuffer} = substr(${$tobackendbuffer}, $written);
                $totalBytesThisIteration += $written;
                $madeProgress = 1;
            }
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

L<PageCamel::Protocol::HTTP2::Server>, L<PageCamel::CMDLine::WebFrontend>

=cut
