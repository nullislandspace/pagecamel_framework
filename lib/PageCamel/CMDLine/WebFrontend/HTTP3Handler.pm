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

    # Convert HTTP/3 headers to HTTP/1.1 request
    my $request = $self->translateRequest($streamId, $headers, $data);

    # Connect to backend
    my $backend = $self->connectBackend($streamId);
    if(!defined($backend)) {
        # Send 590 Backend Not Running
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

    # Translate to HTTP/1.1 WebSocket upgrade
    my $request = $self->translateWebsocketUpgrade($streamId, $headers);

    # Connect to backend
    my $backend = $self->connectBackend($streamId);
    if(!defined($backend)) {
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

    # Prepend PAGECAMEL overhead header
    my $info = $self->{pagecamelInfo};
    my $overhead = "PAGECAMEL $info->{lhost} $info->{lport} $info->{peerhost} $info->{peerport} 1 $PID HTTP/3\r\n";

    return $overhead . $request;
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

    # Prepend PAGECAMEL overhead header
    my $info = $self->{pagecamelInfo};
    my $overhead = "PAGECAMEL $info->{lhost} $info->{lport} $info->{peerhost} $info->{peerport} 1 $PID HTTP/3\r\n";

    return $overhead . $request;
}

sub connectBackend($self, $streamId) {
    my $socketPath = $self->{backendSocketPath};

    my $backend = IO::Socket::UNIX->new(
        Type => SOCK_STREAM,
        Peer => $socketPath,
    );

    if(!defined($backend)) {
        print STDERR getISODate() . " HTTP3Handler: Cannot connect to backend: $ERRNO\n";
        return;
    }

    $backend->blocking(0);
    $self->{streamBackends}->{$streamId} = $backend;

    return $backend;
}

sub handleBackendData($self, $server, $socket, $toclientbufferRef, $maxBufferSize) {
    # Find which stream this backend belongs to
    my $streamId;
    foreach my $sid (keys %{$self->{streamBackends}}) {
        if($self->{streamBackends}->{$sid} == $socket) {
            $streamId = $sid;
            last;
        }
    }

    return unless(defined($streamId));

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
                $tunnel->send($body);
            }

            $self->{streamResponses}->{$streamId} = '';
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
                $stream->send($body);
                $self->{streamBytesSent}->{$streamId} += length($body);
            }

            $self->{streamResponses}->{$streamId} = '';
        } else {
            # Buffering mode - wait for complete response or disconnect
            if($self->{backenddisconnects}->{$streamId}) {
                # Send complete response
                $server->response($streamId, $status, \@responseHeaders, $body);
                $self->cleanupStream($streamId);
            } else {
                # Check if we have complete response
                if(defined($contentLength) && length($body) >= $contentLength) {
                    $body = substr($body, 0, $contentLength);
                    $server->response($streamId, $status, \@responseHeaders, $body);
                    $self->cleanupStream($streamId);
                }
            }
        }
    } elsif($state eq 'streaming') {
        # Forward data to stream
        my $stream = $self->{streamStreams}->{$streamId};
        if(defined($stream) && length($response)) {
            $stream->send($response);
            $self->{streamBytesSent}->{$streamId} += length($response);
            $self->{streamResponses}->{$streamId} = '';
        }

        # Check if complete
        my $contentLength = $self->{streamContentLength}->{$streamId};
        my $bytesSent = $self->{streamBytesSent}->{$streamId};

        if($self->{backenddisconnects}->{$streamId} ||
           (defined($contentLength) && $bytesSent >= $contentLength)) {
            $stream->close() if(defined($stream));
            $self->cleanupStream($streamId);
        }
    } elsif($state eq 'tunnel_active') {
        # Forward data through tunnel
        my $tunnel = $self->{streamTunnels}->{$streamId};
        if(defined($tunnel) && length($response)) {
            $tunnel->send($response);
            $self->{streamResponses}->{$streamId} = '';
        }

        if($self->{backenddisconnects}->{$streamId}) {
            $tunnel->close() if(defined($tunnel));
            $self->cleanupStream($streamId);
        }
    }

    return;
}

sub writeToBackends($self, $blocksize, $loopcount, $finishcountdown, $canWriteHashRef) {
    foreach my $streamId (keys %{$self->{tobackendbuffers}}) {
        my $backend = $self->{streamBackends}->{$streamId};
        next unless(defined($backend));

        my $buffer = $self->{tobackendbuffers}->{$streamId};
        next unless(defined($buffer) && length($buffer));

        # Only write if socket is writable
        next unless($canWriteHashRef->{$backend});

        my $sendcount = $loopcount;
        my $offset = 0;

        while($sendcount && length($buffer) > $offset) {
            my $remaining = length($buffer) - $offset;
            my $towrite = $remaining < $blocksize ? $remaining : $blocksize;

            my $written;
            eval {
                $written = syswrite($backend, $buffer, $towrite, $offset);
            };

            if($EVAL_ERROR || !defined($written)) {
                $self->{backenddisconnects}->{$streamId} = 1;
                last;
            }

            $offset += $written;
            $sendcount--;
        }

        # Remove written data
        if($offset > 0) {
            $self->{tobackendbuffers}->{$streamId} = substr($buffer, $offset);
        }
    }

    return;
}

sub cleanupStream($self, $streamId) {
    # Close backend connection
    my $backend = $self->{streamBackends}->{$streamId};
    if(defined($backend)) {
        eval { $backend->close(); };
    }

    # Clean up stream state
    delete $self->{streamBackends}->{$streamId};
    delete $self->{streamResponses}->{$streamId};
    delete $self->{streamStates}->{$streamId};
    delete $self->{streamStreams}->{$streamId};
    delete $self->{streamTunnels}->{$streamId};
    delete $self->{tobackendbuffers}->{$streamId};
    delete $self->{backenddisconnects}->{$streamId};
    delete $self->{streamContentLength}->{$streamId};
    delete $self->{streamBytesSent}->{$streamId};

    return;
}

sub cleanup($self) {
    # Clean up all streams
    foreach my $streamId (keys %{$self->{streamBackends}}) {
        $self->cleanupStream($streamId);
    }

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
