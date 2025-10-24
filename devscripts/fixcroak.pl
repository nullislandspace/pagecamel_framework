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


use File::Find;

my @files;
find(\&findModules, '.');

# Do a dry-run first
my $ok = 1;
foreach my $fname (@files) {
    #print "------- ", $fname, " -------\n";
    if(!fixCroak($fname, 1)) {
        $ok = 0;
    }
}

if(!$ok) {
    croak("Dry run failed, won't edit files!");
}


foreach my $fname (@files) {
    fixCroak($fname, 0);
}

print "\n\n****** AUTOEDIT FINISHED ******\n";

sub findModules() {
    my $fname = $File::Find::name;
    # Ignore hidden files or directories (starting with a dot)
    if($fname =~ /\/\./) {
        #print "   Ignoring $fname\n";
        return;
    }

    if($fname !~ /\.p[ml]$/) {
        #print "   Not Perl: $fname\n";
        return;
    }

    if($fname =~ /fixcroak\.pl/) {
        return;
    }

    push @files, $fname;

    return;
}

sub fixCroak($fname, $dryrun) {
    my $parseOK = 1;

    open(my $ifh, '<', $fname) or croak("$!");
    my @lines = <$ifh>;
    close $ifh;

    my @newlines;

    my $linenum = 0;

    foreach my $line (@lines) {
        $linenum++;
        chomp $line;

        if($line !~ /croak/) {
            goto printLine;
        }

        if($line =~ /use\ Carp/) {
            goto printLine;
        }

        if($line =~ /^\ *\#/) {
            # Ignore comment lines
            goto printLine;
        }

        if($line =~ /croak\(\'/) {
            # non-evaluating croak string is OK as it is
            goto printLine;
        }

        if($line =~ /croak\ \"(.*?)\"/) {
            #print " - ", $line, "\n";
            $line =~ s/croak\ \"(.*?)\"/croak\(\"$1\"\)/;
            #print " + ", $line, "\n";
        }

        if($line !~ /croak\(/) {
            print "Failed to parse croak line $linenum: ", $line, "\n";
            $parseOK = 0;
        }


        if($line =~ /croak\((\$.*?\))/) {
            my $match = $1;
            if($match =~ /\"/ || $match =~ /\'/ || $match =~ /\ \.\ /) {
                # Compound string
                print "Compound string in $fname:\n    $line\n";
                goto printLine;
            }
            if($match =~ /dbh.*\-\>errstr/) {
                # dbh->errstr and it's variants are already proper string, no need to quote them
                goto printLine;
            }
            #print " - ", $line, "\n";
            $line =~ s/croak\((.*?)\)/croak\(\"$1\"\)/;
            #print " + ", $line, "\n";
        }

        if($line !~ /croak\(\"/) {
            print "Failed to edit croak line $linenum: ", $line, "\n";
            $parseOK = 0;
        }


        printLine:
            push @newlines, $line . "\n";
    }

    if(!$dryrun) {
        open(my $ofh, '>', $fname) or croak("$!");
        print $ofh join('', @newlines);
        close $ofh;
    }

    return $parseOK;
}

