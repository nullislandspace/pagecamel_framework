#!/usr/bin/env perl
#---AUTOPRAGMASTART---
use v5.42;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 5.0;
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license

print "Searching files...\n";
my @files = (find_pm('lib'));

print "Changing files:\n";
foreach my $file (@files) {
	print "Editing $file...\n";

	my @lines;
	open(my $ifh, "<", $file) or die($ERRNO);
	@lines = <$ifh>;
	close $ifh;

	open(my $ofh, ">", $file) or die($ERRNO);
	foreach my $line (@lines) {
        #$line =~ s/VERSION = \d\.\d+/VERSION = $newversion/g;
        $line =~ s/\$ua\-\>request_method\(\)/\$ua->{method}/g;
        $line =~ s/\$ua\-\>user_agent\(\)/\$ua->{headers}->{'User-Agent'}/g;
        $line =~ s/\$ua\-\>referer\(\)/\$ua->{headers}->{Referer}/g;
        if($line =~ /ua\-\>http/) {
            $line =~ s/ua\-\>http\(\"([^\"]+)\"\)/ua->{headers}->{\"$1\"}/g;
            $line =~ s/ua\-\>http\(\'([^\"]+)\'\)/ua->{headers}->{\'$1\'}/g;
            $line =~ s/\$ua\-\>http\(\)/sort keys \%{\$ua->{headers}}/g;
        }
		print $ofh $line;
	}
	close $ofh;
}
print "Done.\n";
exit(0);



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
