package PageCamel::Helpers::CSVFilter;
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
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---


use PageCamel::Helpers::FileSlurp qw(slurpTextFile);


sub new($class, %config) {
    my $self = bless \%config, $class;
    return $self;
}

sub filter($self) {

    my (@headers, @headcount, @lines);

    $self->{logger}->debuglog("Loading input file");
    @lines = slurpTextFile($self->{source});

    my $filecount = 0;
    my $linecount = 0;

    $self->{logger}->debuglog("Parsing Header");
    my $header = shift @lines;
    chomp $header;
    @headers = split/;/, $header;
    for(my $i = 0; $i < $#headers; $i++) {
        $headcount[$i] = 0;
    }

    # First round... get count of used columns
    $self->{logger}->debuglog("Checking for empty columns");
    foreach my $line (@lines) {
        chomp $line;
        my @parts = split/;/o, $line;
        for(my $i = 0; $i < $#parts; $i++) {
            if(length($parts[$i]) > 0) {
                $headcount[$i]++;
            }
        }
    }

    # Second round... write out file
    $self->{logger}->debuglog("Writing Header");
    my $ofh;
    my $outline;
    foreach my $line(@lines) {
        if($linecount == 0) {
            my $ofname = $self->{destination};
            $filecount++;
            $ofname =~ s/#/$filecount/g;

            # Special filehandle handling (i most likely know what i'm doing here), don't use Perl::Critic on this one
            open($ofh, ">", $ofname) or croak($ERRNO); ## no critic (InputOutput::RequireBriefOpen)
            $self->{logger}->debuglog("Opening new output file $ofname");
            $outline = "";
            for(my $i = 0; $i < $#headers; $i++) {
                if($headcount[$i] > 0) {
                    $outline .= "=\"" . $headers[$i] . "\";";
                }
            }
            $self->{logger}->debuglog("Writing data");
            print $ofh "$outline\n";
        }
        $linecount++;

        chomp $line;
        my @parts = split/;/o, $line;
        $outline = "";
        for(my $i = 0; $i < $#headers; $i++) {
            if($headcount[$i] > 0) {
                if(!defined($parts[$i])) {
                    $parts[$i] = "";
                }
                # HACK! FIXME! All columns except the second (which is a date)
                # will be quotet as string
                if($i == 1) {
                    $outline .= "\"" . $parts[$i] . "\";";
                } else {
                    $outline .= "=\"" . $parts[$i] . "\";";
                }
            }
        }
        print $ofh "$outline\n";
    }
    $self->{logger}->debuglog("Closing output file");
    if(defined($ofh)) {
        close $ofh;
    }
    return;
}

1;
__END__

=head1 NAME

PageCamel::Helpers::CSVFilter - filter and quote CSV files

=head1 SYNOPSIS

  use PageCamel::Helpers::CSVFilter;


=head1 DESCRIPTION

This is a special case CSV filter that removes unused columns and quotes the entries. Pretty much unused
in newer stuff, but kept for backwards compatibility with legacy projects.

=head2 new

Create a new instance.

=head2 filter

Run the filter over the file.

=head1 IMPORTANT NOTE

This module is part of the PageCamel framework. Currently, only limited support
and documentation exists outside my DarkPAN repositories. This source is
currently only provided for your reference and usage in other projects (just
copy&paste what you need, see license terms below).

To see PageCamel in action and for news about the project,
visit my blog at L<https://cavac.at>.

=head1 AUTHOR

Rene Schickbauer, E<lt>cavac@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
