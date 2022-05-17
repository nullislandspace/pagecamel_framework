#!/usr/bin/env perl
#---AUTOPRAGMASTART---
use 5.032;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
use feature 'signatures';
no warnings qw(experimental::signatures);
#---AUTOPRAGMAEND---


print "<html><head><title>Statistics</title></head><body><table>";
for(1..1000) {
    print "<tr>";
    for(1..500) {
        print "<td>X</td>";
    }
    print "</tr>";
}
print "</table></body></html>";
