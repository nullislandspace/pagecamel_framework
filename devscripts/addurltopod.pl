#!/usr/bin/env perl
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

# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license

#die("Program disabled! Enable program by commenting out this line!");

print "Searching files...\n";
my @files = (find_pm('lib'), find_pm('devscripts'));

print "Changing files:\n";
foreach my $file (@files) {
    if($file =~ /resetpod/) {
        print "Skipping my own program\n";
        next;
    }
    print "Editing $file...\n";

    my @lines;
    open(my $ifh, "<", $file) or die($ERRNO);
    @lines = <$ifh>;
    close $ifh;

    open(my $ofh, ">", $file) or die($ERRNO);
    my $packname = '';
    my @funcs;
    foreach my $line (@lines) {
        chomp $line;
        # Remove trailing whitespace
        $line =~ s/\ +$//g;
        $line =~ s/\t+$//g;
        print $ofh $line, "\n";

        # Now, for easier matching and stuff, also remove
        # leading whitespace...
        $line =~ s/^\ +//g;
        $line =~ s/^\t+//g;

        # ...and simplify whitespace in between
        $line =~ s/^\ +/ /g;
        $line =~ s/^\t+/ /g;

        if($line =~ /package\ (.*)\;/) {
            # Package name
            $packname = $1;
            next;
        }

        if($line eq 'copy&paste what you need, see license terms below).') {
            print $ofh "\n";
            print $ofh "To see PageCamel in action and for news about the project,\n";
            print $ofh "visit my blog at L<https://cavac.at>.\n";
        }

    }

    close $ofh;
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
            #} elsif($fname =~ /\.p[lm]$/i && -f $fname) {
        } elsif($fname =~ /\.pm$/i && -f $fname) {
            push @files, $fname;
        }
    }
    closedir($dfh);
    return @files;
}
