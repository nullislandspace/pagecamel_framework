#!/usr/bin/env perl
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---
# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license


use JavaScript::Minifier qw(minify);

my $BASE = "./lib/PageCamel/Web/Static/";

my @files = <DATA>;

unlink($BASE . "canvasjs.compiled.js");
unlink($BASE . "canvasjs.compiled-min.js");
print "### Compiling ###\n";
foreach my $file (@files) {
    chomp $file;
    next if($file =~ /^\#/);
    if(!-f $BASE . $file) {
        die("File $file not found!");
    }
    my $cmd = "cat " . $BASE . $file . " >> " . $BASE . "canvasjs.compiled.js";
    print "$cmd\n";
    my @ret = `$cmd`;
    print @ret;
}
print "### Minifying ###\n";
open(my $ifh, "<", $BASE . "canvasjs.compiled.js") or die($ERRNO);
open(my $ofh, ">", $BASE . "canvasjs.compiled-min.js") or die($ERRNO);

minify(input => *$ifh, outfile => *$ofh);

close $ifh;
close $ofh;
print "Done.\n";
unlink($BASE . "canvasjs.compiled.js");

print "For development, use the following lines:\n";
foreach my $file (@files) {
    next if($file =~ /^\#/);
    print "<script type=\"text/javascript\" src=\"/static/" . $file . "[% URLReloadPostfix %]\"></script>\n";
}

__DATA__
canvasjs/canvashelpers.js
canvasjs/canvasbuttons.js
canvasjs/canvas7segment.js
canvasjs/canvasitemlist.js
canvasjs/canvastouchitemlist.js
