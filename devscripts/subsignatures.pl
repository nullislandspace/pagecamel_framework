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
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license


print "Searching files...\n";
my @files = (find_pm('devscripts'), find_pm('lib'));

#@files = ('lib/PageCamel/Helpers/PostgresDB.pm');

die('optionalargs.txt already exists!') if(-f 'optionalargs.txt');
open(my $optfh, '>', 'optionalargs.txt') or die($ERRNO);

my %knownoptionals;

print "Changing files:\n";
foreach my $file (@files) {
    my $inserted = 0;
    print "Editing $file...\n";

    my @lines;
    open(my $ifh, "<", $file) or die($ERRNO);
    @lines = <$ifh>;
    close $ifh;

    #open(my $ofh, ">", 'bla') or die($ERRNO);
    open(my $ofh, ">", $file) or die($ERRNO);
    while(scalar @lines) {
        my $line = shift @lines;
        my ($subname, $args);
        if($line =~ /[^\#]*sub\ (.*)\ \{/) {
            $subname = $1;
        } else {
            print $ofh $line;
            next;
        }
        if($lines[0] =~ /[^\#]*my\ .*?\((.*)\).*\@\_/) {
            $args = $1;
        } elsif($lines[0] =~ /[^\#]*my\ \(*(.*?)\)*\ *\=\ *shift(\ *\@\_)*/) {
            $args = $1;
            print "-------------- SHIFT ARG!!! ---------------\n";
            print "     $args\n";
        } else {
            print "#### Sub $subname has no args\n";
            print $ofh $line;
            next;
        }

        $subname =~ s/^\ +//g;
        $subname =~ s/\ +$//g;
        $args =~ s/^\ +//g;
        $args =~ s/\ +$//g;

        my $temp = shift @lines;
        my $newsub = 'sub ' . $subname . '(' . $args . ') {' . "\n";
        print $newsub;
        print $ofh $newsub;

        lookForOptionals($file, $subname, $args, @lines);
    }
    close $ofh;
}

close $optfh;
print "Done.\n";
exit(0);

sub lookForOptionals($file, $subname, $arglist, @lines) {
    my @sublines = getSublines(@lines);
    my @args = getArgs($arglist);

    foreach my $arg (@args) {
        foreach my $line (@sublines) {
            my $matcharg = 'defined\(\ *\\' . $arg . '\ *\)';
            if($line =~ /$matcharg/) {
                my $key = join('___', $file, $subname, $arg);
                if(!defined($knownoptionals{$key})) {
                    $knownoptionals{$key} = 1;
                    print "$file / $subname: Optional argument $arg\n";
                    print $optfh "$file / $subname: Optional argument $arg\n";
                }
            }
        }
    }

    return;
}

sub getSublines(@lines) {
    my $count = 1;

    my @sublines;

    for(my $i = 0; $i < scalar @lines; $i++) {
        my $line = $lines[$i];
        push @sublines, $line;
        $count += getBraceCount($line);
        last unless($count);
    }

    return @sublines;
}

sub getBraceCount($line) {
    my $count = 0;
    my @parts = split//, $line;
    foreach my $part (@parts) {
        if($part eq '{') {
            $count++;
        } elsif($part eq '}') {
            $count--;
        }
    }
    return $count;
}

sub getArgs($arglist) {
    my @args = split/\,/, $arglist;

    for(my $i = 0; $i < scalar @args; $i++) {
        $args[$i] =~ s/^\ +//;
        $args[$i] =~ s/\ +$//;
    }
    return @args;
}

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
