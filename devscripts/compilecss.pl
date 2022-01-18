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

use CSS::Minifier::XS qw(minify);
use PageCamel::Helpers::FileSlurp qw(slurpBinFile writeBinFile);

my $BASE = "./lib/PageCamel/Web/Static/";

my @files = <DATA>;

#my @themes = qw[classic blacksilk bluegreen corporateugliness orange recycled];
my @themes = qw[blacksilk bluegreen classic corporateugliness orange recycled darkknight space];

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
            die("File $filex not found!");
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
jquery/css/themes/XXUIThemeNameXX/dropdownmenu_top.css
jquery/css/themes/XXUIThemeNameXX/dropdownmenu_side.css
jquery/css/themes/XXUIThemeNameXX/select2.css
pagecameldefaultlayout.css
codehighlight/styles/sunburst.css
jquery/css/datatables.css
jquery/css/jquery.datetimepicker.css
jquery/css/jquery.timepicker.css
jquery/css/pwprogressbar.css
jquery/css/cursortrails.css
jquery/css/themes/XXUIThemeNameXX/pagecamelcustom.css
