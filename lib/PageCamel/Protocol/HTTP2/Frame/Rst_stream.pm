package PageCamel::Protocol::HTTP2::Frame::Rst_stream;
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
use PageCamel::Protocol::HTTP2::Constants qw(const_name :flags :errors);
use PageCamel::Protocol::HTTP2::Trace qw(tracer);

sub decode($con, $buf_ref, $buf_offset, $length) {
    my $frame_ref = $con->decode_context->{frame};

    # RST_STREAM associated with stream
    if ( $frame_ref->{stream} == 0 ) {
        tracer->error("Received reset stream with stream id 0");
        $con->error(PROTOCOL_ERROR);
        return;
    }

    if ( $length != 4 ) {
        tracer->error("Received reset stream with invalid length $length");
        $con->error(FRAME_SIZE_ERROR);
        return;
    }

    my $code = unpack( 'N', substr( ${$buf_ref}, $buf_offset, 4 ) );

    tracer->debug( "Receive reset stream with error code "
          . const_name( "errors", $code )
          . "\n" );
    $con->stream_reset( $frame_ref->{stream}, $code );

    return $length;
}

sub encode($con, $flags_ref, $stream, $data) {
    $con->stream_reset( $stream, $data );
    return pack 'N', $data;
}

1;
