package PageCamel::Helpers::PrintProcessor;
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


use GD;
use GD::Text;
use PageCamel::Helpers::FileSlurp qw(writeBinFile);
use PageCamel::Helpers::DataBlobs;
use PageCamel::Helpers::TestData;
use Crypt::Digest::SHA256 qw[sha256_hex];
use MIME::Base64 qw(encode_base64 decode_base64);
use Net::CUPS2;

my %globalimagecache;

sub new($proto, $config) {
    my $class = ref($proto) || $proto;
    
    my $self = bless $config, $class;

    $self->{imagecache} = \%globalimagecache; # Cache works over multiple instances

    if(!defined($self->{reph})) {
        croak('PageCamel::Helpers::PrintProcessor needs reph');
    }

    if(!defined($self->{dbh})) {
        croak('PageCamel::Helpers::PrintProcessor needs dbh');
    }

    if(!defined($self->{generateEscPos})) {
        $self->{generateEscPos} = 0;
    }

    if(!defined($self->{printerType})) {
        $self->{printerType} = 'SGT116';
    }

    if(!defined($self->{escPosSpeed})) {
        $self->{escPosSpeed} = 1; ; # 1-9 or 1-12 depending on model
    }

    if(!defined($self->{escPosDensity})) {
        $self->{escPosDensity} = 1; # Darkness 1-13 or 0-15, depending on model
    }

    { # Make sure we have a cache table for more persistant caching
        my $dbh = $self->{dbh};
        my $reph = $self->{reph};
        my $type = $dbh->getColumnType('pagecamel.printerimagecache', 'imagekey');
        if(!defined($type)) {
            $reph->debuglog("Creating printer image cache");
            my $stmt = "CREATE TABLE pagecamel.printerimagecache (
                            imagekey text NOT NULL,
                            imagedata text NOT NULL,
                            CONSTRAINT printerimagecache_pk PRIMARY KEY (imagekey)
                        )";
            if(!$dbh->do($stmt)) {
                croak($dbh->errstr);
            }
            $dbh->commit;
        } elsif($type ne 'text') {
            croak("pagecamel.printerimagecache column imagekey has wrong type. Should be 'text' but is $type");
        }
    }

    return $self;
}

sub printStartDocument($self) {
    
    $self->{img} = GD::Image->new($self->{width}, $self->{height});
    $self->{imgoffs} = 0;
    $self->{imgwhite} = $self->{img}->colorAllocate(255, 255, 255);
    $self->{imgblack} = $self->{img}->colorAllocate(0, 0, 0);
    $self->{imgred} = $self->{img}->colorAllocate(255, 0, 0);

    $self->{printcolor} = 'imgblack';
    
    $self->{img}->filledRectangle(0, 0, $self->{width}, $self->{height}, $self->{imgwhite});

    $self->{kickCashdrawer} = 0;
    
    return;
}

sub printEndDocument($self) {
    my $reph = $self->{reph};
    
    # Need to downsize image to minimum required length
    my $cropped = GD::Image->new($self->{width}, $self->{imgoffs});
    my $white = $cropped->colorAllocate(255, 255, 255);
    my $black = $cropped->colorAllocate(0, 0, 0);
    my $red = $cropped->colorAllocate(255, 0, 0);
    
    $cropped->copyResized($self->{img},
                          0, 0, # DEST X Y
                          0, 0, # SRC X Y
                          $self->{width}, $self->{imgoffs}, # DEST W H
                          $self->{width}, $self->{imgoffs}, # SRC W H
                          );
    
    $self->{imagedata} = $cropped->png;
    $self->{img} = $cropped;

    return;
}

sub printKickCashdrawer($self, $kick = 1) {
    # This currently only works in EscPos mode
    $self->{kickCashdrawer} = $kick;

    return;
}

sub _generateEscPos($self, $img = undef) {
    my $reph = $self->{reph};
    $reph->debuglog("Converting image to ESC/POS");

    if(defined($img)) {
        $self->{img} = $img;
    }

    if(!defined($self->{imgwhite})) {
        $self->{imgwhite} = 0;
    }

    if(!defined($self->{printerExtraFeed})) {
        $self->{printerExtraFeed} = 0;
    }

    if($self->{printerType} eq 'TMT88') {
        $reph->debuglog("    Type: TMT88");
        return $self->_escpos_tmt88($self->{printerExtraFeed});
    } elsif($self->{printerType} eq 'TMP20') {
        $reph->debuglog("    Type: TMP20");
        return $self->_escpos_tmp20($self->{printerExtraFeed});
    } elsif($self->{printerType} eq 'CTS801') {
        $reph->debuglog("    Type: CTS801");
        return $self->_escpos_cts801($self->{printerExtraFeed});
    } elsif($self->{printerType} eq 'SGT116') {
        $reph->debuglog("    Type: SGT116");
        return $self->_escpos_sgt116($self->{printerExtraFeed});
    } elsif($self->{printerType} eq 'JWS360') {
        $reph->debuglog("    Type: JWS360");
        return $self->_escpos_jws360($self->{printerExtraFeed});
    }

    $reph->debuglog("   UNSUPPORTED PRINTER TYPE, TRYING TMT88 compatible");
    return $self->_escpos_tmt88();
}
    

