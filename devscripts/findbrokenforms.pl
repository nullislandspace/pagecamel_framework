#!/usr/bin/perl
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

# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
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
