package PageCamel::Protocol::HTTP2::Frame::Window_update;
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
use PageCamel::Protocol::HTTP2::Constants qw(:flags :errors :limits);
use PageCamel::Protocol::HTTP2::Trace qw(tracer);

sub decode($con, $buf_ref, $buf_offset, $length) {
    my $frame_ref = $con->decode_context->{frame};

    if ( $length != 4 ) {
        tracer->error(
            "Received windows_update frame with invalid length $length");
        $con->error(FRAME_SIZE_ERROR);
        return;
    }

    my $fcw_add = unpack 'N', substr ${$buf_ref}, $buf_offset, 4;
    $fcw_add &= 0x7FFF_FFFF;

    if ( $fcw_add == 0 ) {
        tracer->error("Received flow-control window increment of 0");
        $con->error(PROTOCOL_ERROR);
        return;
    }

    if ( $frame_ref->{stream} == 0 ) {
        if ( $con->fcw_send($fcw_add) > MAX_FCW_SIZE ) {
            $con->error(FLOW_CONTROL_ERROR);
        }
        else {
            $con->send_blocked();
        }
    }
    else {
        my $fcw = $con->stream_fcw_send( $frame_ref->{stream}, $fcw_add );
        if ( defined $fcw && $fcw > MAX_FCW_SIZE ) {
            tracer->warning("flow-control window size exceeded MAX_FCW_SIZE");
            $con->stream_error( $frame_ref->{stream}, FLOW_CONTROL_ERROR );
        }
        elsif ( defined $fcw ) {
            $con->stream_send_blocked( $frame_ref->{stream} );
        }
    }
    return $length;
}

sub encode($con, $flags_ref, $stream, $data) {
    return pack 'N', $data;
}

1;
