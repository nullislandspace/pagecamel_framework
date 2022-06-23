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


updateClass('lib/PageCamel/Worker.pm', 'lib/PageCamel/Worker', 'PageCamel::Worker::');
updateClass('lib/PageCamel/WebBase.pm', 'lib/PageCamel/Web', 'PageCamel::Web::');
updateClass('lib/PageCamel/Helpers.pm', 'lib/PageCamel/Helpers', 'PageCamel::Helpers::');
print "Done\n";


sub updateClass($filename, $dirname, $basename) {

    print "updating $filename with $basename classes from $dirname\n";

    my @files = findModules($dirname, $basename);

    my @lines;
    open(my $ifh, "<", $filename) or die($ERRNO . ": $filename");
    @lines = <$ifh>;
    close($ifh);

    
    my $start = 0;
    my $end = 0;

    open(my $ofh, ">", $filename) or die($ERRNO);
    foreach my $line (@lines) {
        if(!$start || $end) {
            print $ofh $line;
        }
        if($line =~ /^\#\=\!\=START\-AUTO\-INCLUDES/o) {
            $start = 1;
            foreach my $newline (sort @files) {
                print $ofh 'use ' . $newline . ";\n";
                print 'use ' . $newline . ";\n";
            }
        } elsif($line =~ /^\#\=\!\=END\-AUTO\-INCLUDES/o) {
            print $ofh $line;
            $end = 1;
        }
    }
    close($ofh);
}

sub findModules($dirname, $basename) {

    my @files;

    opendir(my $dfh, $dirname) or die($ERRNO);
    while((my $fname = readdir($dfh))) {
        next if($fname =~ /^\./);

    my $fullname = $dirname . '/' . $fname;
    if(-d $fullname) {
        push @files, findModules($fullname, $basename . $fname . '::');
        next;
    } elsif($fname !~ /\.pm$/) {
        next;
    }
    $fname = $basename . $fname;
    $fname =~ s/\.pm$//g;
        push @files, $fname;
    }
    closedir($dfh);

    return @files;

}
