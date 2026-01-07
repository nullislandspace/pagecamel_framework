package PageCamel::Protocol::HTTP2::Frame::Rst_stream;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---
use PageCamel::Protocol::HTTP2::Constants qw(const_name :flags :errors);
use PageCamel::Protocol::HTTP2::Trace qw(tracer);

sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    my $frame_ref = $con->decode_context->{frame};

    # RST_STREAM associated with stream
    if ( $frame_ref->{stream} == 0 ) {
        tracer->error("Received reset stream with stream id 0");
        $con->error(PROTOCOL_ERROR);
        return undef;
    }

    if ( $length != 4 ) {
        tracer->error("Received reset stream with invalid length $length");
        $con->error(FRAME_SIZE_ERROR);
        return undef;
    }

    my $code = unpack( 'N', substr( ${$buf_ref}, $buf_offset, 4 ) );

    tracer->debug( "Receive reset stream with error code "
          . const_name( "errors", $code )
          . "\n" );
    $con->stream_reset( $frame_ref->{stream}, $code );

    return $length;
}

sub encode {
    my ( $con, $flags_ref, $stream, $data ) = @_;
    $con->stream_reset( $stream, $data );
    return pack 'N', $data;
}

1;
