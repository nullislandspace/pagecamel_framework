package PageCamel::Protocol::HTTP2::Frame::Headers;
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
use PageCamel::Protocol::HTTP2::Constants qw(:flags :errors :states :limits);
use PageCamel::Protocol::HTTP2::Trace qw(tracer);

# 6.2 HEADERS
sub decode($con, $buf_ref, $buf_offset, $length) {
    my ( $pad, $offset, $weight, $exclusive, $stream_dep ) = ( 0, 0 );
    my $frame_ref = $con->decode_context->{frame};

    # Protocol errors
    if (
        # HEADERS frames MUST be associated with a stream
        $frame_ref->{stream} == 0
      )
    {
        $con->error(PROTOCOL_ERROR);
        return;
    }

    if ( $frame_ref->{flags} & PADDED ) {
        $pad = unpack( 'C', substr( ${$buf_ref}, $buf_offset, 1 ) );
        $offset += 1;
    }

    if ( $frame_ref->{flags} & PRIORITY_FLAG ) {
        ( $stream_dep, $weight ) =
          unpack( 'NC', substr( ${$buf_ref}, $buf_offset + $offset, 5 ) );
        $exclusive = $stream_dep >> 31;
        $stream_dep &= 0x7FFF_FFFF;
        $weight++;

        $con->stream_weight( $frame_ref->{stream}, $weight );
        if(!$con->stream_reprio(
                $frame_ref->{stream}, $exclusive, $stream_dep
            ))
        {
            tracer->error("Malformed HEADERS frame priority");
            $con->error(PROTOCOL_ERROR);
            return;
        }

        $offset += 5;
    }

    # Not enough space for header block
    my $hblock_size = $length - $offset - $pad;
    if ( $hblock_size < 0 ) {
        $con->error(PROTOCOL_ERROR);
        return;
    }

    $con->stream_header_block( $frame_ref->{stream},
        substr( ${$buf_ref}, $buf_offset + $offset, $hblock_size ) );

    # Stream header block complete
    $con->stream_headers_done( $frame_ref->{stream} )
      or return
      if $frame_ref->{flags} & END_HEADERS;

    return $length;
}

sub encode($con, $flags_ref, $stream, $data_ref) {
    my $res = '';

    if ( exists $data_ref->{padding} ) {
        ${$flags_ref} |= PADDED;
        $res .= pack 'C', $data_ref->{padding};
    }

    if ( exists $data_ref->{stream_dep} || exists $data_ref->{weight} ) {
        ${$flags_ref} |= PRIORITY_FLAG;
        my $weight = ( $data_ref->{weight} || DEFAULT_WEIGHT ) - 1;
        my $stream_dep = $data_ref->{stream_dep} || 0;
        $stream_dep |= ( 1 << 31 ) if $data_ref->{exclusive};
        $res .= pack 'NC', $stream_dep, $weight;
    }

    return $res . ${ $data_ref->{hblock} };
}

1;
