#!/usr/bin/env perl
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
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
