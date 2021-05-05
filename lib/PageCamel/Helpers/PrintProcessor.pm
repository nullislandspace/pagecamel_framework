package PageCamel::Helpers::PrintProcessor;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use GD;
use GD::Text;
use PageCamel::Helpers::FileSlurp qw(writeBinFile);
use PageCamel::Helpers::DataBlobs;
use PageCamel::Helpers::TestData;
use Crypt::Digest::SHA256 qw[sha256_hex];

sub new {
    my ($proto, $config) = @_;
    my $class = ref($proto) || $proto;
    
    my $self = bless $config, $class;

    if(!defined($self->{use_eog})) {
        $self->{use_eog} = 0;
    }
    
    $self->{imagecache} = {};
    
    return $self;
}

sub printStartDocument {
    my ($self) = @_;
    
    $self->{img} = GD::Image->new($self->{width}, $self->{height});
    $self->{imgoffs} = 0;
    $self->{imgblack} = $self->{img}->colorAllocate(0, 0, 0);
    $self->{imgwhite} = $self->{img}->colorAllocate(255, 255, 255);
    
    $self->{img}->filledRectangle(0, 0, $self->{width}, $self->{height}, $self->{imgwhite});
    
    return;
}

sub printEndDocument {
    my ($self, $printername) = @_;
    
    # Need to downsize image to minimum required length
    my $cropped = GD::Image->new($self->{width}, $self->{imgoffs});
    my $black = $cropped->colorAllocate(0, 0, 0);
    my $white = $cropped->colorAllocate(255, 255, 255);
    
    $cropped->copyResized($self->{img},
                          0, 0, # DEST X Y
                          0, 0, # SRC X Y
                          $self->{width}, $self->{imgoffs}, # DEST W H
                          $self->{width}, $self->{imgoffs}, # SRC W H
                          );
    
    my $ofname = $self->makeFName();

    if($self->{use_eog}) {
        $ofname = '/home/cavac/src/temp/posprint.png';
    }

    my $imagedata = $cropped->png;
    writeBinFile($ofname, $imagedata);
    
    if($self->{use_eog}) {
        my $cmd = 'gimp ' . $ofname;
        `$cmd`;
    } else {
        my $cmd = $self->{printcommand};
        if(defined($printername) && $printername ne '') {
            $cmd .= ' -P ' . $printername;
        }
        $cmd .= ' ' . $ofname;
        `$cmd`;
    }
    
    unlink $ofname;
    
    delete $self->{img};
    delete $self->{imgoffs};
    delete $self->{imgblack};
    delete $self->{imgwhite};
    return $imagedata;
}

sub printAddTextLine {
    my ($self, $line) = @_;
    
    chomp $line;
    
    $line = encode_utf8($line);
    my $oldoffs = $self->{imgoffs};
    print Dumper($self->{font});
    $self->{img}->stringFT($self->{imgblack}, $self->{font}, 10, 0, 10, $self->{imgoffs} + 10, $line);
    
    $self->{imgoffs} += 12;
    
    return $oldoffs;
}

sub printAddSmallTextLine {
    my ($self, $line) = @_;
    
    chomp $line;
    
    $self->{img}->stringFT($self->{imgblack}, $self->{smallfont}, 8, 0, 10, $self->{imgoffs} + 8, $line);
    
    $self->{imgoffs} += 9;
    
    return;
}

sub printAddBigTextLine {
    my ($self, $line) = @_;
    
    chomp $line;
    
    $self->{img}->stringFT($self->{imgblack}, $self->{bigfont}, 50, 0, 10, $self->{imgoffs} + 50, $line);
    
    $self->{imgoffs} += 55;
    
    return;
}

sub printAddImage {
    my ($self, $filename, $isbindata, $imagesoftness, $doscale, $center) = @_;
    
    my $reph = $self->{reph};
    
    my $pic;
    if(!defined($isbindata)) {
        $isbindata = 0;
    }
    
    # Image softness (dithering grade) only works on greyscale image
    if(!defined($imagesoftness)) {
        $imagesoftness = 1;
    }
    if(!defined($doscale)) {
        $doscale = 1;
    }
    if(!defined($center)) {
        $center = 0;
    }
    
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
    
    $self->{imgoffs} += 10 + $desth;
    
    return;
}

sub printAddGreyscaleImage {
    my ($self, $filename, $isbindata, $imagesoftness) = @_;
    
    my $reph = $self->{reph};
    
    if(!defined($imagesoftness)) {
        $imagesoftness = 1;
    }
    
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
                    $self->{img}->setPixel($x, $y + $self->{imgoffs}, $self->{imgblack});
                    $cachepic->setPixel($x, $y, $cacheblack);
                }
            }
        }
        $self->{imagecache}->{$cachekey} = $cachepic;
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
                        next unless($deltax >= 0 && $deltax < $destw);
                        next unless($deltay >= 0 && $deltay < $desth);
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
                    $self->{img}->setPixel($x, $y + $self->{imgoffs}, $self->{imgblack});
                    $cachepic->setPixel($x, $y, $cacheblack);
                }
            }
        }
        
        $self->{imagecache}->{$cachekey} = $cachepic;
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
                        next unless($deltax >= 0 && $deltax < $destw);
                        next unless($deltay >= 0 && $deltay < $desth);
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
                    $self->{img}->setPixel($x, $y + $self->{imgoffs}, $self->{imgblack});
                    $cachepic->setPixel($x, $y, $cacheblack);
                }
            }
        }
        $self->{imagecache}->{$cachekey} = $cachepic;
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
                my $index = $pic->getPixel($x, $y);
                my ($r,$g,$b) = $pic->rgb($index);
                my $greypixel = int(($r+$g+$b)/3);
                my $level = int($greypixel / (255 / $levels));
                
                my $offs = int(rand($bitlen));
                my $bit = $greys[$level]->[($x + $offs) % $bitlen];
                
                if(!$bit) {
                    $self->{img}->setPixel($x, $y + $self->{imgoffs}, $self->{imgblack});
                    $cachepic->setPixel($x, $y, $cacheblack);
                } else {
                }
            }
        }
        
        $self->{imagecache}->{$cachekey} = $cachepic;
    }
    
    $self->{imgoffs} += $desth;
    return;
}