sub _escpos_tmt88($self, $extrafeed) {
    my $reph = $self->{reph};

    my $raw = '';
    my $img = $self->{img};


    # Reset printer
    $raw .= chr(0x1B) . chr(0x40);

    if($self->{kickCashdrawer}) {
        # Kick drawer 1
        $raw .= chr(0x1B) . chr(0x70) . chr(0x00) . chr(0xFE) . chr(0xFE); # . "\n";
        
        # Kick drawer 2
        $raw .= chr(0x1B) . chr(0x70) . chr(0x01) . chr(0xFE) . chr(0xFE); # . "\n";
    }


    # Remove line spacing
    $raw .=  "\n" . chr(0x1B) . chr(0x33) . chr(0) . "\n";

    # Make darker
    # GS ( K 
    my $densityrangeepson = 255 - int($self->{escPosDensity} * (250 / 15));
    $raw .= chr(0x1D) . chr(0x28) . chr(0x4B) . chr(0x02) . chr(0x00) . chr(0x31) . chr($densityrangeepson);

    # Make faster
    $raw .= chr(0x1D) . chr(0x28) . chr(0x4B) . chr(0x02) . chr(0x00) . chr(0x32) . chr($self->{escPosSpeed});
    
    my ($w, $h) = $img->getBounds();

    # Print bitmap image
    #print "\nTotal: $w x $h\n";

    my $blocksize = 1000;
   
    # Image data

    my $bytew = $w / 8;

    for(my $blockoffs = 0; $blockoffs < $h; $blockoffs += $blocksize) {
        my $blockh = $h - $blockoffs;
        if($blockh > $blocksize) {
            $blockh = $blocksize;
        }
        #print "Block: $w x $blockh\n";
        #           GS          v           0       m         xL                xH                    yL                yH
        $raw .= chr(0x1D) . chr(0x76) . chr(0x30) . chr(0) . chr($bytew & 0xff) . chr(($bytew >> 8) & 0xff) . chr($blockh & 0xff) . chr(($blockh >> 8) & 0xff); 

        for(my $y = 0; $y < $blockh; $y++) {
            for(my $x = 0; $x < $w; $x+=8) {
                my $byte = 0;
                for(my $xoffs = 0; $xoffs < 8; $xoffs++) {
                    my $xtotal = $x + $xoffs;
                    $byte <<= 1;
                    if($xtotal < $w && $img->getPixel($xtotal, $y + $blockoffs) != $self->{imgwhite}) {
                        $byte = $byte | 0x01;
                    }
                }
                $raw .= chr($byte);
            }
        }
        #$raw .= "\n";
    }


    # Feed and half-cut
    $raw .= chr(0x1D) . chr(0x56) . chr(0x42) . chr(0x00);

    if($extrafeed) {
        # Feed 5 empty lines after half-cut to prevent paper jam on older/worn out printers
        for(1..5) {
            $raw .= " \n";
        }
    }

    $self->{escposimagedata} = $raw;

    return;
}

sub _escpos_tmp20($self, $extrafeed) {
    my $reph = $self->{reph};

    my $raw = '';
    my $img;

    # Bluetooth belt printer
    # This is largely compatible to the Epson TM-T88 models. Of course, it doesn't have a cash drawer and it only has 384 pixels width, so we need to downscale the image
    
    {
        my ($w, $h) = $self->{img}->getBounds();
        my $destw = 384;
        my $scale = $w / $destw;
        my $desth = int($h / $scale);
        print STDERR "Scale $scale H $desth\n";
        #croak("BLA");

        $img = GD::Image->new($destw, $desth);
        $img->colorAllocate(255, 255, 255);
        $img->colorAllocate(0, 0, 0);
        $img->colorAllocate(255, 0, 0);

        $img->copyResized($self->{img},
                              0, 0, # DEST X Y
                              0, 0, # SRC X Y
                              $destw, $desth, # DEST W H
                              $w, $h, # SRC W H
                              );
    }

    # Reset printer
    $raw .= chr(0x1B) . chr(0x40);

    # Remove line spacing
    $raw .=  "\n" . chr(0x1B) . chr(0x33) . chr(0) . "\n";

    # Make darker
    # GS ( K 
    my $densityrangeepson = 255 - int($self->{escPosDensity} * (250 / 15));
    $raw .= chr(0x1D) . chr(0x28) . chr(0x4B) . chr(0x02) . chr(0x00) . chr(0x31) . chr($densityrangeepson);

    # Make faster
    $raw .= chr(0x1D) . chr(0x28) . chr(0x4B) . chr(0x02) . chr(0x00) . chr(0x32) . chr($self->{escPosSpeed});
    
    my ($w, $h) = $img->getBounds();

    # Print bitmap image
    #print "\nTotal: $w x $h\n";

    my $blocksize = 1000;
   
    # Image data

    my $bytew = $w / 8;

    for(my $blockoffs = 0; $blockoffs < $h; $blockoffs += $blocksize) {
        my $blockh = $h - $blockoffs;
        if($blockh > $blocksize) {
            $blockh = $blocksize;
        }
        #print "Block: $w x $blockh\n";
        #           GS          v           0       m         xL                xH                    yL                yH
        $raw .= chr(0x1D) . chr(0x76) . chr(0x30) . chr(0) . chr($bytew & 0xff) . chr(($bytew >> 8) & 0xff) . chr($blockh & 0xff) . chr(($blockh >> 8) & 0xff); 

        for(my $y = 0; $y < $blockh; $y++) {
            for(my $x = 0; $x < $w; $x+=8) {
                my $byte = 0;
                for(my $xoffs = 0; $xoffs < 8; $xoffs++) {
                    my $xtotal = $x + $xoffs;
                    $byte <<= 1;
                    if($xtotal < $w && $img->getPixel($xtotal, $y + $blockoffs) != $self->{imgwhite}) {
                        $byte = $byte | 0x01;
                    }
                }
                $raw .= chr($byte);
            }
        }
        #$raw .= "\n";
    }


    # Feed and half-cut
    $raw .= chr(0x1D) . chr(0x56) . chr(0x42) . chr(0x00);

    if($extrafeed) {
        # Feed 5 empty lines after half-cut to prevent paper jam on older/worn out printers
        for(1..5) {
            $raw .= " \n";
        }
    }

    $self->{escposimagedata} = $raw;

    return;
}


