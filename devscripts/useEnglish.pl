#!/usr/bin/env perl
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.1;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

# PAGECAMEL  (C) 2008-2018 Rene Schickbauer
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



sub find_pm {
    my ($workDir) = @_;

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
