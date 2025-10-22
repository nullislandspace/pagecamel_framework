package PageCamel::Helpers::PDFReport;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.7;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use PageCamel::Helpers::Padding qw(doLeftSpacePad doSpacePad doCenterPad);
use Time::HiRes qw(sleep);
use JSON::XS;
use MIME::Base64 qw(encode_base64 decode_base64);
use PageCamel::Helpers::FileSlurp qw(writeBinFile);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::Format qw(linebreakText);
use GD;
use PDF::Report;
BEGIN {
    # The original setFont function in PDF::Report uses the deprecated "corefont" function from PDF::API2, which does NOT allow
    # using external font files. We add a new function that uses the newer, more generic "font" call.
    *PDF::Report::setExternalFont = sub {
        my ( $self, $font, $size )= @_;

        if(exists $self->{__font_cache}->{$font}) {
            $self->{font} = $self->{__font_cache}->{$font};
        } else {
            $self->{font} = $self->{pdf}->font($font);
            $self->{__font_cache}->{$font} = $self->{font};
        }

        $self->{fontname} = $font;
    };

    # We also want to add a passthrough function to PDF::API2 that allows us to use GD::Image objects directly
    *PDF::Report::addGDImage = sub {
        my ($self, $image, $x, $y, $scale) = @_;

        my ($w, $h) = $image->getBounds();
        if(defined($scale) && $scale != 1) {
            $w = int($w * $scale);
            $h = int($h * $scale);
        }

        my $handle = $self->{pdf}->image($image);
        $self->{page}->object($handle, $x, $y, $w, $h);
    };

};

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = bless \%config, $class;

    my $ok = 1;
    foreach my $required (qw[regularFont boldFont monospacedFont boldmonospacedFont]) {
        if(!defined($self->{$required})) {
            print STDERR "Configuration $required not defined\n";
            $ok = 0;
        }
    }
    if(!$ok) {
        croak("Configuration error");
    }
    return $self;
}

sub generateReport($self, $data) {
    $self->{pdf} = PDF::Report->new(PageSize => "A4", PageOrientation => "Portrait");
    $self->{pagecount} = 0;

    if(defined($data->{stationary}->{logo})) {
        my $logo = GD::Image->newFromPngData($data->{stationary}->{logo});
        my ($w, $h) = $logo->getBounds();
        $data->{stationary}->{logowidth} = int($w / 2); # Will print at 50% scale
        $data->{stationary}->{logoheight} = int($h / 2);
        $data->{stationary}->{logogd} = $logo;
    }

    $self->newPage($data);

    foreach my $table (@{$data->{tables}}) {
        $self->addTable($data, $table);
    }

    if(defined($data->{footergraphic})) {
        my $logo = GD::Image->newFromPngData($data->{footergraphic});
        my ($w, $h) = $logo->getBounds();
        $w = int($w / 2); # Print it at 50% scale
        $h = int($h / 2);
        if($self->{y} < (100 + $h)) {
            $self->newPage($data);
        }
        my $xoffs = int((560 - $w) / 2);
        my $fullheight = $h;

        if(defined($data->{footergraphictext})) {
            my @parts = @{$data->{footergraphictext}};

            # Calculate width of Text so we can center the whole thing
            my $twidth = 0;
            $self->{pdf}->setSize(5);
            $self->{pdf}->setExternalFont($self->{monospacedFont});
            for(my $i = 0; $i < scalar @parts; $i++) {
                my $tempwidth = $self->{pdf}->getStringWidth($parts[$i]);
                if($tempwidth > $twidth) {
                    $twidth = $tempwidth;
                }
            }
            # New $xoffs
            $xoffs = int((560 - $w - 10 - $twidth) / 2);

            # Finally, add the text
            for(my $i = 0; $i < scalar @parts; $i++) {
                $self->addText('monospacedFont', $xoffs + $w + 10, $self->{y} - ($i * 7) - 10, 5, 'black', $parts[$i]);
            }

            if((scalar @parts) * 7 > $fullheight) {
                $fullheight = (scalar @parts) * 7;
            }
        }

        # Add the image
        $self->{pdf}->addGDImage($logo, $xoffs, $self->{y} - $h, 0.5);
        $self->{y} -= $fullheight + 20;
    }

    my $footerlogoheight = 0;
    my $footerlogo;
    if(defined($data->{footerlogo})) {
        $footerlogo = GD::Image->newFromPngData($data->{footerlogo});
        my ($w, $h) = $footerlogo->getBounds();
        $footerlogoheight = int($h / 2); # We add it at 50% scale so it looks more to scale like the one printed in thermal printer rolls. Also makes it look slightly higher res
    }

    my $footerlogodone = 0;
    if(!$footerlogoheight) {
        $footerlogodone = 1;
    }
    if(defined($data->{footerlines})) {
        my $height = scalar @{$data->{footerlines}} * 12 + $footerlogoheight;
        if($self->{y} < (100 + $height)) {
            $self->newPage($data);
        }

        foreach my $footerline (@{$data->{footerlines}}) {
            if($footerline =~ /XXXLOGOXXX/) {
                if(!$footerlogodone) {
                    $self->{pdf}->addGDImage($footerlogo, 50, $self->{y} - $footerlogoheight, 0.5);
                    $self->{y} -= $footerlogoheight + 20;
                }
                $footerlogodone = 1;
                next;
            }

            my $fontname = 'regularFont';
            if($footerline =~ /^\$/) {
                $footerline =~ s/^\$//;
                $fontname = 'boldFont';
            }
            $self->addText($fontname, 20, $self->{y}, 10, 'black', $footerline);
            $self->{y} -= 12;
        }
    }

    if(!$footerlogodone) {
        if($self->{y} < (100 + $footerlogoheight)) {
            $self->newPage($data);
        }
        $self->{pdf}->addGDImage($footerlogo, 20, $self->{y} - $footerlogoheight, 0.5);
        $self->{y} -= $footerlogoheight + 20;
    }

    my $now = getISODate();
    for(my $i = 0; $i < $self->{pagecount}; $i++) {
        $self->{pdf}->openpage($i + 1);
        $self->addText('regularFont', 20, 20, 10, 'grey', $now);
        $self->addText('regularFont', 200, 20, 10, 'grey', 'Seite ' . ($i + 1) . ' von ' . $self->{pagecount});
    }

    my $report = $self->{pdf}->Finish;

    delete $self->{pdf};

    #writeBinFile('/home/cavac/src/temp/report.pdf', $report);
    return $report;
}


