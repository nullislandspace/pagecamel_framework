package PageCamel::CMDLine::WebFrontend::BaseHTTPHandler;
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

use IO::Socket::UNIX;
use IO::Select;
use Socket qw(MSG_PEEK MSG_DONTWAIT);
use Time::HiRes qw(time);
use PageCamel::Helpers::DateStrings;

=head1 NAME

PageCamel::CMDLine::WebFrontend::BaseHTTPHandler - Base class for HTTP/2 and HTTP/3 handlers

=head1 DESCRIPTION

Provides shared backend connection pooling functionality for HTTP/2 and HTTP/3 handlers.
Each handler instance maintains its own connection pool, isolated per-client.

=head1 METHODS

=cut

=head2 initPooling

Initialize the backend connection pooling data structures.
Should be called from the subclass constructor.

=cut

sub initPooling($self) {
    # Stream to backend connection mapping
    $self->{streamBackends} = {};
    # Reverse lookup: backend socket → stream ID (for O(1) lookup)
    $self->{backendToStream} = {};
    # Backend connection pool (Keep-Alive reuse)
    $self->{backendPool} = [];           # Available connections ready for reuse
    $self->{maxPoolSize} = 8;            # Max connections to keep in pool
    $self->{waitingForBackend} = [];     # Queue of [streamId, request, state] waiting for backend

    return;
}

=head2 createPooledBackend($protocolVersion)

Create a new backend connection and send PAGECAMEL overhead header immediately.
The protocol version (e.g., "HTTP/2" or "HTTP/3") is passed as a parameter.

Returns the backend socket on success, undef on failure.

=cut

sub createPooledBackend($self, $protocolVersion) {
    my $startTime = time();

    my $backend = IO::Socket::UNIX->new(
        Type    => SOCK_STREAM,
        Peer    => $self->{backendSocketPath},
        Timeout => 15,
    );

    if(!defined($backend)) {
        print STDERR getISODate() . " $protocolVersion: Failed to connect to backend: $ERRNO\n";
        return;
    }

    # Send PAGECAMEL overhead header immediately (required within 15 seconds)
    my $info = $self->{pagecamelInfo};
    my $usessl = $info->{usessl} // 1;
    my $pid = $info->{pid} // $PID;
    my $overhead = "PAGECAMEL $info->{lhost} $info->{lport} $info->{peerhost} $info->{peerport} $usessl $pid $protocolVersion\r\n";

    my $written = syswrite($backend, $overhead);
    if(!defined($written) || $written != length($overhead)) {
        carp("$protocolVersion: Failed to send overhead to backend: $ERRNO");
        close($backend);
        return;
    }

    # Set non-blocking mode for async I/O
    $backend->blocking(0);

    my $elapsed = time() - $startTime;
    if($elapsed > 0.001) {  # Log if > 1ms
        print STDERR getISODate() . " $protocolVersion: createPooledBackend took ${elapsed}s\n";
    }

    return $backend;
}

=head2 isBackendAlive($backend)

Check if a backend connection is still open and healthy.
Uses select() with 0 timeout to check for readability without blocking.
If readable with no data or error, connection is closed.

Returns 1 if healthy, 0 if dead.

=cut

sub isBackendAlive($self, $backend) {
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

=head2 acquireBackend($streamId)

Acquire a backend connection for the given stream.
First tries to get a healthy connection from the pool, otherwise creates a new one.
If at max capacity, returns undef and caller should queue the request.

Returns backend socket on success, undef if at capacity or on error.

=cut

sub acquireBackend($self, $streamId) {
    # First, try to get a healthy connection from the pool
    while(scalar(@{$self->{backendPool}}) > 0) {
        my $backend = pop @{$self->{backendPool}};

        if($self->isBackendAlive($backend)) {
            # Connection is healthy, assign to stream
            $self->{streamBackends}->{$streamId} = $backend;
            $self->{backendToStream}->{$backend} = $streamId;
            return $backend;
        } else {
            # Connection is dead, close and try next
            eval { close($backend); };
        }
    }

    # Pool empty, check if we can create a new connection
    my $activeBackends = scalar(keys %{$self->{streamBackends}});
    if($activeBackends >= $self->{maxPoolSize}) {
        # At max capacity, caller should queue the stream
        return;
    }

    # Create new connection (subclass must implement protocolVersion)
    my $backend = $self->createPooledBackend($self->protocolVersion());
    if(!defined($backend)) {
        return;
    }

    $self->{streamBackends}->{$streamId} = $backend;
    $self->{backendToStream}->{$backend} = $streamId;

    return $backend;
}

=head2 releaseBackend($streamId, $reusable)

Release a backend connection from a stream.
If reusable and healthy, returns it to the pool. Otherwise closes it.

=cut

sub releaseBackend($self, $streamId, $reusable = 1) {
    my $backend = $self->{streamBackends}->{$streamId};
    return if(!defined($backend));

    # Clean up mappings
    delete $self->{streamBackends}->{$streamId};
    delete $self->{backendToStream}->{$backend};

    # Check if we should return to pool
    if($reusable && $self->isBackendAlive($backend) && scalar(@{$self->{backendPool}}) < $self->{maxPoolSize}) {
        push @{$self->{backendPool}}, $backend;
    } else {
        eval { close($backend); };
    }

    return;
}

=head2 processWaitingStreams($server)

Process streams waiting for a backend connection.
Called from the main event loop after backends are released.

=cut

sub processWaitingStreams($self, $server) {
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
    }

    # Put remaining waiting streams back
    unshift @{$self->{waitingForBackend}}, @stillWaiting;

    return;
}

=head2 closeAllPooledBackends

Close all connections in the pool. Called during cleanup.

=cut

sub closeAllPooledBackends($self) {
    while(my $backend = pop @{$self->{backendPool}}) {
        eval { close($backend); };
    }
    return;
}

=head2 protocolVersion

Returns the protocol version string (e.g., "HTTP/2" or "HTTP/3").
Must be implemented by subclasses.

=cut

sub protocolVersion($self) {
    croak("protocolVersion() must be implemented by subclass");
}

1;