sub rememberPrint {
    my ($self, $imagedata, $description, $markascopytext, $copy_y) = @_;
    
    my $dbh = $self->{dbh};
    my $reph = $self->{reph};

    if(defined($markascopytext)) {
        my $img = GD::Image->new($imagedata);
        my $black = $img->colorAllocate(0, 0, 0);
        my $white = $img->colorAllocate(255, 255, 255);
        $img->stringFT($black, $self->{font}, 10, 0, 10, $copy_y + 10, $markascopytext);
        $imagedata = $img->png;
    }
    
    my $blob = PageCamel::Helpers::DataBlobs->new($dbh);
    $blob->blobOpen();
    $blob->blobWrite(\$imagedata);
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
    
    return 1;
}

sub reprintDocument {
    my ($self, $documentid, $printername) = @_;

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
    
    my $ofname = makeFName();
    print STDERR $ofname, "\n";

    writeBinFile($ofname, $imagedata);
    
    my $cmd = $self->{printcommand};
    if(defined($printername) && $printername ne '') {
        $cmd .= ' -P ' . $printername;
    }
    $cmd .= ' ' . $ofname;
    `$cmd`;
    
    $reph->debuglog("    " . $line->{description});
    
    unlink $ofname;
    
    return;
}

sub printAddTestPattern_HeatupCooldown {
    my ($self) = @_;
    
    for(1..3) {
        $self->{img}->filledRectangle(0, $self->{imgoffs},
                                      $self->{width}, $self->{imgoffs} + 200,
                                              $self->{imgblack});
        $self->{imgoffs} += 400;
    }
    
    return
}

sub printAddTestPattern_VerticalLines {
    my ($self, $pointsize) = @_;
    
    for(my $x = 0; $x < $self->{width}; $x += $pointsize) {

        if($x % ($pointsize * 2) != 0) {
            next;
        }
        
        $self->{img}->filledRectangle($x, $self->{imgoffs},
                                      $x + $pointsize, $self->{imgoffs} + 40,
                                          $self->{imgblack});
    }

    
    $self->{imgoffs} += 40;
    
    return
}

sub printAddTestPattern_HorizontalLines {
    my ($self, $pointsize) = @_;
    
    for(1..2) {
        my $i = 0;

        $self->{img}->filledRectangle(0, $self->{imgoffs}, $self->{width},
                                          $self->{imgoffs} + $pointsize,
                                          $self->{imgblack});
        
        $self->{imgoffs} += $pointsize * 2;
        
    }
    
    return
}

sub printAddTestPattern_Rectangle {
    my ($self) = @_;
    
    for(my $i = 0; $i < $self->{width}; $i++) {
        if($i == 0 || $i == ($self->{width} - 1)) {
            for(my $j = 0; $j <= $self->{width}; $j++) {
                $self->{img}->setPixel($j, $self->{imgoffs}, $self->{imgblack});
            }
        } else {
            $self->{img}->setPixel(0, $self->{imgoffs}, $self->{imgblack});
            $self->{img}->setPixel($i, $self->{imgoffs}, $self->{imgblack});
            $self->{img}->setPixel($self->{width} - $i - 1, $self->{imgoffs}, $self->{imgblack});
            $self->{img}->setPixel($self->{width} - 1, $self->{imgoffs}, $self->{imgblack});
        }
        $self->{imgoffs}++;
    }
    
    return
}


sub printTestMessage {
    my ($self, $printer, $tests) = @_;
    
    my @lines = PageCamel::Helpers::TestData::getTestLines();
    
    $self->printStartDocument();
    
    if(contains('text', $tests)) {
        $self->printAddTextLine("TEST 'Text'");
        $self->printAddBigTextLine("GladOS");
        foreach my $line (@lines) {
            $self->printAddTextLine($line);
        }
        for(1..3) {
            $self->printAddTextLine('');
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

    if(contains('heatcool', $tests)) {
        
        $self->printAddTextLine("TEST 'Heat up/Cooldown'");
        $self->printAddTestPattern_HeatupCooldown();
    }
    
    if(contains('greyscale', $tests)) {
        $self->printAddTextLine("TEST 'Greyscale Images'");
        for(my $softness = 0; $softness < 4; $softness++) {
            $self->printAddTextLine("   Softness $softness");    
            $self->printAddGreyscaleImage(PageCamel::Helpers::TestData::getTestImage1(), 1, $softness);
            $self->printAddGreyscaleImage(PageCamel::Helpers::TestData::getTestImage2(), 1, $softness);
        }
        for(1..3) {
            $self->printAddTextLine('');
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
    
    $self->printEndDocument($printer);
    return;
}

sub makeFName {
    my ($self) = @_;
    
    my $fname = '';
    while($fname eq '') {
        $fname = '/tmp/posprint_' . $PID . '_';
        for(1..10) {
            $fname .= '' . int(rand(10)) . '';
        }
        $fname .= '.png';
    }
    
    return $fname;
}


1;