sub addText($self, $fontname, $x, $y, $size, $color, $text) {
    my $nbsp = chr(0xA0);
    $text =~ s/\ /$nbsp/g;

    $self->{pdf}->setSize($size);
    $self->{pdf}->setExternalFont($self->{$fontname});
    $self->{pdf}->addRawText($text, $x, $y, $color);
    return;
}

sub newPage($self, $data) {
    $self->{pdf}->newpage(1);
    $self->{pagecount}++;
    my ($pagewidth, $pageheight) = $self->{pdf}->getPageDimensions();

    $self->{y} = $pageheight - 20;

    if(defined($data->{stationary})) {
        my $sheight = 0;
        if(defined($data->{stationary}->{logo})) {
            $sheight = $data->{stationary}->{logoheight};
            $self->{pdf}->addGDImage($data->{stationary}->{logogd}, 560 - $data->{stationary}->{logowidth}, $self->{y} - $data->{stationary}->{logoheight}, 0.5);
        }

        if(defined($data->{stationary}->{address})) {
            for(my $i = 0; $i < scalar @{$data->{stationary}->{address}}; $i++) {
                $self->addText('regularFont', 40, $self->{y} - ($i * 15), 10, 'black', $data->{stationary}->{address}->[$i]);
            }
            my $theight = scalar @{$data->{stationary}->{address}} * 15;
            if($theight > $sheight) {
                $sheight = $theight;
            }
        }

        $self->{y} -= $sheight;
        $self->{y} -= 20;
    }

    if($self->{pagecount} == 1 && defined($data->{address})) {
        foreach my $headerline (@{$data->{address}}) {
            $self->addText('regularFont', 20, $self->{y}, 10, 'black', $headerline);
            $self->{y} -= 12;
        }
        $self->{y} -= 30;
    }

    $self->addText('boldFont', 20, $self->{y}, 20, 'black', $data->{title});
    $self->{y} -= 30;


    foreach my $headerline (@{$data->{headerlines}}) {
        $self->addText('regularFont', 20, $self->{y}, 10, 'black', $headerline);
        $self->{y} -= 12;
    }

    $self->{y} -= 20;

    return;
}

