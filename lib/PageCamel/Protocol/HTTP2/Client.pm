package PageCamel::Protocol::HTTP2::Client;
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
# autodie close excluded - conflicts with close() method
use PageCamel::Protocol::HTTP2::Connection;
use PageCamel::Protocol::HTTP2::Constants qw(:frame_types :flags :states :endpoints
  :errors);
use PageCamel::Protocol::HTTP2::Trace qw(tracer);
use Scalar::Util ();

=encoding utf-8

=head1 NAME

PageCamel::Protocol::HTTP2::Client - HTTP/2 client

=head1 SYNOPSIS

    use PageCamel::Protocol::HTTP2::Client;

    # Create client object
    my $client = PageCamel::Protocol::HTTP2::Client->new;

    # Prepare first request
    $client->request(

        # HTTP/2 headers
        ':scheme'    => 'http',
        ':authority' => 'localhost:8000',
        ':path'      => '/',
        ':method'    => 'GET',

        # HTTP/1.1 headers
        headers      => [
            'accept'     => '*/*',
            'user-agent' => 'perl-Protocol-HTTP2/0.13',
        ],

        # Callback when receive server's response
        on_done => sub {
            my ( $headers, $data ) = @_;
            ...
        },
    );

    # PageCamel::Protocol::HTTP2 is just HTTP/2 protocol decoder/encoder
    # so you must create connection yourself

    use AnyEvent;
    use AnyEvent::Socket;
    use AnyEvent::Handle;
    my $w = AnyEvent->condvar;

    # Plain-text HTTP/2 connection
    tcp_connect 'localhost', 8000, sub {
        my ($fh) = @_ or die "connection failed: $ERRNO\n";
        
        my $handle;
        $handle = AnyEvent::Handle->new(
            fh       => $fh,
            autocork => 1,
            on_error => sub {
                $_[0]->destroy;
                print "connection error\n";
                $w->send;
            },
            on_eof => sub {
                $handle->destroy;
                $w->send;
            }
        );

        # First write preface to peer
        while ( my $frame = $client->next_frame ) {
            $handle->push_write($frame);
        }

        # Receive servers frames
        # Reply to server
        $handle->on_read(
            sub {
                my $handle = shift;

                $client->feed( $handle->{rbuf} );

                $handle->{rbuf} = undef;
                while ( my $frame = $client->next_frame ) {
                    $handle->push_write($frame);
                }

                # Terminate connection if all done
                $handle->push_shutdown if $client->shutdown;
            }
        );
    };

    $w->recv;

=head1 DESCRIPTION

PageCamel::Protocol::HTTP2::Client is HTTP/2 client library. It's intended to make
http2-client implementations on top of your favorite event-loop.

=head2 METHODS

=head3 new

Initialize new client object

    my $client = PageCamel::Protocol::HTTP2::Client->new( %options );

Available options:

=over

=item on_push => sub {...}

If server send push promise this callback will be invoked

    on_push => sub {
        # received PUSH PROMISE headers
        my $pp_header = shift;
        ...
    
        # if we want reject this push
        # return undef
    
        # if we want to accept pushed resource
        # return callback to receive data
        return sub {
            my ( $headers, $data ) = @_;
            ...
        }
    },

=item upgrade => 0|1

Use HTTP/1.1 Upgrade to upgrade protocol from HTTP/1.1 to HTTP/2. Upgrade
possible only on plain (non-tls) connection. Default value is 0.

See
L<Starting HTTP/2 for "http" URIs|https://tools.ietf.org/html/rfc7540#section-3.2>

=item keepalive => 0|1

Keep connection alive after requests. Default value is 0. Don't forget to
explicitly call close method if set this to true.

=item on_error => sub {...}

Callback invoked on protocol errors

    on_error => sub {
        my $error = shift;
        ...
    },

=item on_change_state => sub {...}

Callback invoked every time when http/2 streams change their state.
See
L<Stream States|https://tools.ietf.org/html/rfc7540#section-5.1>

    on_change_state => sub {
        my ( $stream_id, $previous_state, $current_state ) = @_;
        ...
    },