sub _escpos_cts801($self, $extrafeed) {
    my $reph = $self->{reph};

    # Citizen CTS801 is *mostly* compatible with Epson TM-T88V but has a wider print head that print right to (and sometimes over) the edge of the paper.
    # Fortunately, the resolution (DPI) is the same, there are just more pixels left and right.
    # For this printer, we just add a few blank spaces at the start of each line.
    my $blankspaces = 8;

    my $raw = '';
    my $img = $self->{img};

    # Reset printer
    $raw .= chr(0x1B) . chr(0x40);

    if($self->{kickCashdrawer}) {
        # Kick drawer 1
        $raw .= chr(0x1B) . chr(0x70) . chr(0x00) . chr(0xFE) . chr(0xFE); # . "\n";
        
        # Kick drawer 2
        $raw .= chr(0x1B) . chr(0x70) . chr(0x01) . chr(0xFE) . chr(0xFE); # . "\n";
    }


    # Remove line spacing
    $raw .=  "\n" . chr(0x1B) . chr(0x33) . chr(0) . "\n";

    # Make darker
    # GS ( K 
    my $densityrangeepson = 255 - int($self->{escPosDensity} * (250 / 15));
    $raw .= chr(0x1D) . chr(0x28) . chr(0x4B) . chr(0x02) . chr(0x00) . chr(0x31) . chr($densityrangeepson);

    # Make faster
    $raw .= chr(0x1D) . chr(0x28) . chr(0x4B) . chr(0x02) . chr(0x00) . chr(0x32) . chr($self->{escPosSpeed});
    
    my ($w, $h) = $img->getBounds();


    # Print bitmap image
    #print "\nTotal: $w x $h\n";

    my $blocksize = 1000;
   
    # Image data

    my $bytew = ($w / 8) + $blankspaces;

    for(my $blockoffs = 0; $blockoffs < $h; $blockoffs += $blocksize) {
        my $blockh = $h - $blockoffs;
        if($blockh > $blocksize) {
            $blockh = $blocksize;
        }
        #print "Block: $w x $blockh\n";
        #           GS          v           0       m         xL                xH                    yL                yH
        $raw .= chr(0x1D) . chr(0x76) . chr(0x30) . chr(0) . chr($bytew & 0xff) . chr(($bytew >> 8) & 0xff) . chr($blockh & 0xff) . chr(($blockh >> 8) & 0xff); 

        for(my $y = 0; $y < $blockh; $y++) {
            for(my $i = 0; $i < $blankspaces; $i++) {
                $raw .= chr(0x00);
            }
            for(my $x = 0; $x < $w; $x+=8) {
                my $byte = 0;
                for(my $xoffs = 0; $xoffs < 8; $xoffs++) {
                    my $xtotal = $x + $xoffs;
                    $byte <<= 1;
                    if($xtotal < $w && $img->getPixel($xtotal, $y + $blockoffs) != $self->{imgwhite}) {
                        $byte = $byte | 0x01;
                    }
                }
                $raw .= chr($byte);
            }
        }
        #$raw .= "\n";
    }


    # Feed and half-cut
    $raw .= chr(0x1D) . chr(0x56) . chr(0x42) . chr(0x00);

    if($extrafeed) {
        # Feed 5 empty lines after half-cut to prevent paper jam on older/worn out printers
        for(1..5) {
            $raw .= " \n";
        }
    }

    $self->{escposimagedata} = $raw;

    return;
}

sub _escpos_sgt116($self, $extrafeed) {

    my $raw = '';
    my $img = $self->{img};

    # Reset printer
    #$raw .= chr(0x1B) . chr(0x40);

    # Chinesium version of ESC/POS for SGT116
    $raw .= chr(0x12) . chr(0x23) . chr($self->{escPosDensity});
    # Doesn't seem to have a configurable speed that actually works


    # Kick drawer
    if($self->{kickCashdrawer}) {
        #$raw .= chr(0x1b) . chr(0x70) . chr(0x00);
        $raw .= chr(0x1B) . chr(0x70) . chr(0x00) . chr(0xFE) . chr(0xFE); # . "\n";
    }

    my ($w, $h) = $img->getBounds();

    # Remove line spacing
    $raw .=  chr(0x1B) . chr(0x33) . chr(3) . "\n";

    # 24 pixel height per line
    for(my $y = 0; $y < $h; $y += 24) {
        # Command "Send pixel data"
        $raw .= chr(0x1B) . chr(0x2A) .  chr(33);

        # Send width definition
        my $leadingwhitespace = 32;
        my $virtualw = $w + $leadingwhitespace;
        $raw .= chr($virtualw & 0xff);
        $raw .= chr(($virtualw >> 8) & 0xff);

        for(1..($leadingwhitespace*3)) {
            $raw .= chr(0x00);
        }

        for(my $x = 0; $x < $w; $x++) {
            for(my $ybyte = 0; $ybyte < 3; $ybyte++) {
                my $byte = 0;
                for(my $yoffs = 0; $yoffs < 8; $yoffs++) {
                    my $ytotal = $y + $yoffs + ($ybyte * 8);
                    $byte <<= 1;
                    if($ytotal < $h && $img->getPixel($x, $ytotal) != $self->{imgwhite}) {
                        $byte = $byte | 0x01;
                    }
                }
                $raw .= chr($byte);
            }
        }

        # Line break
        $raw .= "\n";
    }

    # Feed and half-cut
    $raw .= chr(0x1D) . chr(0x56) . chr(0x42) . chr(0x00);

    if($extrafeed) {
        # Feed 5 empty lines after half-cut to prevent paper jam on older/worn out printers
        for(1..5) {
            $raw .= " \n";
        }
    }

    $self->{escposimagedata} = $raw;

    return;
}

sub _escpos_jws360($self, $extrafeed) {
    my $raw = '';
    my $img = $self->{img};

    # Reset printer
    $raw .= chr(0x1B) . chr(0x40);

    # Chinesium version of ESC/POS for SGT116
    #$raw .= chr(0x12) . chr(0x23) . chr($self->{escPosDensity});
    # Doesn't seem to have a configurable speed that actually works

    $raw .= "\n";

    # Kick drawer
    if($self->{kickCashdrawer}) {
        $raw .= chr(0x1B) . chr(0x70) . chr(0x00) . chr(0xFE) . chr(0xFE); # . "\n";
    }
    $raw .= "\n";

    my ($w, $h) = $img->getBounds();

    # Remove line spacing
    $raw .=  chr(0x1B) . chr(0x33) . chr(3) . "\n";

    # 24 pixel height per line
    for(my $y = 0; $y < $h; $y += 24) {
        # Command "Send pixel data"
        $raw .= chr(0x1B) . chr(0x2A) .  chr(33);

        # Send width definition
        my $leadingwhitespace = 32;
        my $virtualw = $w + $leadingwhitespace;
        $raw .= chr($virtualw & 0xff);
        $raw .= chr(($virtualw >> 8) & 0xff);

        for(1..($leadingwhitespace*3)) {
            $raw .= chr(0x00);
        }

        for(my $x = 0; $x < $w; $x++) {
            for(my $ybyte = 0; $ybyte < 3; $ybyte++) {
                my $byte = 0;
                for(my $yoffs = 0; $yoffs < 8; $yoffs++) {
                    my $ytotal = $y + $yoffs + ($ybyte * 8);
                    $byte <<= 1;
                    if($ytotal < $h && $img->getPixel($x, $ytotal) != $self->{imgwhite}) {
                        $byte = $byte | 0x01;
                    }
                }
                $raw .= chr($byte);
            }
        }

        # Line break
        $raw .= "\n";
    }

    # Feed and half-cut
    $raw .= chr(0x1D) . chr(0x56) . chr(0x42) . chr(0x00);
    #$raw .= "\n";

    if($extrafeed) {
        # Feed 5 empty lines after half-cut to prevent paper jam on older/worn out printers
        for(1..5) {
            $raw .= " \n";
        }
    }

    $self->{escposimagedata} = $raw;

    return;
}

