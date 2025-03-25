package PageCamel::Helpers::Padding;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.7;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---


use base qw(Exporter);
our @EXPORT_OK = qw(doFPad doSpacePad trimLine doLeftSpacePad forceByteLength doCenterPad);


sub doFPad($val, $len) {
    if(!defined($val) || !defined($len)) {
        print STDERR "ERROR: Undefined variable!\n";
    }
    while(length($val) < $len) {
        $val = "0$val";
    }
    return $val;
}

sub doSpacePad($val, $len) {
    while(length($val) < $len) {
        $val = "$val ";
    }
    return $val;
}

sub doLeftSpacePad($val, $len) {
    while(length($val) < $len) {
        $val = " $val";
    }
    return $val;
}

sub doCenterPad($val, $len) {
    
    while(length($val) < $len) {
        $val = " $val";
        
        if(length($val) < $len) {
            $val .= ' ';
        }
    }
    
    return $val;
}

sub trimLine($string) {
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}

sub forceByteLength($string, $len) {
    
    if(length($string) > $len) {
        $string = substr $string, 0, $len;
    } else {
        while(length($string) < $len) {
          $string .= chr(0);
        }
    }
    
    return $string;
}


1;
__END__

=head1 NAME

PageCamel::Helpers::Padding - pad strings

=head1 SYNOPSIS

  use PageCamel::Helpers::Padding;

=head1 DESCRIPTION

Helper functions for string padding and trimming.

=head2 doFPad

Pad a string with leading zeroes to a specified length.

=head2 doSpacePad

Pad a string with trailing spaces to a specified length.

=head2 doLeftSpacePad

Pad a string with leading spaced to a specified length

=head2 trimLine

Trim leading and trailing whitespace off a string.

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