=back

=cut

sub new($class, %opts) {
    my $self = {
        con            => undef,
        input          => '',
        active_streams => 0,
        keepalive      => exists $opts{keepalive}
        ? delete $opts{keepalive}
        : 0,
        settings => exists $opts{settings} ? $opts{settings} : {},
    };

    if ( exists $opts{on_push} ) {
        Scalar::Util::weaken( my $self = $self );

        my $cb = delete $opts{on_push};
        $opts{on_new_peer_stream} = sub {
            my $stream_id = shift;
            $self->active_streams(+1);

            $self->{con}->stream_cb(
                $stream_id,
                RESERVED,
                sub {
                    my $res =
                      $cb->( $self->{con}->stream_pp_headers($stream_id) );
                    if ( $res && ref $cb eq 'CODE' ) {
                        $self->{con}->stream_cb(
                            $stream_id,
                            CLOSED,
                            sub {
                                $res->(
                                    $self->{con}->stream_headers($stream_id),
                                    $self->{con}->stream_data($stream_id),
                                );
                                $self->active_streams(-1);
                            }
                        );
                    }
                    else {
                        $self->{con}
                          ->stream_error( $stream_id, REFUSED_STREAM );
                        $self->active_streams(-1);
                    }
                }
            );
        };
    }

    $self->{con} = PageCamel::Protocol::HTTP2::Connection->new( CLIENT, %opts );
    return bless $self, $class;
}

sub active_streams($self, $add = 0) {
    $self->{active_streams} += $add;
    if($self->{active_streams} <= 0 && !$self->{keepalive}) {
        $self->{con}->finish;
    }
    return;
}

=head3 request

Prepare HTTP/2 request.

    $client->request(

        # HTTP/2 headers
        ':scheme'    => 'http',
        ':authority' => 'localhost:8000',
        ':path'      => '/items',
        ':method'    => 'POST',

        # HTTP/1.1 headers
        headers      => [
            'content-type' => 'application/x-www-form-urlencoded',
            'user-agent' => 'perl-Protocol-HTTP2/0.06',
        ],

        # Callback when receive server's response
        on_done => sub {
            my ( $headers, $data ) = @_;
            ...
        },

        # Callback when receive stream reset
        on_error => sub {
            my $error_code = shift;
        },

        # Body of POST request
        data => "hello=world&test=done",
    );

You can chaining request one by one:

    $client->request( 1-st request )->request( 2-nd request );

Available callbacks:

=over

=item on_done => sub {...}

Invoked when full servers response is available

    on_done => sub {
        my ( $headers, $data ) = @_;
        ...
    },

=item on_headers => sub {...}

Invoked as soon as headers have been successfully received from the server

    on_headers => sub {
        my $headers = shift;
        ...

        # if we want reject any data
        # return undef

        # continue
        return 1
    }

=item on_data => sub {...}

If specified all data will be passed to this callback instead if on_done.
on_done will receive empty string.

    on_data => sub {
        my ( $partial_data, $headers ) = @_;
        ...

        # if we want cancel download
        # return undef

        # continue downloading
        return 1
    }

=item on_error => sub {...}

Callback invoked on stream errors

    on_error => sub {
        my $error = shift;
        ...
    }

=back

=cut

my @must = (qw(:authority :method :path :scheme));

