package PageCamel::Protocol::HTTP2::Server::Tunnel;
#---AUTOPRAGMASTART---
use v5.42;
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
use PageCamel::Protocol::HTTP2::Constants qw(:states :frame_types);
use Scalar::Util ();

=encoding utf-8

=head1 NAME

PageCamel::Protocol::HTTP2::Server::Tunnel - HTTP/2 bidirectional tunnel (RFC 8441)

=head1 SYNOPSIS

    my $tunnel = $server->tunnel_response(
        stream_id => $stream_id,
        ':status' => 200,
        headers   => [
            'sec-websocket-protocol' => 'chat',
        ],
        on_data   => sub {
            my $data = shift;
            # Handle incoming tunnel data (e.g., WebSocket frames)
        },
        on_close  => sub {
            # Tunnel was closed
        },
    );

    # Send data through tunnel
    $tunnel->send($data);

    # Close tunnel
    $tunnel->close();

=cut

sub new($class, %opts) {
    my $self = bless {%opts}, $class;

    if ( my $on_close = $self->{on_close} ) {
        my $weak_self = $self;
        Scalar::Util::weaken($weak_self);
        $self->{con}->stream_cb(
            $self->{stream_id},
            CLOSED,
            sub {
                return if !$weak_self || $weak_self->{done};
                $weak_self->{done} = 1;
                $on_close->();
            }
        );
    }

    # Set up callback for received DATA frames on this tunnel
    if ( my $on_data = $self->{on_data} ) {
        my $weak_self = $self;
        Scalar::Util::weaken($weak_self);
        $self->{con}->stream_frame_cb(
            $self->{stream_id},
            DATA,
            sub {
                my $data = shift;
                $on_data->($data) if $on_data && $weak_self && !$weak_self->{done};
            }
        );
    }

    return $self;
}

# Set callback for receiving data on tunnel
sub on_data($self, $cb) {
    $self->{on_data} = $cb;
    my $weak_self = $self;
    Scalar::Util::weaken($weak_self);
    $self->{con}->stream_frame_cb(
        $self->{stream_id},
        DATA,
        sub {
            my $data = shift;
            $cb->($data) if $cb && $weak_self && !$weak_self->{done};
        }
    );
    return;
}

# Send data through tunnel (no END_STREAM flag)
sub send($self, $data) {
    return if $self->{done};
    $self->{con}->send_data( $self->{stream_id}, $data );
    return;
}

# Close the tunnel with optional final data
sub close($self, $data = undef) {
    return if $self->{done};
    $self->{done} = 1;
    $self->{con}->send_data( $self->{stream_id}, $data, 1 );
    return;
}

sub DESTROY($self) {
    if(!$self->{done} && $self->{con}) {
        $self->{con}->send_data( $self->{stream_id}, undef, 1 );
    }
    return;
}

1;
