#!/usr/bin/env perl
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

use Perl::Tidy;
use File::Copy;

die("This makes a lot of problems. Don't use!!!!");

my @arguments = (
#   '--backup-and-modify-in-place',
   '--cuddled-else',
   '--indent-columns=4',
   '--paren-tightness=2', 
   '--square-bracket-tightness=2', 
   '--brace-tightness=2', 
   '--nospace-after-keyword="if else elsif until unless while for switch case given when"', 
   '--break-after-all-operators',
);

my $args = join(' ', @arguments);

# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license


print "Searching files...\n";
my @files = (find_pm('lib'), find_pm('devscripts'));
#my @files = find_pm('server');

print "Changing files:\n";
foreach my $file (@files) {
    print "Tidying $file...\n";
    my $error_flag = Perl::Tidy::perltidy(
        source => $file,
        destination => $file . '.tdy',
        argv => $args,
    );
    if($error_flag) {
        die("  Tidy error on $file: $error_flag");
    }
    move($file . '.tdy', $file) or die("Move failed: $ERRNO");

}
print "Done.\n";
exit(0);



sub find_pm($workDir) {
    my @files;
    opendir(my $dfh, $workDir) or die($ERRNO);
    while((my $fname = readdir($dfh))) {
        next if($fname eq "." || $fname eq ".." || $fname eq ".hg");
        $fname = $workDir . "/" . $fname;
        if(-d $fname) {
            push @files, find_pm($fname);
        } elsif($fname =~ /\.p[lm]$/i && -f $fname) {
            push @files, $fname;
        }
    }
    closedir($dfh);
    return @files;
}
