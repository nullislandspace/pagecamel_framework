package PageCamel::Helpers::Colors;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.3;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---


use base qw(Exporter);

our @EXPORT_OK = qw(colorHex2RGB colorRGB2Hex colorMaxContrast colorHexMaxContrast);

sub colorHex2RGB {
    my ($colorstring) = @_;
    
    my @rgb = (0, 0, 0);
    my @hexrgb;
    
    if($colorstring =~ /\#(\w{2})(\w{2})(\w{2})/) {
        @hexrgb = ($1, $2, $3);
        for(my $i = 0; $i < 3; $i++) {
            $rgb[$i] = CORE::hex($hexrgb[$i]);
        }
    }
    
    return @rgb;
}

sub colorRGB2Hex {
    my ($r, $g, $b) = @_;

    return sprintf("#%02lx%02lx%02lx", $r, $g, $b);
}

sub colorMaxContrast {
    my ($r, $g, $b) = @_;

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

sub colorHexMaxContrast {
    my ($colorstring) = @_;

    return colorRGB2Hex(colorMaxContrast(colorHex2RGB($colorstring)));
}


1;
__END__
