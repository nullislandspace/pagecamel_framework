#!/usr/bin/env perl
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.5;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---


use GD;

convert('testimage.png', 'testimage.bin');
convert('invoice.png', 'invoice.bin');
convert('printertest.png', 'printertest.bin');

exit(0);

sub convert($ifname, $ofname) {
    my $img = GD::Image->new($ifname);
    my ($w, $h) = $img->getBounds();
    #$h = 48;
    #$w = 48;

    open(my $ofh, '>', $ofname);
    local $INPUT_RECORD_SEPARATOR = undef;
    binmode($ofh);

    # Remove line spacing
    print $ofh chr(0x1B), chr(0x33), chr(3), "\n";

    # Make darker
    print $ofh chr(0x1D), chr(0x28), chr(0x4B), chr(0x02), chr(0x00), chr(0x31), chr(127);
    
    # Make faster
    print $ofh chr(0x1D), chr(0x28), chr(0x4B), chr(0x02), chr(0x00), chr(0x32), chr(1);

    # 24 pixel height per line
    if(1) {
        for(my $y = 0; $y < $h; $y += 24) {
            # Command "Send pixel data"
            #my $line = chr(0x1B) . chr(0x2A) .  chr(0x00);
            my $line = chr(0x1B) . chr(0x2A) .  chr(33);

            # Send width definition
            my $leadingwhitespace = 32;
            my $virtualw = $w + $leadingwhitespace;
            $line .= chr($virtualw & 0xff);
            $line .= chr(($virtualw >> 8) & 0xff);

            for(1..($leadingwhitespace*3)) {
                $line .= chr(0x00);
            }

            for(my $x = 0; $x < $w; $x++) {
                for(my $ybyte = 0; $ybyte < 3; $ybyte++) {
                    my $byte = 0;
                    for(my $yoffs = 0; $yoffs < 8; $yoffs++) {
                        $byte <<= 1;
                        if(!$img->getPixel($x, $y + $yoffs + ($ybyte * 8))) {
                            $byte = $byte | 0x01;
                        }
                    }
                    $line .= chr($byte);
                }
            }

            # Line break
            $line .= "\n";

            print $ofh $line;
        }
    }

    # ESC @ for reinit the printer, then new lines, then ESC i   for cutting
    print $ofh chr(0x1B), chr(0x40), "\n", "\n", "\n", "\n", chr(0x1B), chr(0x69), "\n";

    close($ofh);
}

        