sub request($self, %h) {
    my @miss = grep { !exists $h{$_} } @must;
    croak "Missing fields in request: @miss" if @miss;

    my $con = $self->{con};

    my $stream_id = $con->new_stream;
    if(!defined $stream_id) {
        if(exists $con->{on_error}) {
            $con->{on_error}->(PROTOCOL_ERROR);
            return $self;
        }
        croak "Can't create new stream, connection is closed";
    }

    $self->active_streams(+1);

    if ( $con->upgrade && !exists $self->{sent_upgrade} ) {
        $con->enqueue_raw(
            $con->upgrade_request(
                ( map { $_ => $h{$_} } @must ),
                headers => exists $h{headers} ? $h{headers} : []
            )
        );
        $self->{sent_upgrade} = 1;
        $con->stream_state( $stream_id, HALF_CLOSED );
    }
    else {
        if ( !$con->preface ) {
            $con->enqueue_raw( $con->preface_encode );
            $con->enqueue( SETTINGS, 0, 0, $self->{settings} );
            $con->preface(1);
        }

        $con->send_headers(
            $stream_id,
            [
                ( map { $_ => $h{$_} } @must ),
                exists $h{headers} ? @{ $h{headers} } : ()
            ],
            exists $h{data} ? 0 : 1
        );
        $con->send_data( $stream_id, $h{data}, 1 ) if exists $h{data};
    }

    Scalar::Util::weaken $self;
    Scalar::Util::weaken $con;

    $con->stream_cb(
        $stream_id,
        CLOSED,
        sub {
            if ( exists $h{on_error} && $con->stream_reset($stream_id) ) {
                $h{on_error}->( $con->stream_reset($stream_id) );
            }
            else {
                $h{on_done}->(
                    $con->stream_headers($stream_id),
                    $con->stream_data($stream_id),
                );
            }
            $self->active_streams(-1);
        }
    ) if exists $h{on_done};

    $con->stream_frame_cb(
        $stream_id,
        HEADERS,
        sub {
            my $res = $h{on_headers}->( $_[0] );
            return if $res;
            $con->stream_error( $stream_id, REFUSED_STREAM );
        }
    ) if exists $h{on_headers};

    $con->stream_frame_cb(
        $stream_id,
        DATA,
        sub {
            my $res = $h{on_data}->( $_[0], $con->stream_headers($stream_id), );
            return if $res;
            $con->stream_error( $stream_id, REFUSED_STREAM );
        }
    ) if exists $h{on_data};

    return $self;
}

=head3 keepalive

Keep connection alive after requests

    my $bool = $client->keepalive;
    $client = $client->keepalive($bool);

=cut

sub keepalive($self, $value = undef) {
    return defined $value
      ? scalar( $self->{keepalive} = $value, $self )
      : $self->{keepalive};
}

=head3 shutdown

Get connection status:

=over

=item 0 - active

=item 1 - closed (you can terminate connection)

=back

=cut

sub shutdown {
    return shift->{con}->shutdown;
}

=head3 close

Explicitly close connection (send GOAWAY frame). This is required if client
has keepalive option enabled.

=cut

sub close {
    return shift->{con}->finish;
}

=head3 next_frame

get next frame to send over connection to server.
Returns:

=over

=item undef - on error

=item 0 - nothing to send

=item binary string - encoded frame

=back

    # Example
    while ( my $frame = $client->next_frame ) {
        syswrite $fh, $frame;
    }

=cut

sub next_frame($self) {
    my $frame = $self->{con}->dequeue;
    tracer->debug("send one frame to wire\n") if $frame;
    return $frame;
}

=head3 feed

Feed decoder with chunks of server's response

    sysread $fh, $binary_data, 4096;
    $client->feed($binary_data);

=cut

sub feed($self, $chunk) {
    $self->{input} .= $chunk;
    my $offset = 0;
    my $len;
    my $con = $self->{con};
    tracer->debug( "got " . length($chunk) . " bytes on a wire\n" );
    if ( $con->upgrade ) {
        $len = $con->decode_upgrade_response( \$self->{input}, $offset );
        $con->shutdown(1) unless defined $len;
        return unless $len;
        $offset += $len;
        $con->upgrade(0);
        $con->enqueue_raw( $con->preface_encode );
        $con->preface(1);
    }
    while ( $len = $con->frame_decode( \$self->{input}, $offset ) ) {
        tracer->debug("decoded frame at $offset, length $len\n");
        $offset += $len;
    }
    $self->{input} = substr( $self->{input}, $offset ) if $offset;
    return;
}

=head3 ping

Send ping frame to server (to keep connection alive)

    $client->ping

or

    $client->ping($payload);

Payload can be arbitrary binary string and must contain 8 octets. If payload argument
is omitted client will send random data.

=cut

sub ping($self, $payload = undef) {
    return $self->{con}->send_ping($payload);
}

1;
