#!/usr/bin/env perl
#---AUTOPRAGMASTART---
use v5.38;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.3;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
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
