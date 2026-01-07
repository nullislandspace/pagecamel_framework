package PageCamel::Protocol::HTTP2::Frame::Continuation;
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
use PageCamel::Protocol::HTTP2::Constants qw(:flags :errors);
use PageCamel::Protocol::HTTP2::Trace qw(tracer);

sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    my $frame_ref = $con->decode_context->{frame};

    # Protocol errors
    if (
        # CONTINUATION frames MUST be associated with a stream
        $frame_ref->{stream} == 0
      )
    {
        $con->error(PROTOCOL_ERROR);
        return undef;
    }

    $con->stream_header_block( $frame_ref->{stream},
        substr( ${$buf_ref}, $buf_offset, $length ) );

    # Stream header block complete
    $con->stream_headers_done( $frame_ref->{stream} )
      or return undef
      if $frame_ref->{flags} & END_HEADERS;

    return $length;

}

sub encode {
    my ( $con, $flags_ref, $stream, $data_ref ) = @_;
    return ${$data_ref};
}

1;
