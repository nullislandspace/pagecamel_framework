package PageCamel::CMDLine::WebFrontend::HTTP3Handler;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 6.0;
use Array::Contains;
use utf8;
use Data::Dumper;
#---AUTOPRAGMAEND---

no warnings 'experimental::args_array_with_signatures';

use base 'PageCamel::CMDLine::WebFrontend::BaseHTTPHandler';

use PageCamel::Protocol::HTTP3;
use IO::Socket::UNIX;
use IO::Select;
use Socket qw(MSG_PEEK);
use Time::HiRes qw(time);
use Scalar::Util qw(blessed refaddr);
use PageCamel::Helpers::DateStrings;

sub new($class, %config) {
    my $self = bless \%config, $class;

    # Required parameters - now we expect h3Config instead of quicConnection
    foreach my $key (qw[h3Config backendSocketPath pagecamelInfo]) {
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
    # Per-stream pending flush flag (for buffered responses awaiting buffer drain)
    $self->{streamPendingFlush} = {};
    # Per-stream chunked encoding flag (for uploads without Content-Length)
    $self->{streamUseChunked} = {};
    # Per-stream headers storage (populated from on_request callback)
    $self->{streamHeaders} = {};

    return $self;
}

# Initialize the HTTP/3 connection. Can be called explicitly for multi-connection
# mode, or implicitly via run() for per-connection fork mode.
sub init($self) {
    return $self->{h3conn} if defined($self->{h3conn});

    my $config = $self->{h3Config};

    # Create unified HTTP/3 connection
    my $h3conn;
    eval {
        $h3conn = PageCamel::Protocol::HTTP3::Connection->new_server(
            dcid => $config->{dcid},
            scid => $config->{scid},
            original_dcid => $config->{original_dcid},
            local_addr => $config->{local_addr},
            local_port => $config->{local_port},
            remote_addr => $config->{remote_addr},
            remote_port => $config->{remote_port},
            version => $config->{version} // 1,
            ssl_domains => $config->{ssl_domains},
            default_domain => $config->{default_domain},
            default_backend => $config->{default_backend},
            initial_max_data => $config->{initial_max_data} // 10 * 1024 * 1024,
            initial_max_stream_data_bidi => $config->{initial_max_stream_data_bidi} // 1024 * 1024,
            initial_max_streams_bidi => $config->{initial_max_streams_bidi} // 100,
            max_idle_timeout_ms => $config->{max_idle_timeout_ms} // 30000,
            cc_algo => $config->{cc_algo} // 1,  # CUBIC
            enable_debug => $config->{enable_debug} // 0,

            # Callbacks
            on_send_packet => sub($data, $addr, $port) {
                if(defined($self->{sendPacketCallback})) {
                    return $self->{sendPacketCallback}->($data, "$addr:$port");
                }
                return -1;  # No callback configured
            },
            on_request => sub($streamId, $headersRef, $body, $isConnect) {
                $self->handleRequest($self->{h3conn}, $streamId, $headersRef, $body, $isConnect);
            },
            on_request_body => sub($streamId, $data, $fin) {
                $self->handleStreamData($self->{h3conn}, $streamId, $data, $fin);
            },
            on_stream_close => sub($streamId, $errorCode) {
                $self->cleanupStream($streamId);
            },
        );
    };
    if($@) {
        return undef;
    }

    $self->{h3conn} = $h3conn;

    # Process initial packet if provided
    if(defined($config->{initial_packet})) {
        my $rv;
        eval {
            $rv = $h3conn->process_packet(
                $config->{initial_packet},
                $config->{remote_addr},
                $config->{remote_port}
            );
        };
        if($@) {
            return undef;
        }
        if($rv < 0 && $rv != PageCamel::Protocol::HTTP3::H3_WOULDBLOCK()) {
            print STDERR "HTTP3Handler: Initial packet processing error: $rv\n";
        }
        eval { $h3conn->flush_packets(); };
        if($@) {
        }
    }

    return $h3conn;
}

# Get the underlying h3 connection object (calls init() if needed)
sub h3conn($self) {
    return $self->init();
}

# Check if connection is closing/closed
sub is_closing($self) {
    my $h3conn = $self->{h3conn};
    return 1 unless defined($h3conn);
    return $h3conn->is_closing();
}

# Get timeout in milliseconds
sub get_timeout_ms($self) {
    my $h3conn = $self->{h3conn};
    return 1000 unless defined($h3conn);  # Default 1 second if not initialized
    return $h3conn->get_timeout_ms();
}

# Handle timeout
sub handle_timeout($self) {
    my $h3conn = $self->{h3conn};
    return unless defined($h3conn);
    return $h3conn->handle_timeout();
}

# Get connection IDs for routing
sub get_connection_ids($self) {
    my $config = $self->{h3Config};
    return () unless defined($config);
    my @ids;
    push @ids, $config->{dcid} if defined($config->{dcid});
    push @ids, $config->{scid} if defined($config->{scid});
    push @ids, $config->{original_dcid} if defined($config->{original_dcid});
    return @ids;
}

sub protocolVersion($self) {
    return 'HTTP/3';
}

sub run($self) {
    # Initialize connection if not already done
    my $h3conn = $self->init();

    # Buffering variables
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

        # Get timeout from HTTP/3 connection
        my $timeout_ms = $h3conn->get_timeout_ms();
        my $timeout = $timeout_ms / 1000;  # Convert to seconds
        $timeout = 0.001 if($timeout < 0.001);  # Minimum 1ms
        $timeout = 1 if($timeout > 1);  # Cap at 1 second

        $ERRNO = 0;
        my ($canRead, $canWrite, undef) = IO::Select->select($readSet, $writeSet, undef, $timeout);

        # Handle EINTR
        if(!defined($canRead) && $ERRNO{EINTR}) {
            next;
        }

        $canRead //= [];
        $canWrite //= [];

        # Handle timeouts
        $h3conn->handle_timeout();

        # Check if connection is still alive
        if($h3conn->is_closing()) {
            $clientdisconnect = 1;
        }

        # Handle readable backend sockets
        foreach my $socket (@{$canRead}) {
            $self->handleBackendData($h3conn, $socket, \$toclientbuffer, $maxBufferSize);
        }

        # Build hash of writable sockets
        my %canWriteHash = map { $_ => 1 } @{$canWrite};

        # Write to backends from per-stream buffers
        $self->writeToBackends($blocksize, 1000, $finishcountdown, \%canWriteHash);

        # Process any streams waiting for a backend connection
        $self->processWaitingStreams($h3conn);

        # Flush pending data and send packets
        $self->flushPendingStreams($h3conn);

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

# Process incoming UDP packet from parent process
sub processPacket($self, $data, $remoteAddr, $remotePort) {
    my $h3conn = $self->{h3conn};
    return unless defined($h3conn);

    my $rv = $h3conn->process_packet($data, $remoteAddr, $remotePort);
    if($rv < 0 && $rv != PageCamel::Protocol::HTTP3::H3_WOULDBLOCK()) {
        print STDERR "HTTP3Handler: Packet processing error: $rv\n";
    }

    $h3conn->flush_packets();
    return $rv;
}

sub handleRequest($self, $h3conn, $streamId, $headersRef, $body, $isConnect) {
    $self->{streamsHandled}++;

    # Store headers for later use
    $self->{streamHeaders}->{$streamId} = $headersRef;

    if($isConnect) {
        $self->handleConnectRequest($h3conn, $streamId, $headersRef);
    } else {
        $self->handleNormalRequest($h3conn, $streamId, $headersRef, $body);
    }
}

sub handleNormalRequest($self, $h3conn, $streamId, $headersRef, $body) {
    # Convert HTTP/3 headers to HTTP/1.1 request (without PAGECAMEL overhead)
    my $request = $self->translateRequest($streamId, $headersRef, $body);

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
        $h3conn->send_response(
            $streamId,
            590,
            ['content-type', 'text/html; charset=UTF-8'],
            $self->{errorPage590Html} // ''
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

sub handleConnectRequest($self, $h3conn, $streamId, $headersRef) {
    # Check for WebSocket upgrade via extended CONNECT (RFC 9220)
    my %h;
    for(my $i = 0; $i < scalar(@{$headersRef}); $i += 2) {
        $h{$headersRef->[$i]} = $headersRef->[$i + 1];
    }

    my $protocol = $h{':protocol'} // '';
    if($protocol ne 'websocket') {
        # Reject non-WebSocket CONNECT requests
        $h3conn->send_response($streamId, 400, ['content-type', 'text/plain'], 'Bad Request');
        return;
    }

    # Translate to HTTP/1.1 WebSocket upgrade (without PAGECAMEL overhead)
    my $request = $self->translateWebsocketUpgrade($streamId, $headersRef);

    # Try to acquire backend from pool
    my $backend = $self->acquireBackend($streamId);
    if(!defined($backend)) {
        my $activeBackends = scalar(keys %{$self->{streamBackends}});
        if($activeBackends >= $self->{maxPoolSize}) {
            push @{$self->{waitingForBackend}}, [$streamId, $request, 'tunnel_pending'];
            return;
        }

        $h3conn->send_response($streamId, 590, ['content-type', 'text/html'], $self->{errorPage590Html} // '');
        return;
    }

    # Buffer request for backend
    $self->{tobackendbuffers}->{$streamId} = $request;

    # Mark as tunnel pending
    $self->{streamStates}->{$streamId} = 'tunnel_pending';
    $self->{streamResponses}->{$streamId} = '';

    return;
}

sub handleStreamData($self, $h3conn, $streamId, $data, $fin) {
    # Handle incoming data on a stream (for tunnels/WebSocket AND request bodies)
    my $state = $self->{streamStates}->{$streamId} // '';

    return unless defined($data) && length($data);

    if($state eq 'tunnel_active') {
        # Forward data to backend (WebSocket tunnel)
        my $backend = $self->{streamBackends}->{$streamId};
        if(defined($backend)) {
            $self->{tobackendbuffers}->{$streamId} //= '';
            $self->{tobackendbuffers}->{$streamId} .= $data;
        }
    } elsif($state eq 'waiting_response') {
        # Forward request body data to backend (PUT/POST uploads)
        my $backend = $self->{streamBackends}->{$streamId};
        if(defined($backend)) {
            $self->{tobackendbuffers}->{$streamId} //= '';
            if($self->{streamUseChunked}->{$streamId}) {
                # Encode as HTTP/1.1 chunk
                my $chunk = sprintf("%x\r\n%s\r\n", length($data), $data);
                $self->{tobackendbuffers}->{$streamId} .= $chunk;
            } else {
                $self->{tobackendbuffers}->{$streamId} .= $data;
            }
        }
    }

    return;
}

sub translateRequest($self, $streamId, $headersRef, $body) {
    # Convert HTTP/3 headers to HTTP/1.1 request format
    my %h;
    my @otherHeaders;
    my $hasContentLength = 0;

    for(my $i = 0; $i < scalar(@{$headersRef}); $i += 2) {
        my $name = $headersRef->[$i];
        my $value = $headersRef->[$i + 1];

        if($name =~ /^:/) {
            $h{$name} = $value;
        } else {
            push @otherHeaders, "$name: $value";
            if(lc($name) eq 'content-length') {
                $hasContentLength = 1;
            }
        }
    }

    my $method = $h{':method'} // 'GET';
    my $path = $h{':path'} // '/';
    my $authority = $h{':authority'} // '';

    # Build HTTP/1.1 request
    my $request = "$method $path HTTP/1.1\r\n";
    $request .= "Host: $authority\r\n";

    foreach my $hdr (@otherHeaders) {
        $request .= "$hdr\r\n";
    }

    my %methodsWithBody = ('POST' => 1, 'PUT' => 1, 'PATCH' => 1);
    if(!$hasContentLength && exists($methodsWithBody{$method})) {
        $request .= "Transfer-Encoding: chunked\r\n";
        $self->{streamUseChunked}->{$streamId} = 1;
    }

    $request .= "\r\n";

    if(defined($body) && length($body)) {
        if($self->{streamUseChunked}->{$streamId}) {
            $request .= sprintf("%x\r\n%s\r\n", length($body), $body);
        } else {
            $request .= $body;
        }
    }

    return $request;
}

sub translateWebsocketUpgrade($self, $streamId, $headersRef) {
    my %h;
    my @otherHeaders;

    for(my $i = 0; $i < scalar(@{$headersRef}); $i += 2) {
        my $name = $headersRef->[$i];
        my $value = $headersRef->[$i + 1];

        if($name =~ /^:/) {
            $h{$name} = $value;
        } else {
            push @otherHeaders, "$name: $value";
        }
    }

    my $path = $h{':path'} // '/';
    my $authority = $h{':authority'} // '';

    my $request = "GET $path HTTP/1.1\r\n";
    $request .= "Host: $authority\r\n";
    $request .= "Upgrade: websocket\r\n";
    $request .= "Connection: Upgrade\r\n";
    $request .= "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n";
    $request .= "Sec-WebSocket-Version: 13\r\n";

    foreach my $hdr (@otherHeaders) {
        next if($hdr =~ /^(connection|upgrade|sec-websocket)/i);
        $request .= "$hdr\r\n";
    }

    $request .= "\r\n";

    return $request;
}

sub handleBackendData($self, $h3conn, $socket, $toclientbufferRef, $maxBufferSize) {
    if(!defined($self->{backendToStream}->{$socket})) {
        return;
    }
    my $streamId = $self->{backendToStream}->{$socket};

    return if(length(${$toclientbufferRef}) >= $maxBufferSize);

    my $totalBytesRead = 0;
    my $maxReadPerCall = 4_000_000;

    while($totalBytesRead < $maxReadPerCall) {
        if($self->{streamCongestionBlocked}->{$streamId}) {
            last;
        }

        my $buf;
        my $bytesRead = $socket->sysread($buf, 65_536);

        if(!defined($bytesRead)) {
            if($ERRNO{EAGAIN} || $ERRNO{EWOULDBLOCK}) {
                last;
            }
            $self->{backenddisconnects}->{$streamId} = 1;
            $self->processBackendResponse($h3conn, $streamId);
            return;
        }

        if($bytesRead == 0) {
            $self->{backenddisconnects}->{$streamId} = 1;
            $self->processBackendResponse($h3conn, $streamId);
            return;
        }

        $totalBytesRead += $bytesRead;
        $self->{backendBytesRead}->{$streamId} //= 0;
        $self->{backendBytesRead}->{$streamId} += $bytesRead;
        $self->{streamResponses}->{$streamId} .= $buf;

        $self->processBackendResponse($h3conn, $streamId);
    }

    return;
}

sub processBackendResponse($self, $h3conn, $streamId) {
    my $state = $self->{streamStates}->{$streamId} // '';
    my $response = $self->{streamResponses}->{$streamId} // '';

    if($state eq 'waiting_response') {
        my $headerEnd = index($response, "\r\n\r\n");
        return if($headerEnd < 0);

        my $headerBlock = substr($response, 0, $headerEnd);
        my $body = substr($response, $headerEnd + 4);

        my @lines = split(/\r\n/, $headerBlock);
        my $statusLine = shift @lines;

        my ($httpVersion, $status, $statusText) = $statusLine =~ m{^HTTP/(\S+)\s+(\d+)\s*(.*)$};
        $status //= 500;

        my @responseHeaders;
        my $contentLength;

        foreach my $line (@lines) {
            my ($name, $value) = split(/:\s*/, $line, 2);
            next unless(defined($name) && defined($value));

            $name = lc($name);
            next if($name eq 'connection');
            next if($name eq 'transfer-encoding');
            next if($name eq 'keep-alive');

            if($name eq 'content-length') {
                $contentLength = $value;
            }

            push @responseHeaders, $name, $value;
        }

        # Check for WebSocket upgrade
        my %respHeaders = @responseHeaders;
        if($self->{streamStates}->{$streamId} eq 'tunnel_pending' ||
           ($status == 101 && exists $respHeaders{'upgrade'})) {
            $self->{streamStates}->{$streamId} = 'tunnel_active';

            # Send 200 OK for HTTP/3 tunnel
            my @tunnelHeaders = grep { $_ ne 'content-length' } @responseHeaders;
            $h3conn->send_response_headers($streamId, 200, \@tunnelHeaders, 1);
            $self->{streamTunnels}->{$streamId} = 1;

            if(length($body)) {
                $h3conn->send_response_body($streamId, $body, 0);
                $h3conn->flush_packets();
            }
            $self->{streamResponses}->{$streamId} = '';
            return;
        }

        # Determine streaming vs buffering
        my $shouldStream = 0;
        if(defined($contentLength) && $contentLength > 1_000_000) {
            $shouldStream = 1;
        }

        if($shouldStream) {
            $self->{streamStates}->{$streamId} = 'streaming';
            $self->{streamContentLength}->{$streamId} = $contentLength;
            $self->{streamBytesSent}->{$streamId} = 0;
            $self->{streamStreams}->{$streamId} = 1;

            $h3conn->send_response_headers($streamId, $status, \@responseHeaders, 1);

            if(length($body)) {
                my $rv = $h3conn->send_response_body($streamId, $body, 0);
                if($rv == PageCamel::Protocol::HTTP3::H3_OK()) {
                    $self->{streamBytesSent}->{$streamId} += length($body);
                    $self->{streamResponses}->{$streamId} = '';
                    $h3conn->flush_packets();
                } else {
                    $self->{streamCongestionBlocked}->{$streamId} = 1;
                }
            } else {
                $self->{streamResponses}->{$streamId} = '';
            }
        } else {
            if($self->{backenddisconnects}->{$streamId}) {
                $h3conn->send_response($streamId, $status, \@responseHeaders, $body);
                $h3conn->flush_packets();
                $self->{streamPendingFlush}->{$streamId} = 1;
                $self->{streamResponses}->{$streamId} = '';
            } else {
                if(defined($contentLength) && length($body) >= $contentLength) {
                    $body = substr($body, 0, $contentLength);
                    $h3conn->send_response($streamId, $status, \@responseHeaders, $body);
                    $h3conn->flush_packets();
                    $self->{streamPendingFlush}->{$streamId} = 1;
                    $self->{streamResponses}->{$streamId} = '';
                }
            }
        }
    } elsif($state eq 'streaming') {
        if(length($response)) {
            my $rv = $h3conn->send_response_body($streamId, $response, 0);
            if($rv == PageCamel::Protocol::HTTP3::H3_OK()) {
                $self->{streamBytesSent}->{$streamId} += length($response);
                $self->{streamResponses}->{$streamId} = '';
                delete $self->{streamCongestionBlocked}->{$streamId};
                $h3conn->flush_packets();
            } else {
                $self->{streamCongestionBlocked}->{$streamId} = 1;
            }
        }

        my $contentLength = $self->{streamContentLength}->{$streamId};
        my $bytesSent = $self->{streamBytesSent}->{$streamId};
        my $bufferEmpty = length($self->{streamResponses}->{$streamId} // '') == 0;

        if($bufferEmpty &&
           ($self->{backenddisconnects}->{$streamId} ||
            (defined($contentLength) && $bytesSent >= $contentLength))) {
            $h3conn->send_response_body($streamId, '', 1);  # EOF
            $h3conn->flush_packets();
            $self->cleanupStream($streamId);
        }
    } elsif($state eq 'tunnel_active') {
        if(length($response)) {
            my $rv = $h3conn->send_response_body($streamId, $response, 0);
            if($rv == PageCamel::Protocol::HTTP3::H3_OK()) {
                $self->{streamResponses}->{$streamId} = '';
                $h3conn->flush_packets();
            }
        }

        # Only send EOF when buffer is empty AND backend disconnected
        my $bufferEmpty = length($self->{streamResponses}->{$streamId} // '') == 0;
        if($bufferEmpty && $self->{backenddisconnects}->{$streamId}) {
            $h3conn->send_response_body($streamId, '', 1);  # EOF
            $h3conn->flush_packets();
            $self->cleanupStream($streamId);
        }
    }

    return;
}

sub writeToBackends($self, $blocksize, $loopcount, $finishcountdown, $canWriteHashRef) {
    my $maxBytesPerIteration = 1_000_000;
    my $totalBytesThisIteration = 0;
    my $madeProgress = 1;

    while($madeProgress && $totalBytesThisIteration < $maxBytesPerIteration) {
        $madeProgress = 0;

        foreach my $streamId (keys %{$self->{tobackendbuffers}}) {
            my $backend = $self->{streamBackends}->{$streamId};
            next unless(defined($backend));
            next if($self->{backenddisconnects}->{$streamId});
            next unless($canWriteHashRef->{$backend});

            my $tobackendbuffer = \$self->{tobackendbuffers}->{$streamId};
            next unless(defined(${$tobackendbuffer}) && length(${$tobackendbuffer}));

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

sub flushPendingStreams($self, $h3conn) {
    # Flush packets first
    $h3conn->flush_packets();

    # Retry sending buffered data for streams
    foreach my $streamId (keys %{$self->{streamResponses}}) {
        my $response = $self->{streamResponses}->{$streamId};
        next unless(defined($response) && length($response));

        my $state = $self->{streamStates}->{$streamId} // '';

        if($state eq 'streaming') {
            delete $self->{streamCongestionBlocked}->{$streamId};

            my $rv = $h3conn->send_response_body($streamId, $response, 0);
            if($rv == PageCamel::Protocol::HTTP3::H3_OK()) {
                $self->{streamBytesSent}->{$streamId} += length($response);
                $self->{streamResponses}->{$streamId} = '';
                $h3conn->flush_packets();
            } else {
                $self->{streamCongestionBlocked}->{$streamId} = 1;
            }

            my $contentLength = $self->{streamContentLength}->{$streamId};
            my $bytesSent = $self->{streamBytesSent}->{$streamId};
            my $bufferEmpty = length($self->{streamResponses}->{$streamId} // '') == 0;

            if($bufferEmpty &&
               ($self->{backenddisconnects}->{$streamId} ||
                (defined($contentLength) && $bytesSent >= $contentLength))) {
                $h3conn->send_response_body($streamId, '', 1);
                $h3conn->flush_packets();
                $self->cleanupStream($streamId);
            }
        } elsif($state eq 'tunnel_active') {
            my $rv = $h3conn->send_response_body($streamId, $response, 0);
            if($rv == PageCamel::Protocol::HTTP3::H3_OK()) {
                $self->{streamResponses}->{$streamId} = '';
                $h3conn->flush_packets();
            }

            # Only send EOF when buffer is empty AND backend disconnected
            my $bufferEmpty = length($self->{streamResponses}->{$streamId} // '') == 0;
            if($bufferEmpty && $self->{backenddisconnects}->{$streamId}) {
                $h3conn->send_response_body($streamId, '', 1);
                $h3conn->flush_packets();
                $self->cleanupStream($streamId);
            }
        }
    }

    return;
}

sub cleanupStream($self, $streamId) {
    my $isTunnel = defined($self->{streamTunnels}->{$streamId});
    my $backendClosed = $self->{backenddisconnects}->{$streamId} // 0;
    my $reusable = !$isTunnel && !$backendClosed;

    my $backend = $self->{streamBackends}->{$streamId};
    if(defined($backend)) {
        $self->releaseBackend($streamId, $reusable);
    } else {
        delete $self->{streamBackends}->{$streamId};
    }

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
    delete $self->{streamUseChunked}->{$streamId};
    delete $self->{streamHeaders}->{$streamId};

    return;
}

sub cleanup($self) {
    foreach my $streamId (keys %{$self->{streamBackends}}) {
        $self->cleanupStream($streamId);
    }

    foreach my $streamId (keys %{$self->{streamPendingFlush}}) {
        $self->cleanupStream($streamId);
    }

    while(my $backend = pop @{$self->{backendPool}}) {
        eval { close($backend); };
    }

    $self->{waitingForBackend} = [];

    return;
}

1;

__END__

=head1 NAME

PageCamel::CMDLine::WebFrontend::HTTP3Handler - HTTP/3 request handler using unified C library

=head1 SYNOPSIS

    use PageCamel::CMDLine::WebFrontend::HTTP3Handler;

    my $handler = PageCamel::CMDLine::WebFrontend::HTTP3Handler->new(
        h3Config => {
            dcid => $client_dcid,
            scid => $our_scid,
            local_addr => '0.0.0.0',
            local_port => 443,
            remote_addr => $client_ip,
            remote_port => $client_port,
            ssl_domains => { ... },
            default_domain => 'example.com',
            initial_packet => $first_udp_packet,
        },
        backendSocketPath => '/run/pagecamel/backend.sock',
        pagecamelInfo => {
            lhost    => '192.168.1.1',
            lport    => 443,
            peerhost => '10.0.0.1',
            peerport => 54321,
        },
        sendPacketCallback => sub($data, $addr) { ... },
    );

    $handler->run();

=head1 DESCRIPTION

This module handles HTTP/3 requests using the unified PageCamel::Protocol::HTTP3
library, which integrates ngtcp2 (QUIC) and nghttp3 (HTTP/3) with direct C-to-C
callback wiring.

This eliminates the data corruption issues from the previous implementation
that used Perl trampolines for internal ngtcp2<->nghttp3 callbacks.

=head1 CHANGES FROM PREVIOUS VERSION

=over 4

=item * Uses PageCamel::Protocol::HTTP3 unified module instead of separate XS modules

=item * No longer requires PageCamel::Protocol::HTTP3::Server or QUIC::Connection

=item * Callbacks are now handled in C, only crossing to Perl for application events

=item * Configuration passed via h3Config hash instead of quicConnection object

=back

=head1 SEE ALSO

L<PageCamel::Protocol::HTTP3>,
L<PageCamel::CMDLine::WebFrontend::HTTP2Handler>

=cut