sub addTable($self, $data, $table) {
    # Ignore table if it has no data
    if(!defined($table->{data}) || ref $table->{data} ne 'ARRAY' || !scalar @{$table->{data}}) {
        return;
    }

    # Calculate the column offsets
    {
        $self->{pdf}->setSize(10);
        $self->{pdf}->setExternalFont($self->{monospacedFont});
        my $offset = 20;
        foreach my $col (@{$table->{columns}}) {
            $col->{offset} = $offset;
            my $bla = 'X' x $col->{width};
            my $width = $self->{pdf}->getStringWidth($bla);
            $col->{pixelwidth} = $width;
            $offset += $width + 20;
        }
    }
    $self->{pdf}->setGfxLineWidth(1);

    if($self->{y} < 140) {
        $self->newPage($data);
    }

    if(defined($table->{title}) && $table->{title} ne '') {
        $self->addText('boldFont', 20, $self->{y}, 20, 'black', $table->{title});
        $self->{y} -= 30;
    }

    my $needheader = 1;
    my $evenodd = 1;
    my $nbsp = chr(0xA0);
    foreach my $line (@{$table->{data}}) {
        if($self->{y} < 100) {
            $self->newPage($data);
            $needheader = 1;
        }

        if($needheader) {
            $self->{pdf}->shadeRect(15, $self->{y} + 10, 560, $self->{y} - 5, "grey");
            $evenodd = 1;

            #foreach my $col (@{$table->{columns}}) {
            for(my $i = 0; $i < scalar @{$table->{columns}}; $i++) {
                $self->addText('boldmonospacedFont', $table->{columns}->[$i]->{offset}, $self->{y}, 10, 'black', $table->{columns}->[$i]->{name});

                if(defined($table->{columns}->[$i + 1])) {
                    my $xline = $table->{columns}->[$i + 1]->{offset} - 10;
                    $self->{pdf}->drawLine($xline, $self->{y} + 10, $xline, $self->{y} - 5);
                }
            }
            $self->{y} -= 15;
            $needheader = 0;
        }

        my $linefont = 'monospacedFont';
        if($line->[0] =~ /^\$/) {
            $linefont = 'boldmonospacedFont';
            $line->[0] =~ s/^\$//;
        }

        # Wrap text and find out how many lines this will take
        my @formatted;
        my $maxlines = 1;
        for(my $i = 0; $i < scalar @{$table->{columns}}; $i++) {
            if(!defined($line->[$i])) {
                $line->[$i] = '';
            }

            my $val = $line->[$i];

            my @parts = split/\n/, $val;
            my @dest;
            foreach my $part (@parts) {
                #my $newval = $self->{pdf}->wrapText($part, $table->{columns}->[$i]->{pixelwidth});
                #my @newparts = split/\n/, $newval;

                my $newval = linebreakText($part, $table->{columns}->[$i]->{width});
                my @newparts = @{$newval};

                foreach my $newpart (@newparts) {
                    if($table->{columns}->[$i]->{align} eq 'right') {
                        $newpart = doLeftSpacePad($newpart, $table->{columns}->[$i]->{width});
                        $newpart =~ s/\ /$nbsp/g;
                    }
                    push @dest, $newpart;
                }
            }

            if(scalar @dest > $maxlines) {
                $maxlines = scalar @dest;
            }
            push @formatted, \@dest;
        }

        if($evenodd) {
            $self->{pdf}->shadeRect(15, $self->{y} + 10, 560, $self->{y} - (15 * $maxlines) + 10, "lightGrey");
        }
        $evenodd = 1 - $evenodd;

        for(my $i = 0; $i < scalar @{$table->{columns}}; $i++) {
            my $coldata = $formatted[$i];
            my $offset = $table->{columns}->[$i]->{offset};
            for(my $j = 0; $j < scalar @{$coldata}; $j++) {
                $self->addText($linefont, $table->{columns}->[$i]->{offset}, $self->{y} - ($j * 15), 10, 'black', $coldata->[$j]);
            }
            if(defined($table->{columns}->[$i + 1])) {
                my $xline = $table->{columns}->[$i + 1]->{offset} - 10;
                $self->{pdf}->drawLine($xline, $self->{y} + 10, $xline, $self->{y} - ($maxlines * 15) + 10);
            }
        }

        $self->{y} -= $maxlines * 15;
    }

    $self->{y} -= 20;

    return;
}



1;
