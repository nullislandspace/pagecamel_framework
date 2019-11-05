#!/usr/bin/env perl
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.4;
use Fatal qw( close );
use Array::Contains;
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
