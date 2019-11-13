#!/usr/bin/perl
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp;
our $VERSION = 2.4;
use autodie qw( close );
use Array::Contains;
use utf8;
#---AUTOPRAGMAEND---

# PAGECAMEL  (C) 2008-2018 Rene Schickbauer
# Developed under Artistic license

foreach my $fname (@ARGV) {
    my $hasform = 0;
    my $hasfilterform = 0;
    my $hasfiltertable = 0;

    open(my $ifh, "<", $fname) or die($ERRNO);
    my @lines = <$ifh>;
    close $ifh;

    foreach my $line (@lines) {
        if($line =~ /MainFilterTable/) {
            $hasfiltertable = 1;
        }
        if($line =~ /MainFilterForm/) {
            $hasfilterform = 1;
        }
        if($line =~ /form/) {
            $hasform = 1;
        }

    }
    next if(!$hasform);
    if($hasfilterform != $hasfiltertable) {
        print "$fname\n";
    }

}
