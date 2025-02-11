package PageCamel::Helpers::APPQRCode;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.6;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use Image::PNG::QRCode 'qrpng';
use MIME::Base64 qw(encode_base64 encode_base64url);

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = bless \%config, $class;

    if(!defined($self->{scale})) {
        $self->{scale} = 3;
    }

    return $self;
}

sub generate($self, %elements) {
    my @lines = ('PAGECAMEL');
    foreach my $key (sort keys %elements) {
        push @lines, $key . ':' . $elements{$key};
    }
    my $qrtext = join("\n", @lines);

    #print STDERR "QRTEXT:\n", $qrtext, "\n----\n";

    my $imgdata;
    qrpng(text => $qrtext, scale => $self->{scale}, out => \$imgdata);

    return $imgdata;
}


sub generateEmbeddedImage($self, %elements) {
    my $imgdata = $self->generate(%elements);

    my $imagedata = 'data:image/png;base64,' . encode_base64($imgdata, '');

    return $imagedata;
}

1;
