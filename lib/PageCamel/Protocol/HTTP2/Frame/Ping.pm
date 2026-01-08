package PageCamel::Protocol::HTTP2::Frame::Ping;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---
use PageCamel::Protocol::HTTP2::Constants qw(:flags :errors :limits);
use PageCamel::Protocol::HTTP2::Trace qw(tracer);

sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    my $frame_ref = $con->decode_context->{frame};

    # PING associated with connection
    if ( $frame_ref->{stream} != 0 ) {
        $con->error(PROTOCOL_ERROR);
        return;
    }

    # payload is 8 octets
    if ( $length != PING_PAYLOAD_SIZE ) {
        $con->error(FRAME_SIZE_ERROR);
        return;
    }

    $con->ack_ping( \substr ${$buf_ref}, $buf_offset, $length )
      unless $frame_ref->{flags} & ACK;

    return $length;
}

sub encode {
    my ( $con, $flags_ref, $stream, $data_ref ) = @_;
    if ( length(${$data_ref}) != PING_PAYLOAD_SIZE ) {
        $con->error(INTERNAL_ERROR);
        return;
    }
    return ${$data_ref};
}

1;