sub printSendToPrinter($self, $cupsprinters = []) {
    my $reph = $self->{reph};
    
    #my $ofname = $self->makeFName();

    if($self->{generateEscPos}) {
        $self->_generateEscPos();
        #writeBinFile($ofname, $self->{escposimagedata});
        #writeBinFile('/home/cavac/lastprint.dat', $self->{escposimagedata});
        return $self->_printFile($self->{escposimagedata}, '0.0.0.0', $cupsprinters);
    } else {
        return $self->_printFile($self->{imagedata}, '0.0.0.0', $cupsprinters);
    }
}

sub printerOpenCashdrawer($self, $cupsprinters = []) {
    my $reph = $self->{reph};

    if(!$self->{generateEscPos}) {
        # FIXME not implemented yet for non ESC/POS printers
        return;
    }

    my $raw = '';
    if($self->{printerType} eq 'TMT88') {
        $reph->debuglog("    Type: TMT88");

        # Kick drawer 1
        $raw .= chr(0x1B) . chr(0x70) . chr(0x00) . chr(0xFE) . chr(0xFE); # . "\n";
        # Kick drawer 2
        $raw .= chr(0x1B) . chr(0x70) . chr(0x01) . chr(0xFE) . chr(0xFE); # . "\n";
    } elsif($self->{printerType} eq 'CTS801') {
        $reph->debuglog("    Type: CTS801");
        # Kick drawer 1
        $raw .= chr(0x1B) . chr(0x70) . chr(0x00) . chr(0xFE) . chr(0xFE); # . "\n";
        # Kick drawer 2
        $raw .= chr(0x1B) . chr(0x70) . chr(0x01) . chr(0xFE) . chr(0xFE); # . "\n";
    } elsif($self->{printerType} eq 'SGT116') {
        $reph->debuglog("    Type: SGT116");
        $raw .= chr(0x1b) . chr(0x70) . chr(0x00);
    } elsif($self->{printerType} eq 'JWS360') {
        $reph->debuglog("    Type: JWS360");
        $raw .= chr(0x1B) . chr(0x70) . chr(0x00) . chr(0xFE) . chr(0xFE); # . "\n";
    } else {
        # Cash drawer not supported on this printer
        return;
    }
    return $raw;
}

sub _printFile($self, $raw, $cupsip, $cupsprinters = []) {
    my $reph = $self->{reph};

    my $ispdf = 0;
    if(substr($raw, 0, 4) eq '%PDF') {
        $ispdf = 1;
    }

    my $ofname = $self->makeFName($ispdf);
    writeBinFile($ofname, $raw);

    if(ref $cupsprinters ne 'ARRAY') {
        my @tmp;
        if(!defined($cupsprinters) || $cupsprinters eq '') {
            $reph->debuglog("No printer name given!!!!!!");
            if(!defined($self->{defaultprinter})) {
                $reph->debuglog("...and no default printer set!!!!");
            } else {
                push @tmp, $self->{defaultprinter};
            }
        } else {
            push @tmp, $cupsprinters . '';
        }

        $cupsprinters = \@tmp;
    }

    if($cupsip eq '0.0.0.0') {
        if(defined($ENV{PC_CUPS_SERVER}) && $ENV{PC_CUPS_SERVER} ne '') {
            $cupsip = $ENV{PC_CUPS_SERVER};
        } else {
            $cupsip = '127.0.0.1';
        }
    }

    $reph->debuglog("Selecting CUPS IP ", $cupsip);


    my $cups = Net::CUPS2->new();
    $cups->setServer($cupsip);

    foreach my $printername (@{$cupsprinters}) {
        if($self->{printcommand} =~ /^\/bin\/true/) {
            $reph->debuglog("Print command disabled");
            next;
        }
        my @availprinters = $cups->getDestinations();
        foreach my $availprinter (@availprinters) {
            #$reph->debuglog('   Available: ', $availprinter->getName(), " / ", $availprinter->getDescription());
        }
        my $printer = $cups->getDestination($printername);
        if(!defined($printer)) {
            $reph->debuglog("Printer ", $printername, " not found in CUPS server ", $cupsip);
            next;
        }
        $reph->debuglog("Printing to CUPS server at ", $cupsip , " on printer ", $printername);
        $printer->printFile($ofname, "PAGECAMEL PRINT SERVICE $VERSION");

        #my $cmd = $self->{printcommand} . ' -P ' . $printername . ' ' . $ofname;
        #$reph->debuglog("Running 'open cashdrawer' printer command: $cmd");
        #`$cmd`;
    }
    
    unlink $ofname;

    return $raw;
}

sub printGetImagedata($self) {
    return $self->{imagedata};
}


sub printMoveOffset($self, $offset) {
    $self->{imgoffs} += $offset;
}

sub printSetColorRed($self, $val) {
    if($val) {
        $self->{printcolor} = 'imgred';
    } else {
        $self->{printcolor} = 'imgblack';
    }
}

sub _getPrintColor($self, $isfont = 0) {
    if($isfont && $self->{$self->{printcolor}} > 0) {
        # return the NEGATIVE number of the print color, this disables Font Aliasing
        return -1 * $self->{$self->{printcolor}};
    }
    return  $self->{$self->{printcolor}};
}

sub printAddTextLine($self, $line, $y = undef) {
    
    chomp $line;
    
    $line = encode_utf8($line);
    my $oldoffs = $self->{imgoffs};
    if(!defined($y)) {
        $self->{img}->stringFT($self->_getPrintColor(1), $self->{font}, 20, 0, 10, $self->{imgoffs} + 10, $line);
        
        $self->{imgoffs} += 27;
    } else {
        $self->{img}->stringFT($self->_getPrintColor(1), $self->{font}, 20, 0, 10, $y + 10, $line);
        $oldoffs = $y;
    }
    
    return $oldoffs;
}

sub printAddBoldTextLine($self, $line, $y = undef) {
    
    chomp $line;
    
    $line = encode_utf8($line);
    my $oldoffs = $self->{imgoffs};
    if(!defined($y)) {
        $self->{img}->stringFT($self->_getPrintColor(1), $self->{boldfont}, 20, 0, 10, $self->{imgoffs} + 10, $line);
        
        $self->{imgoffs} += 24;
    } else {
        $self->{img}->stringFT($self->_getPrintColor(1), $self->{boldfont}, 20, 0, 10, $y + 10, $line);
        $oldoffs = $y;
    }
    
    return $oldoffs;
}

