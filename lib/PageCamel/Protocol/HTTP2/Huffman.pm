package PageCamel::Protocol::HTTP2::Huffman;
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
use PageCamel::Protocol::HTTP2::HuffmanCodes;
use PageCamel::Protocol::HTTP2::Trace qw(tracer);
our ( %hcodes, %rhcodes, $hre );
use parent qw(Exporter);
our @EXPORT = qw(huffman_encode huffman_decode);

# Memory unefficient algorithm (well suited for short strings)

sub huffman_encode {
    my $s = shift;
    my $ret = my $bin = '';
    for my $i ( 0 .. length($s) - 1 ) {
        $bin .= $hcodes{ ord( substr $s, $i, 1 ) };
    }
    $bin .= substr( $hcodes{256}, 0, 8 - length($bin) % 8 ) if length($bin) % 8;
    return $ret . pack( 'B*', $bin );
}

sub huffman_decode {
    my $s = shift;
    my $bin = unpack( 'B*', $s );

    my $c = 0;
    $s = pack 'C*', map { $c += length; $rhcodes{$_} } ( $bin =~ /$hre/g );
    tracer->warning(
        sprintf(
            "malformed data in string at position %i, " . " length: %i",
            $c, length($bin)
        )
    ) if length($bin) - $c > 8;
    tracer->warning(
        sprintf "no huffman code 256 at the end of encoded string '%s': %s\n",
        substr( $s,   0, 30 ),
        substr( $bin, $c )
    ) if $hcodes{256} !~ /^@{[ substr($bin, $c) ]}/;
    return $s;
}

1;
