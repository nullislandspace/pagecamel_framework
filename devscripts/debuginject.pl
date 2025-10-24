#!/usr/bin/env perl
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license


print "Searching files...\n";
my @files = (find_pm('lib'));

print "Changing files:\n";
foreach my $file (@files) {
    my $inserted = 0;
    print "Editing $file...\n";

    my @lines;
    open(my $ifh, "<", $file) or die($ERRNO);
    @lines = <$ifh>;
    close $ifh;

    open(my $ofh, ">", $file) or die($ERRNO);
    my $pkgname = '--undef--';
    foreach my $line (@lines) {
        if($line =~ /\#\ DEBUGINJECT/) {
            next;
        }
        if($line =~ /package\ (.*)\;/) {
            $pkgname = $1;
        }
        if($line =~ /^\ *sub\ +(.+?)\{/ && $line !~ /\}$/) {
            my $subname = $1;
            print $ofh $line;
            print $ofh 'print STDERR ":: $PID ', $pkgname, '::', $subname, '\n"; # DEBUGINJECT', "\n";
            next;
        }

        print $ofh $line;
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
        } elsif($fname =~ /\.p[lm]$/i && -f $fname) {
            push @files, $fname;
        }
    }
    closedir($dfh);
    return @files;
}
