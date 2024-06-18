package PageCamel::Helpers::Colors;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---


use base qw(Exporter);
use GD;
use MIME::Base64;

our @EXPORT_OK = qw(colorHex2RGB colorRGB2Hex colorMaxContrast colorHexMaxContrast colorSwatch colorSwatchB64 colorSwatchUrl colorSwatchHTML);

sub colorHex2RGB($colorstring) {
    
    my @rgb = (0, 0, 0);
    my @hexrgb;

    $colorstring =~ s/^\#//;
    
    if($colorstring =~ /^(\w{2})(\w{2})(\w{2})$/) {
        @hexrgb = ($1, $2, $3);
        for(my $i = 0; $i < 3; $i++) {
            $rgb[$i] = CORE::hex($hexrgb[$i]);
        }
    }
    
    return @rgb;
}

sub colorRGB2Hex($r, $g, $b) {

    return sprintf("#%02lx%02lx%02lx", $r, $g, $b);
}

sub colorMaxContrast($r, $g, $b) {

    my ($newr, $newg, $newb);

    my $avg = ($r + $g + $b) / 3;

    if($avg < 100) {
        # Nearly black, so make the result white
        $newr = 255;
        $newg = 255;
        $newb = 255;
    } elsif($avg > 156) {
        # Nearly white, so make the result black
        $newr = 0;
        $newg = 0;
        $newb = 0;
    } else {
        # Somewhere in the middle. This is bad for color blindness. Try to do our best
        # by contrasting every single channel to black or white
        if($r < 128) {
            $newr = 255;
        } else {
            $newr = 0;
        }
        if($g < 128) {
            $newg = 255;
        } else {
            $newg = 0;
        }
        if($b < 128) {
            $newb = 255;
        } else {
            $newb = 0;
        }
    }

    return ($newr, $newg, $newb);
}

sub colorHexMaxContrast($colorstring) {

    return colorRGB2Hex(colorMaxContrast(colorHex2RGB($colorstring)));
}

my %colorswatchcache;
sub colorSwatch($color) {

    if(defined($colorswatchcache{$color})) {
        return $colorswatchcache{$color};
    }

    my $img = GD::Image->new(50,20);
    my $bg1 = $img->colorAllocate(0,0,0);
    my $bg2 = $img->colorAllocate(255,255,255);
    my $fg = $img->colorAllocate(colorHex2RGB($color));

    $img->filledRectangle(0, 0, 50, 20, $bg1);
    $img->filledRectangle(1, 1, 48, 18, $bg2);
    $img->filledRectangle(2, 2, 47, 17, $fg);

    my $pngdata = $img->png;

    $colorswatchcache{$color} = $pngdata;

    return $pngdata;
}

sub colorSwatchB64($color) {
    return encode_base64(colorSwatch($color), '');
}

sub colorSwatchUrl($color) {
    return 'data:image/png;base64,' . encode_base64(colorSwatch($color), '');
}

sub colorSwatchHTML($color) {
    return '<img width="50" height="20" src="data:image/png;base64,' . encode_base64(colorSwatch($color), '') . '">';
}

1;
__END__
