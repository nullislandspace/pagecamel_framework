#!/usr/bin/env perl
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.2;
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

use CSS::Minifier::XS qw(minify);
use PageCamel::Helpers::FileSlurp qw(slurpBinFile writeBinFile);

my $BASE = "./lib/PageCamel/Web/Static/";

my @files = <DATA>;

my @themes = qw[blacksilk bluegreen classic corporateugliness orange recycled space darkmode polished];

foreach my $theme (@themes) {
    unlink($BASE . "jquery.compiled_" . $theme . ".css");
    unlink($BASE . "jquery.compiled-min_" . $theme . ".css");
    print "### Compiling for theme $theme ###\n";
    foreach my $file (@files) {
        chomp $file;
        next if($file =~ /^\#/);

        my $filex = $file . ''; # Force copy
        $filex =~ s/XXUIThemeNameXX/$theme/g;

        if(!-f $BASE . $filex) {
            croak("File $filex not found!");
            next;
        }
        my $cmd = "cat " . $BASE . $filex . " >> " . $BASE . "jquery.compiled_" . $theme . ".css";
        print "$cmd\n";
        my @ret = `$cmd`;
        print @ret;
    }
    print "### Minifying ###\n";
    my $indata = slurpBinFile($BASE . "jquery.compiled_" . $theme . ".css");
    unlink($BASE . "jquery.compiled_" . $theme . ".css");
    
    # Remove CSS comments (minify doesn't do that!)
    $indata =~ s/\/\*.+?\*\///gs;

    my $outdata = minify($indata);
    writeBinFile($BASE . "jquery.compiled-min_" . $theme . ".css", $outdata);

    print "Done.\n";
}

print "For development, use the following lines:\n";
foreach my $file (@files) {
    next if($file =~ /^\#/);
    my $line = "<link REL=\"stylesheet\" TYPE=\"text/css\" href=\"/static/" . $file . "[% URLReloadPostfix %]\"></link>\n";
    $line =~ s/XXUIThemeNameXX/[% UIThemeName %]/g;
    print $line;
}

__DATA__
jquery/css/themes/XXUIThemeNameXX/jquery-ui.css
jquery/css/themes/XXUIThemeNameXX/jquery-ui.structure.css
jquery/css/themes/XXUIThemeNameXX/jquery-ui.theme.css
jquery/css/themes/XXUIThemeNameXX/select2.css
jquery/css/themes/BASECSS/select2.css
jquery/css/themes/XXUIThemeNameXX/jquery.datetimepicker.css
jquery/css/themes/BASECSS/jquery.datetimepicker.css
pagecameldefaultlayout.css
codehighlight/styles/sunburst.css
jquery/css/themes/XXUIThemeNameXX/datatables.css
jquery/css/datatables.css
jquery/css/jquery.timepicker.css
jquery/css/pwprogressbar.css
jquery/css/cursortrails.css
jquery/css/jquery.jqplot.css
jquery/css/themes/XXUIThemeNameXX/pagecamelcustom.css
jquery/css/themes/BASECSS/pagecamelcustom.css
jquery/css/themes/XXUIThemeNameXX/menubars.css
jquery/css/themes/BASECSS/menubars.css
