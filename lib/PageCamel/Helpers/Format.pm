package PageCamel::Helpers::Format;
#---AUTOPRAGMASTART---
use v5.42;
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

use POSIX;
use PageCamel::Helpers::Strings qw(stripString);

use base qw(Exporter);
our @EXPORT_OK = qw(formatNumber formatQuantity roundNumber euroToCents centsToEuro linebreakText);

sub formatNumber($displaynumber, $in_cents = 0) {
    if($displaynumber =~ /\,/) {
        print STDERR "Warning: Formatting already formatted number????\n";
        $displaynumber =~ s/\.//g;
        $displaynumber =~ s/\,/./g;
    }
    
    my $isnegative = 0;
    if($displaynumber =~ /^\-/) {
        $isnegative = 1;
        $displaynumber =~ s/^\-//;
    }
    
    if(!$in_cents) {
        $displaynumber = $displaynumber * 100;
    }

    # int() introduces floating point errors, sometimes even in already-integer numbers
    # $displaynumber = int($displaynumber);
    # Let's use regex on a number-as-a-string instead
    #$displaynumber =~ s/\..*$//g;
    $displaynumber = roundNumber($displaynumber, 0);

    $displaynumber = '' . $displaynumber;
    while(length($displaynumber) < 3) {
        $displaynumber = '0' . $displaynumber;
    }
    
    my @displayparts = split//, $displaynumber;
    $displaynumber = pop @displayparts;
    $displaynumber = ',' . (pop @displayparts) . $displaynumber;
    my $cnt = 0;
    while(@displayparts) {
        my $digit = pop @displayparts;
        $displaynumber = $digit . $displaynumber;
        $cnt++;
        if($cnt == 3 && @displayparts) {
            $cnt = 0;
            $displaynumber = '.' . $displaynumber;
        }
    }
    
    if($isnegative) {
        $displaynumber = '-' . $displaynumber;
    }
    
    return $displaynumber;
}

sub formatQuantity($quantity, $retailmode = 1, $trailingzeroes = 0) {
    if(!$retailmode) {
        $quantity = int($quantity);

        while(length($quantity) < 3) {
            $quantity = ' ' . $quantity;
        }

        if(length($quantity) > 3) {
            $quantity = '###';
        }

        return $quantity;
    } else {
        $quantity = '' . $quantity;
        my ($pre, $post) = split/\./, $quantity;
        if(!defined($post)) {
            $post = '000';
        }

        if(length($post) > 3) {
            $post = substr $post, 0, 3;
        }

        while(length($pre) < 3) {
            $pre = ' ' . $pre;
        }
        while(length($post) < 3) {
            $post .= '0';
        }

        if($trailingzeroes && $post eq '000') {
            return $pre . '    ';
        } else {
            return $pre . ',' . $post;
        }
    }

}

sub roundNumber($displaynumber, $digits = 0) {
    my $usekomma = 0;
    if($displaynumber =~ /\,/) {
        $displaynumber =~ s/\,/./g;
        $usekomma = 1;
    }

    my ($pre, $post) = split/\./, $displaynumber;
    if(!defined($post)) {
        $post = '';
    }

    my @parts = split//, $post;
    my @newparts;
    for(my $i = 0; $i < $digits; $i++) {
        if(!scalar @parts) {
            push @newparts, '0';
        } else {
            my $digit = shift @parts;
            push @newparts, $digit;
        }
    }

    if(scalar @parts) {
        # correct rounding
        my $nextdigit = shift @parts;
        if($nextdigit >= 5) {
            my $tempnum = $pre . join('', @newparts);
            $tempnum++;
            my @tempparts = split//, $tempnum;
            @newparts = ();
            for(my $i = 0; $i < $digits; $i++) {
                my $tempdigit = pop @tempparts;
                unshift @newparts, $tempdigit;
            }
            if(!scalar @tempparts) {
                $pre = '0';
            } else {
                $pre = join('', @tempparts);
            }
        }
    }

    my $newnumber = $pre;
    if($digits) {
        $newnumber .= '.' . join('', @newparts);
    }


    if($usekomma) {
        $newnumber =~ s/\./,/g;
    }

    return $newnumber;
}

sub euroToCents($euro) {
    if(!defined($euro)) {
        croak("Undefined value");
    }

    if($euro =~ /\,/) {
        $euro =~ s/\,/./g;
    }

    my ($pre, $post) = split/\./, $euro;
    if(!defined($post)) {
        $post = '';
    }

    while(length($post) < 2) {
        $post .= '0';
    }

    my $cents = $pre . $post;

    $cents = 0 + $cents;

    return $cents;
}

sub centsToEuro($val) {
    if($val =~ /\,/) {
        #croak("BLA $val");
    }
    $val = int($val);

    my $negative = 0;
    if($val =~ s/^\-//g) {
        $negative = 1;
    }

    while(length($val) < 3) {
        $val = '0' . $val;
    }
    $val =~ s/^(\d+)(\d\d)$/$1.$2/;

    if($negative) {
        $val = '-' . $val;
    }

    return $val;

}

sub linebreakText($val, $len, $nextlen = undef) {
    if(!defined($nextlen)) {
        $nextlen = $len;
    }

    $val = stripString($val);
    my @lines;

    $val =~ s/\ \ / /g;

    my @parts = split/\ /, $val;

    my $line = '';

    my $thislen = $len;

    foreach my $part (@parts) {
        if($line ne '') {
            $line .= ' ';
        }

        if((length($line) + length($part)) > $thislen && length($line) < ($thislen/2)) {
            # Current line is only less than half filled. Aggresively linewrap the current part into the current line no matter what. This is much more space effective
            my $partlen = $thislen - length($line);
            $line .= substr($part, 0, $partlen);
            if(length($line)) {
                push @lines, $line;
            }
            $line = '';
            $thislen = $nextlen; # Reset to default line length
            $part = substr $part, $partlen;
        }

        if((length($line) + length($part)) > $thislen) {
            if(length($line)) {
                push @lines, $line;
            }
            $thislen = $nextlen; # Reset to default line length
            if(length($part) < $thislen) {
                $line = $part;
            } else {
                while(length($part)) {
                    $line = substr $part, 0, $thislen;
                    if(length($line) == $thislen) {
                        push @lines, $line;
                        $line = '';
                    }
                    if(length($part) > $thislen) {
                        $part = substr $part, $thislen;
                    } else {
                        $part = '';
                    }
                    $thislen = $nextlen; # Reset to default line length
                }
            }
        } else {
            $line .= $part;
        }
    }
    if(length($line)) {
        push @lines, $line;
    }

    return \@lines;
}


1;
__END__
