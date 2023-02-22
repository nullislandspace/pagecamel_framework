#!/usr/bin/env perl
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license


print "Searching files...\n";
my @files = (find_pm('lib'), find_pm('devscripts'));
#my @files = find_pm('server');

print "Changing files:\n";
foreach my $file (@files) {
    if($file =~ /useEnglish\.pl/) {
        print "Skipping my own script...\n";
        next;
    }
    print "Editing $file...\n";

    my @lines;
    open(my $ifh, "<", $file) or die($!);
    @lines = <$ifh>;
    close $ifh;

    open(my $ofh, ">", $file) or die($!);
    foreach my $line (@lines) {
        $line =~ s/\$\@/\$EVAL_ERROR/g;
        $line =~ s/\$\/(\ *\=)/\$INPUT_RECORD_SEPARATOR$1/g;
        $line =~ s/\$\!/\$ERRNO/g;
        $line =~ s/\$\>/\$EFFECTIVE_USER_ID/g;
        $line =~ s/\$\^\O/\$OSNAME/g;
        $line =~ s/\$\?/\$CHILD_ERROR/g;

        print $ofh $line;
    }
    close $ofh;
}
print "Done.\n";
exit(0);



sub find_pm($workDir) {

    my @files;
    opendir(my $dfh, $workDir) or die($!);
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