sub printAddSmallTextLine($self, $line, $x = undef, $y = undef) {
    
    chomp $line;
    
    if(defined($x) && defined($y)) {
        $self->{img}->stringFT($self->_getPrintColor(1), $self->{smallfont}, 15, 0, $x, $y + 8, $line);
    } else {
        $self->{img}->stringFT($self->_getPrintColor(1), $self->{smallfont}, 15, 0, 10, $self->{imgoffs} + 8, $line);
        $self->{imgoffs} += 19;
    }
    
    return;
}

sub printAddBoldSmallTextLine($self, $line, $x = undef, $y = undef) {
    
    chomp $line;
    
    if(defined($x) && defined($y)) {
        $self->{img}->stringFT($self->_getPrintColor(1), $self->{boldfont}, 15, 0, $x, $y + 8, $line);
    } else {
        $self->{img}->stringFT($self->_getPrintColor(1), $self->{boldfont}, 15, 0, 10, $self->{imgoffs} + 8, $line);
        $self->{imgoffs} += 19;
    }
    
    return;
}


sub printAddSemiSmallTextLine($self, $line, $x = undef, $y = undef) {
    
    chomp $line;
    
    if(defined($x) && defined($y)) {
        $self->{img}->stringFT($self->_getPrintColor(1), $self->{smallfont}, 18, 0, $x, $y + 8, $line);
    } else {
        $self->{img}->stringFT($self->_getPrintColor(1), $self->{smallfont}, 18, 0, 10, $self->{imgoffs} + 8, $line);
        $self->{imgoffs} += 22;
    }
    
    return;
}

sub printAddBoldSemiSmallTextLine($self, $line, $x = undef, $y = undef) {
    
    chomp $line;
    
    if(defined($x) && defined($y)) {
        $self->{img}->stringFT($self->_getPrintColor(1), $self->{boldfont}, 18, 0, $x, $y + 8, $line);
    } else {
        $self->{img}->stringFT($self->_getPrintColor(1), $self->{boldfont}, 18, 0, 10, $self->{imgoffs} + 8, $line);
        $self->{imgoffs} += 22;
    }
    
    return;
}

sub printAddBigTextLine($self, $line) {
    
    chomp $line;
    
    $self->{img}->stringFT($self->_getPrintColor(1), $self->{bigfont}, 50, 0, 10, $self->{imgoffs} + 50, $line);
    
    $self->{imgoffs} += 58;
    
    return;
}

sub printAddMediumBigTextLine($self, $line) {
    
    chomp $line;
    
    $self->{img}->stringFT($self->_getPrintColor(1), $self->{bigfont}, 30, 0, 10, $self->{imgoffs} + 30, $line);
    
    $self->{imgoffs} += 38;
    
    return;
}

sub printAddSingleLine($self) {
    $self->{img}->filledRectangle(0, $self->{imgoffs} + 5, $self->{width},
                                      $self->{imgoffs} + 1 + 5,
                                      $self->_getPrintColor());
    $self->{imgoffs} += 24;

    return;
}

sub printAddDoubleLine($self) {
    $self->{img}->filledRectangle(0, $self->{imgoffs} + 5, $self->{width},
                                      $self->{imgoffs} + 1 + 5,
                                      $self->_getPrintColor());
    $self->{img}->filledRectangle(0, $self->{imgoffs} + 12, $self->{width},
                                      $self->{imgoffs} + 1 + 12,
                                      $self->_getPrintColor());
    $self->{imgoffs} += 24;

    return;
}

sub printAddDottedLine($self) {
    for(my $i = 0; $i < $self->{width}; $i += 6) {
        $self->{img}->filledRectangle($i, $self->{imgoffs} + 5, $i + 3,
                                          $self->{imgoffs} + 1 + 5,
                                          $self->_getPrintColor());
    }
    $self->{imgoffs} += 24;

    return;
}

sub printAddImage($self, $filename, $isbindata = false, $imagesoftness = 1, $doscale = true, $center = false) {
    
    my $reph = $self->{reph};
    
    my $pic;
    
    if($isbindata) {
        $pic = GD::Image->newFromPngData($filename, 0);
    } else {
        $pic = GD::Image->newFromPng($filename, 0);
    }
    
    if($pic->colorsTotal != 2) {
        $reph->debuglog("printAddImage detected an image with >2 index colors!");
        $reph->debuglog("Switching to (slower) printAddGreyscaleImage() processing");
        return $self->printAddGreyscaleImage($filename, $isbindata, $imagesoftness);
    }
    $reph->debuglog("printAddImage detected an image with exactly 2 colors!");
    
    my ($w, $h) = $pic->getBounds();
    
    my $destw = $self->{width};
    my $scale = $w / $destw;
    my $desth = int($h / $scale);

    if(!$doscale) {
        $destw = $w;
        $desth = $h;
    }

    my $centeroffs = 0;
    if($center) {
        $centeroffs = int(($self->{width} - $destw) / 2);
    }

    
    $self->{img}->copyResized($pic,
                              $centeroffs, $self->{imgoffs}, # DEST X Y
                              0, 0, # SRC X Y
                              $destw, $desth, # DEST W H
                              $w, $h, # SRC W H
                              );
    
    my $oldimgoffs = $self->{imgoffs};
    $self->{imgoffs} += 10 + $desth;
    
    return $oldimgoffs;
}

