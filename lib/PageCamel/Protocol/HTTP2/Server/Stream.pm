package PageCamel::Protocol::HTTP2::Server::Stream;
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
use PageCamel::Protocol::HTTP2::Constants qw(:states);
use Scalar::Util ();

=encoding utf-8

=head1 NAME

PageCamel::Protocol::HTTP2::Server::Stream - HTTP/2 server response stream

=head1 SYNOPSIS

    my $server_stream = $server->response_stream(
        ':status'  => 200,
        stream_id  => $stream_id,
        headers    => [
            'server' => 'perl-Protocol-HTTP2/0.01',
        ],
        on_cancel => sub {
            ...
        }
    );

    # Send partial data
    $server_stream->send($chunk_of_data);

    ## 3 ways to finish stream:
    #
    # The best: send last chunk and close stream in one action
    $server_stream->last($chunk_of_data);

    # Close the stream (will send empty frame)
    $server_stream->close();

    # Destroy object (will send empty frame)
    undef $server_stream

=cut

sub new($class, %opts) {
    my $self = bless {%opts}, $class;

    if ( my $on_cancel = $self->{on_cancel} ) {
        Scalar::Util::weaken( my $self = $self );
        $self->{con}->stream_cb(
            $self->{stream_id},
            CLOSED,
            sub {
                return if $self->{done};
                $self->{done} = 1;
                $on_cancel->();
            }
        );
    }

    return $self;
}

sub send($self, $data = undef) {
    $self->{con}->send_data( $self->{stream_id}, $data );
    return;
}

sub last($self, $data = undef) {
    $self->{done} = 1;
    $self->{con}->send_data( $self->{stream_id}, $data, 1 );
    return;
}

sub close($self) {
    $self->{done} = 1;
    $self->{con}->send_data( $self->{stream_id}, undef, 1 );
    return;
}

sub DESTROY($self) {
    if(!$self->{done} && $self->{con}) {
        $self->{con}->send_data( $self->{stream_id}, undef, 1 );
    }
    return;
}

1;
