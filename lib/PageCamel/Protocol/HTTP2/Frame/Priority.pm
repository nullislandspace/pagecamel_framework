package PageCamel::Protocol::HTTP2::Frame::Priority;
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
use PageCamel::Protocol::HTTP2::Constants qw(:flags :errors);
use PageCamel::Protocol::HTTP2::Trace qw(tracer);

sub decode($con, $buf_ref, $buf_offset, $length) {
    my $frame_ref = $con->decode_context->{frame};

    # Priority frames MUST be associated with a stream
    if ( $frame_ref->{stream} == 0 ) {
        $con->error(PROTOCOL_ERROR);
        return;
    }

    if ( $length != 5 ) {
        $con->error(FRAME_SIZE_ERROR);
        return;
    }

    my ( $stream_dep, $weight ) =
      unpack( 'NC', substr( ${$buf_ref}, $buf_offset, 5 ) );
    my $exclusive = $stream_dep >> 31;
    $stream_dep &= 0x7FFF_FFFF;
    $weight++;

    $con->stream_weight( $frame_ref->{stream}, $weight );
    if(!$con->stream_reprio( $frame_ref->{stream}, $exclusive, $stream_dep ))
    {
        tracer->error("Malformed priority frame");
        $con->error(PROTOCOL_ERROR);
        return;
    }

    return $length;
}

sub encode($con, $flags_ref, $stream, $data_ref) {
    my $stream_dep = $data_ref->[0];
    my $weight     = $data_ref->[1] - 1;
    return pack( 'NC', $stream_dep, $weight );
}

1;
