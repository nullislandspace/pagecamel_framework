#!/usr/bin/env perl
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp;
our $VERSION = 2.4;
use autodie qw( close );
use Array::Contains;
use utf8;
#---AUTOPRAGMAEND---
# PAGECAMEL  (C) 2008-2019 Rene Schickbauer
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