sub printAddGreyscaleImage($self, $filename, $isbindata, $imagesoftness = 1) {
    
    my $reph = $self->{reph};
    
    my $rawpic;
    if($isbindata) {
        $rawpic = GD::Image->newFromPngData($filename, 0);
    } else {
        $rawpic = GD::Image->newFromPng($filename, 0);
    }
            
    my ($w, $h) = $rawpic->getBounds();
    
    my $destw = $self->{width};
    my $scale = $w / $destw;
    my $desth = int($h / $scale);
    
    
    # Check if we got that image already cached
    my $cachekey = $imagesoftness . '_' . sha256_hex($rawpic->png);
    $reph->debuglog("   KEY $cachekey");

    if(!defined($self->{imagecache}->{$cachekey})) {
        # We don't have it in RAM, let's try our secondary cache in the database
        my $data = $self->loadDBCache($cachekey);
        if(defined($data)) {
            $reph->debuglog("       loaded from database");
            $self->{imagecache}->{$cachekey} = GD::Image->newFromPngData($data, 0);
        }
    }

    if(defined($self->{imagecache}->{$cachekey})) {
        $reph->debuglog("   using cached greyscale image conversion");
        $self->{img}->copyResized($self->{imagecache}->{$cachekey},
                          0, $self->{imgoffs}, # DEST X Y
                          0, 0, # SRC X Y
                          $destw, $desth, # DEST W H
                          $destw, $desth, # SRC W H
                          );
        $self->{imgoffs} += $desth;
        return;
    }

    $reph->debuglog("   need to do image conversion");
    
    my $pic = GD::Image->new($destw, $desth);
    
    # Copy palette
    my $colorcount = $rawpic->colorsTotal;
    for(my $c = 0; $c < $colorcount; $c++) {
        my ($r,$g,$b) = $rawpic->rgb($c);
        $pic->colorAllocate($r, $g, $b);
    }
    
    $pic->copyResized($rawpic,
                      0, 0, # DEST X Y
                      0, 0, # SRC X Y
                      $destw, $desth, # DEST W H
                      $w, $h, # SRC W H
                    );
    
    # For caching converted images
    my $cachepic = GD::Image->new($destw, $desth);
    my $cachewhite = $cachepic->colorAllocate(255, 255, 255);
    my $cacheblack = $cachepic->colorAllocate(0, 0, 0);
    my $cachered = $cachepic->colorAllocate(255, 0, 0);

    my @pixels;
    # Prepare for dithering
    for(my $y = 0; $y < $desth; $y++) {
        for(my $x = 0; $x < $destw; $x++) {
            my $index = $pic->getPixel($x, $y);
            my ($r,$g,$b) = $pic->rgb($index);
            my $greypixel = int(($r+$g+$b)/3);
            my $oldpixel = $greypixel * 1.0;

            $pixels[$x]->[$y] = $oldpixel;
        }
    }
    
    if($imagesoftness == 0) {
        for(my $y = 0; $y < $desth; $y++) {
            for(my $x = 0; $x < $destw; $x++) {
                my $oldpixel = $pixels[$x]->[$y];
    
                # Simple monochrome conversion
                if($oldpixel < 128) {
                    $self->{img}->setPixel($x, $y + $self->{imgoffs}, $self->_getPrintColor());
                    $cachepic->setPixel($x, $y, $cacheblack);
                }
            }
        }
        $self->{imagecache}->{$cachekey} = $cachepic;
        $self->saveDBCache($cachekey, $cachepic->png);
    } elsif($imagesoftness == 2) {
        # Floyd-Steinberg dithering
        my @dither = (
            [0, 0, 7],
            [3, 5, 1],
        );
        for(my $y = 0; $y < $desth; $y++) {
            for(my $x = 0; $x < $destw; $x++) {
                my $oldpixel = $pixels[$x]->[$y];
    
                # "Find closed palette/index value
                my $newpixel = 255.0;
                if($oldpixel < 128) {
                    $newpixel = 0.0;
                }
                $pixels[$x]->[$y] = $newpixel;
    
                my $quanterror = $oldpixel - $newpixel;
                for(my $ditherx = 0; $ditherx < 3; $ditherx++) {
                    for(my $dithery = 0; $dithery < 2; $dithery++) {
                        my $deltax = $x + $ditherx - 1;
                        my $deltay = $y + $dithery;
                        my $factor = $dither[$dithery]->[$ditherx];
                        next unless($factor);
                        next if($deltax < 0 || $deltax >= $destw);
                        next if($deltay < 0 || $deltay >= $desth);
                        my $change = $factor * $quanterror / 16.0;
    
                        #print "## $oldpixel $newpixel $factor $quanterror $change\n";
                        $pixels[$deltax]->[$deltay] += $change;
                    }
                }
            }
        }
    
        for(my $y = 0; $y < $desth; $y++) {
            for(my $x = 0; $x < $destw; $x++) {    
                if($pixels[$x]->[$y] < 128) {
                    #print "$x $y ", $pixels[$x]->[$y], "\n";
                    $self->{img}->setPixel($x, $y + $self->{imgoffs}, $self->_getPrintColor());
                    $cachepic->setPixel($x, $y, $cacheblack);
                }
            }
        }
        
        $self->{imagecache}->{$cachekey} = $cachepic;
        $self->saveDBCache($cachekey, $cachepic->png);
    } elsif($imagesoftness == 1) {

        # Dithering  https://en.wikipedia.org/wiki/Error_diffusion#minimized_average_error
        my @dither = (
            [0, 0, 0, 7, 5],
            [3, 5, 7, 5, 3],
            [1, 3, 5, 3, 1],
        );
        for(my $y = 0; $y < $desth; $y++) {
            for(my $x = 0; $x < $destw; $x++) {
                my $oldpixel = $pixels[$x]->[$y];
    
                # "Find closed palette/index value
                my $newpixel = 255.0;
                if($oldpixel < 128) {
                    $newpixel = 0.0;
                }
                $pixels[$x]->[$y] = $newpixel;
    
                my $quanterror = $oldpixel - $newpixel;
                for(my $ditherx = 0; $ditherx < 5; $ditherx++) {
                    for(my $dithery = 0; $dithery < 3; $dithery++) {
                        my $deltax = $x + $ditherx - 2;
                        my $deltay = $y + $dithery - 1;
                        my $factor = $dither[$dithery]->[$ditherx];
                        next unless($factor);
                        next if($deltax < 0 || $deltax >= $destw);
                        next if($deltay < 0 || $deltay >= $desth);
                        my $change = $factor * $quanterror / 48.0;
    
                        #print "## $oldpixel $newpixel $factor $quanterror $change\n";
                        $pixels[$deltax]->[$deltay] += $change;
                    }
                }
            }
        }
    
        for(my $y = 0; $y < $desth; $y++) {
            for(my $x = 0; $x < $destw; $x++) {    
                if($pixels[$x]->[$y] < 128) {
                    #print "$x $y ", $pixels[$x]->[$y], "\n";
                    $self->{img}->setPixel($x, $y + $self->{imgoffs}, $self->_getPrintColor());
                    $cachepic->setPixel($x, $y, $cacheblack);
                }
            }
        }
        $self->{imagecache}->{$cachekey} = $cachepic;
        $self->saveDBCache($cachekey, $cachepic->png);
    } elsif($imagesoftness == 3) {
    
        my @rawgreys = (
            '0000000000000000',
            '0000000001000000',
            '0000100000100000',
            '0010000001000001',
            '1000001000101000',
            '1010000000010110',
            '0001010001101010',
            '1010110010100100',
            '1010010101101010',
            '1001011001011011',
            '1001011110101101',
            '1101101001111110',
            '1011111001111011',
            '1011011111101111',
            '1111011111101111',
            '1111111110111111',
            '1111111111111111',
        );
        my $levels = scalar @rawgreys;
        my $bitlen = length($rawgreys[0]);
        
        my @greys;
        foreach my $rawgrey (@rawgreys) {
            my @parts = split//, $rawgrey;
            push @greys, \@parts;
        }
        
        for(my $y = 0; $y < $desth; $y++) {
            for(my $x = 0; $x < $destw; $x++) {    
                my $greypixel = $pixels[$x]->[$y];
                my $level = int($greypixel / (256 / $levels));

                my $offs = int(rand($bitlen));
                my $bit = $greys[$level]->[($x + $offs) % $bitlen];
                
                if(!$bit) {
                    $self->{img}->setPixel($x, $y + $self->{imgoffs}, $self->_getPrintColor());
                    $cachepic->setPixel($x, $y, $cacheblack);
                }
            }
        }
        
        $self->{imagecache}->{$cachekey} = $cachepic;
        $self->saveDBCache($cachekey, $cachepic->png);
    }
    
    $self->{imgoffs} += $desth;
    return;
}

