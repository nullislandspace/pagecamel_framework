#!/usr/bin/env perl
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



use Image::PNG::QRCode 'qrpng';
use GD;

use PageCamel::Helpers::FileSlurp qw(writeBinFile);

foreach my $line (<DATA>) {
    next if(!defined($line));
    chomp $line;
    next if(!length($line));
    my ($code, $text) = split/\W+/, $line, 2;
    print "Code $code Text $text\n";
    my $qrimg;
    qrpng(text => $code, scale => 50, quiet => 7, out => \$qrimg);

    my $img = GD::Image->new($qrimg);

    my $black = $img->colorAllocate(0, 0, 0);
    my $fontname = '/home/cavac/src/pagecamel_er_base/fonts/intel/IntelOneMono-Medium.ttf';
        $img->stringFT($black, $fontname, 60, 0, 60, 140, $text);

    my $outdata = $img->png();

    my $fname = $code . '.png';
    writeBinFile($fname, $outdata);
}


__DATA__
42302919 Normal
23232323 Freipreis
12345678 Einzelartikel
98765432 Einzelartikel Freipreis

