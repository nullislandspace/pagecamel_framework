#!/usr/bin/env perl
#---AUTOPRAGMASTART---
use 5.032;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.0;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
use feature 'signatures';
no warnings qw(experimental::signatures);
#---AUTOPRAGMAEND---


print "<html><head><title>Login</title></head><body><form method=\"POST\"><table>";
for(1..50000) {
    print "<tr><td>Captcha Part $_</td><td><input type=\"radio\" name=\"captcha\" value=\"" . $_ . "\"><img src=\"/pics/hackman2.gif\"></td></tr>";
}
print "<tr><td>Username</td><td><input type=\"text\" name=\"username\"></td></tr>";
print "<tr><td>Password</td><td><input type=\"password\" name=\"password\"></td></tr>";
print "<tr><td colspan=\"2\"><input type=\"submit\" value=\"Login\"></td></tr>";
print "</table><form></body></html>";
