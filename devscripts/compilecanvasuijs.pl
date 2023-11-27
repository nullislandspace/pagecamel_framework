#!/usr/bin/env perl
#---AUTOPRAGMASTART---
use v5.38;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.3;
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

binmode STDOUT, ':utf8';

use JavaScript::Minifier qw(minify);

my $BASE = "./lib/PageCamel/Web/Static/";

my @files = <DATA>;

my $tmpfile = '/tmp/canvasuijs.compiled.js';
my $minified = './lib/PageCamel/Web/Templates/canvasuijs.js.tt';
unlink($tmpfile);
unlink($minified);

print "### Compiling ###\n";
open(my $ofh, '>:encoding(utf-8)', $tmpfile) or croak("$ERRNO");
foreach my $file (@files) {
    chomp $file;
    next if($file =~ /^\#/);
    my $fname = $BASE . $file;
    if(!-f $fname) {
        die("File $fname not found!");
    }

    open(my $ifh, '<:encoding(utf-8)', $fname) or croak("$ERRNO");
    while((my $line = <$ifh>)) {
        if($line =~ /\_trquote/) {
            #print "< ", $line;
            $line =~ s/\_trquote\((.+?)\)/\"\[\% tr.tr\($1\) \%\]\"/g;
            #print "> ", $line;
        }
        print $ofh $line;
    }
    close $ifh;
}
close $ofh;

print "### Minifying ###\n";
open(my $mifh, "<:encoding(utf-8)", $tmpfile) or die($ERRNO);
open(my $mofh, ">:encoding(utf-8)", $minified) or die($ERRNO);

minify(input => *$mifh, outfile => *$mofh);

close $mifh;
close $mofh;
print "Done.\n";

#`cp $tmpfile $minified`;
unlink($tmpfile);

print "For development, use the following lines:\n";
foreach my $file (@files) {
    next if($file =~ /^\#/);
    print "<script type=\"text/javascript\" src=\"/static/" . $file . "[% URLReloadPostfix %]\"></script>\n";
}

__DATA__
#canvasuijs/trhelper.js
canvasuijs/canvashelpers.js
canvasuijs/uiview.js
canvasuijs/uitextbox.js
canvasuijs/uitext.js
canvasuijs/uiline.js
canvasuijs/uilist.js
canvasuijs/uinumpad.js
canvasuijs/uiarrowbutton.js
canvasuijs/uibuttonrow.js
canvasuijs/uiscrolllist.js
canvasuijs/uilistitem.js
canvasuijs/uidragndrop.js
canvasuijs/uicircle.js
canvasuijs/uicolorpalet.js
canvasuijs/uiimage.js
canvasuijs/uicheckbox.js
canvasuijs/uitextinput.js
canvasuijs/uibutton.js
canvasuijs/uidialog.js
