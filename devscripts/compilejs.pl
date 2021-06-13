#!/usr/bin/env perl
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.6;
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

unlink($BASE . "jquery.compiled.js");
unlink($BASE . "jquery.compiled-min.js");
print "### Compiling ###\n";
foreach my $file (@files) {
    chomp $file;
    next if($file =~ /^\#/);
    if(!-f $BASE . $file) {
        die("File $file not found!");
    }
    my $cmd = "cat " . $BASE . $file . " >> " . $BASE . "jquery.compiled.js";
    print "$cmd\n";
    my @ret = `$cmd`;
    print @ret;
    $cmd = "echo >> " . $BASE . "compiled.js";
}
print "### Minifying ###\n";
open(my $ifh, "<", $BASE . "jquery.compiled.js") or die($ERRNO);
open(my $ofh, ">", $BASE . "jquery.compiled-min.js") or die($ERRNO);

minify(input => *$ifh, outfile => *$ofh);

close $ifh;
close $ofh;
print "Done.\n";
unlink($BASE . "jquery.compiled.js");

print "For development, use the following lines:\n";
foreach my $file (@files) {
    next if($file =~ /^\#/);
    print "<script type=\"text/javascript\" src=\"/static/" . $file . "[% URLReloadPostfix %]\"></script>\n";
}

__DATA__
ajaxhelpers.js
formhelpers.js
unicodehelpers.js
pageviewstats.js
codehighlight/highlight.pack.js
jquery/js/jquery-3.4.1.js
jquery/js/jquery-migrate-3.1.0.min.js
jquery/js/jquery-ui.min.js
jquery/js/jquery.metadata.js
jquery/js/jquery.statictable.js
jquery/js/jquery.form.js
jquery/js/jquery.dataTables.js
jquery/js/datatables.js
jquery/js/jquery.dataTables.plugins.js
jquery/js/jquery.dataTables.sortplugin.js
jquery/js/jquery.dataTables.filterplugin.js
#jquery/js/jquery.dataTables.filterdelay.js
jquery/js/jquery.checkify.js
jquery/js/jquery.cavacnote.js
jquery/js/jquery.cavacnote_mobile.js
jquery/js/jquery.gotobutton.js
jquery/js/jquery.sparkline.js
jquery/js/jquery.sha1.js
jquery/js/jquery.hashmask.js
jquery/js/jquery.tmpl.js
jquery/js/jquery.iframe-transport.js
jquery/js/jquery.spritely-0.6.8.js
# jquery/js/jquery.CKEditor.pack.js DON'T COMPILE CKEDITOR IN, THIS NEEDS EXCEMPTIONS FOR THE CSP
jquery/js/jquery.json-2.3.js
jquery/js/jquery.websocket-pagecamel.js
jquery/js/jquery.complexify.banlist.js
jquery/js/jquery.complexify.js
jquery/js/jquery.blockUI.js
jquery/js/jquery.datetimepicker.js
jquery/js/dropdownmenu.js
jquery/js/jquery.insertatcaret.js
jquery/js/jquery.xeyes-2.0.js
jquery/js/jquery.transit.min.0.9.12.js
jquery/js/jquery.cursortrails.js
jquery/js/jquery.timepicker.js
jquery/js/three.js
jquery/js/cavaclogo.js
jquery/js/select2.full.js
jquery/js/js.cookie.js
Chart.bundle.js
