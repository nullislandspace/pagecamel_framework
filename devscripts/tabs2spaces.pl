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
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---



print "Searching files...\n";
my @files = (find_files('lib'), find_files('devscripts'));

print "Changing files:\n";
foreach my $file (@files) {
    print "Fixing $file...\n";
    open(my $ifh, '<', $file) or croak($ERRNO);
    my @lines = <$ifh>;
    close $ifh;
    open(my $ofh, '>', $file);
    foreach my $line (@lines) {
        chomp $line;
        $line =~ s/\t/    /g;
        print $ofh "$line\n";
    }
    close $ofh;
}
print "Done.\n";
exit(0);



sub find_files {
    my ($workDir) = @_;

    my @files;
    opendir(my $dfh, $workDir) or die($ERRNO);
    while((my $fname = readdir($dfh))) {
        next if($fname eq "." || $fname eq ".." || $fname eq ".hg");
        $fname = $workDir . "/" . $fname;
        if(-d $fname) {
            push @files, find_files($fname);
        } elsif($fname =~ /\.(p[lm]|tt|xml)$/i && -f $fname) {
            push @files, $fname;
        }
    }
    closedir($dfh);
    return @files;
}