sub markAsCopy($self, $markascopytext = undef, $copy_y = undef) {
    
    $self->{img}->stringFT($self->_getPrintColor(1), $self->{boldfont}, 20, 0, 10, $copy_y + 10, $markascopytext);
    $self->{imagedata} = $self->{img}->png;

    return;
}

sub loadDBCache($self, $imagekey) {
    my $dbh = $self->{dbh};
    my $reph = $self->{reph};

    my $selsth = $dbh->prepare_cached("SELECT * FROM pagecamel.printerimagecache
                                        WHERE imagekey = ?")
            or croak($dbh->errstr);
    if(!$selsth->execute($imagekey)) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return;
    }
    my $line = $selsth->fetchrow_hashref;
    $selsth->finish;
    $dbh->commit;
    
    if(!defined($line) || !defined($line->{imagedata})) {
        return;
    }

    my $data = decode_base64($line->{imagedata});
    return $data;
}

sub saveDBCache($self, $imagekey, $imagedata) {
    my $dbh = $self->{dbh};
    my $reph = $self->{reph};

    my $data = encode_base64($imagedata, '');

    my $delsth = $dbh->prepare_cached("DELETE FROM pagecamel.printerimagecache
                                        WHERE imagekey = ?")
            or croak($dbh->errstr);

    my $inssth = $dbh->prepare_cached("INSERT INTO pagecamel.printerimagecache (imagekey, imagedata) VALUES (?, ?)")
            or croak($dbh->errstr);

    if(!$delsth->execute($imagekey)) {
        croak($dbh->errstr);
    }
    if(!$inssth->execute($imagekey, $data)) {
        croak($dbh->errstr);
    }
    $dbh->commit;
    return;
}

sub rememberPrint($self, $description) {
    
    my $dbh = $self->{dbh};
    my $reph = $self->{reph};

    my $blob = PageCamel::Helpers::DataBlobs->new($dbh);
    $blob->blobOpen();
    $blob->blobWrite(\$self->{imagedata});
    my $filesize = $blob->getLength();
    my $blobid = $blob->blobID();
    $blob->blobClose();
    
    my $inssth = $dbh->prepare_cached("INSERT INTO " . $self->{table} . "
                                      (file_datablob_id, filesize_bytes, description)
                                      VALUES (?, ?, ?)
                                      RETURNING document_id")
            or croak($dbh->errstr);
    if(!$inssth->execute($blobid, $filesize, $description)) {
        $reph->debuglog("DB FAIL: " . $dbh->errstr);
        $dbh->rollback;
        return 0;
    }
    my $line = $inssth->fetchrow_hashref;
    $inssth->finish;
    my $documentid = $line->{document_id};
    
    $reph->debuglog("Printed document saved as ID $documentid with BLOB $blobid");
    $dbh->commit;
    
    return $documentid;
}

sub reprintDocument($self, $documentid, $printername) {

    my $dbh = $self->{dbh};
    my $reph = $self->{reph};
    
    $reph->debuglog("REPRINT ID $documentid on printer $printername");
    
    my $selsth = $dbh->prepare_cached("SELECT * FROM " . $self->{table} . "
                                       WHERE document_id = ?")
            or croak($dbh->errstr);
    if(!$selsth->execute($documentid)) {
        $reph->debuglog("   FAIL: " . $dbh->errstr);
        $dbh->rollback;
        return;
    }
    
    
    my $line = $selsth->fetchrow_hashref;
    $selsth->finish;
    
    if(!defined($line) || !defined($line->{document_id})) {
        $reph->debuglog("   Document not found");
        $dbh->rollback;
        return;
    }
    
    my $imagedata;
    my $blob = PageCamel::Helpers::DataBlobs->new($dbh, $line->{file_datablob_id});
    my $len = $blob->getLength();
    $blob->blobRead(\$imagedata);
    $blob->blobClose();
    $dbh->commit;

    $self->{kickCashdrawer} = 0;
    $self->reprintDocumentData($imagedata, $printername);

    return;
}

sub reprintDocumentData($self, $imagedata, $printername) {
    $self->{imagedata} = $imagedata;
    $self->{img} = GD::Image->newFromPngData($imagedata, 0);
    $self->printSendToPrinter($printername);

    return;
}

sub printAddTestPattern_HeatupCooldown($self) {
    
    for(1..2) {
        $self->{img}->filledRectangle(0, $self->{imgoffs},
                                      $self->{width}, $self->{imgoffs} + 200,
                                              $self->_getPrintColor());
        $self->{imgoffs} += 400;
    }

    $self->{img}->filledRectangle(0, $self->{imgoffs},
                                  $self->{width}, $self->{imgoffs} + 200,
                                          $self->_getPrintColor());
    $self->{imgoffs} += 200;
    for(my $i = 512; $i > 0; $i--) {
        $self->{img}->filledRectangle(0, $self->{imgoffs}, $i,
                                          $self->{imgoffs} + 0,
                                          $self->_getPrintColor());
        
        $self->{imgoffs} += 1;
        
    }
    
    return;
}

sub printAddTestPattern_VerticalLines($self, $pointsize) {
    
    for(my $x = 0; $x < $self->{width}; $x += $pointsize) {

        if($x % ($pointsize * 2) != 0) {
            next;
        }
        
        $self->{img}->filledRectangle($x, $self->{imgoffs},
                                      $x + $pointsize, $self->{imgoffs} + 40,
                                          $self->_getPrintColor());
    }

    
    $self->{imgoffs} += 40;
    
    return;
}

sub printAddTestPattern_HorizontalLines($self, $pointsize) {
    
    for(1..2) {
        my $i = 0;

        $self->{img}->filledRectangle(0, $self->{imgoffs}, $self->{width},
                                          $self->{imgoffs} + $pointsize,
                                          $self->_getPrintColor());
        
        $self->{imgoffs} += $pointsize * 2;
        
    }
    
    return;
}

sub printAddTestPattern_GreyBlocks($self) {
    { # Quarter-dark
        my $evenodd  = 0;
        for(1..100) {
            my $val = 0;
            for(my $i = 0; $i < $self->{width} - 1; $i++) {
                if($val == $evenodd) {
                    $self->{img}->setPixel($i, $self->{imgoffs}, $self->_getPrintColor());
                }
                $val++;
                if($val == 4) {
                    $val = 0;
                }
            }
            $self->{imgoffs}++;
            $evenodd = 2 - $evenodd;
        }
    }
    { # Half-dark
        my $evenodd  = 1;
        for(1..100) {
            my $val = 0;
            for(my $i = 0; $i < $self->{width} - 1; $i++) {
                if($val == $evenodd) {
                    $self->{img}->setPixel($i, $self->{imgoffs}, $self->_getPrintColor());
                }
                $val = 1 - $val;
            }
            $self->{imgoffs}++;
            $evenodd = 1 - $evenodd;
        }
    }
    { # Three-Quarter-dark
        my $evenodd  = 0;
        for(1..100) {
            my $val = 0;
            for(my $i = 0; $i < $self->{width} - 1; $i++) {
                if($val != $evenodd) {
                    $self->{img}->setPixel($i, $self->{imgoffs}, $self->_getPrintColor());
                }
                $val++;
                if($val == 4) {
                    $val = 0;
                }
            }
            $self->{imgoffs}++;
            $evenodd = 2 - $evenodd;
        }
    }
    { # Dark
        for(1..100) {
            for(my $i = 0; $i < $self->{width} - 1; $i++) {
                $self->{img}->setPixel($i, $self->{imgoffs}, $self->_getPrintColor());
            }
            $self->{imgoffs}++;
        }
    }

    return;
}

sub printAddTestPattern_Rectangle($self) {
    
    for(my $i = 0; $i < $self->{width}; $i++) {
        if($i == 0 || $i == ($self->{width} - 1)) {
            for(my $j = 0; $j <= $self->{width}; $j++) {
                $self->{img}->setPixel($j, $self->{imgoffs}, $self->_getPrintColor());
            }
        } else {
            $self->{img}->setPixel(0, $self->{imgoffs}, $self->_getPrintColor());
            $self->{img}->setPixel($i, $self->{imgoffs}, $self->_getPrintColor());
            $self->{img}->setPixel($self->{width} - $i - 1, $self->{imgoffs}, $self->_getPrintColor());
            $self->{img}->setPixel($self->{width} - 1, $self->{imgoffs}, $self->_getPrintColor());
        }
        $self->{imgoffs}++;
    }
    
    return;
}


sub printTestMessage($self, $tests) {
    
    my @lines = PageCamel::Helpers::TestData::getTestLines();
    
    $self->printStartDocument();
    for(1..3) {
        $self->printAddTextLine('');
    }
    
    if(contains('text', $tests)) {
        $self->printAddTextLine("TEST 'Text'");
        $self->printAddBigTextLine("GladOS");
        foreach my $line (@lines) {
            $self->printAddTextLine($line);
        }
        for(1..3) {
            $self->printAddTextLine('');
        }
        for(my $i = 0; $i < 4; $i++) {
            $self->printAddBigTextLine("BIGTEXT LINE $i");
        }
        for(my $i = 0; $i < 4; $i++) {
            $self->printAddSmallTextLine("SMALLTEXT LINE $i");
        }
    }

    if(contains('vlines', $tests)) {
        $self->printAddTextLine("TEST 'Vertical lines'");
        for(my $i = 20; $i > 0; $i--) {
            $self->printAddTestPattern_VerticalLines($i);
        }
        for(1..3) {
            $self->printAddTextLine('');
        }
    }

    if(contains('hlines', $tests)) {
        $self->printAddTextLine("TEST 'Horizontal lines'");
        for(my $i = 20; $i > 0; $i--) {
            $self->printAddTestPattern_HorizontalLines($i);
        }
        for(1..3) {
            $self->printAddTextLine('');
        }
    }

    if(contains('greyblocks', $tests)) {
        $self->printAddTextLine("TEST 'Greyscale Blocks'");
        $self->printAddTestPattern_GreyBlocks();
        for(1..3) {
            $self->printAddTextLine('');
        }
    }

    if(contains('heatcool', $tests)) {
        
        $self->printAddTextLine("TEST 'Heat up/Cooldown'");
        $self->printAddTestPattern_HeatupCooldown();
        for(1..3) {
            $self->printAddTextLine('');
        }
    }
    
    if(contains('greyscale', $tests)) {
        $self->printAddTextLine("TEST 'Greyscale Images'");
        for(my $softness = 0; $softness < 4; $softness++) {
            $self->printAddTextLine("   Softness $softness");    
            $self->printAddGreyscaleImage(PageCamel::Helpers::TestData::getTestImage1(), 1, $softness);
            $self->printAddGreyscaleImage(PageCamel::Helpers::TestData::getTestImage2(), 1, $softness);

            for(1..3) {
                $self->printAddTextLine('');
            }
        }
    }
    
    if(contains('rectangle', $tests)) {
        
        $self->printAddTextLine("TEST 'Rectangle'");
        $self->printAddTestPattern_Rectangle();
    }
    
    for(1..3) {
        $self->printAddTextLine('');
    }
    $self->printAddTextLine('**** END OF TEST ****');
    for(1..3) {
        $self->printAddTextLine('');
    }
    
    $self->printEndDocument();
    return;
}

sub makeFName($self, $ispdf = 0) {
    my $fname = '';
    while($fname eq '') {
        $fname = '/tmp/posprint_' . $PID . '_';
        for(1..10) {
            $fname .= '' . int(rand(10)) . '';
        }

        if($ispdf) {
            $fname .= '.pdf';
        } elsif($self->{generateEscPos}) {
            $fname .= '.bin';
        } else {
            $fname .= '.png';
        }
    }
    
    return $fname;
}


1;
