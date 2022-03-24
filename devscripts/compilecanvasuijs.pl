#!/usr/bin/env perl
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.0;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---
# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license


use JavaScript::Minifier qw(minify);

my $BASE = "./lib/PageCamel/Web/Static/";

my @files = <DATA>;

unlink($BASE . "canvasuijs.compiled.js");
unlink($BASE . "canvasuijs.compiled-min.js");
print "### Compiling ###\n";
foreach my $file (@files) {
    chomp $file;
    next if($file =~ /^\#/);
    if(!-f $BASE . $file) {
        die("File $file not found!");
    }
    my $cmd = "cat " . $BASE . $file . " >> " . $BASE . "canvasuijs.compiled.js";
    print "$cmd\n";
    my @ret = `$cmd`;
    print @ret;
}
print "### Minifying ###\n";
open(my $ifh, "<", $BASE . "canvasuijs.compiled.js") or die($ERRNO);
open(my $ofh, ">", $BASE . "canvasuijs.compiled-min.js") or die($ERRNO);

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
canvasuijs/uiview.js
canvasuijs/uitext.js
canvasuijs/uibutton.js
canvasuijs/canvashelpers.js
canvasuijs/uiline.js
canvasuijs/uilist.js
canvasuijs/uinumpad.js
canvasuijs/uiarrowbutton.js
canvasuijs/uitextbox.js
canvasuijs/uipaylist.js
canvasuijs/uilistitem.js
canvasuijs/uidragndrop.js
canvasuijs/uitableplan.js
canvasuijs/uicircle.js
