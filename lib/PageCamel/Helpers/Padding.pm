package PageCamel::Helpers::Padding;
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


use base qw(Exporter);
our @EXPORT_OK = qw(doFPad doSpacePad trim doLeftSpacePad);


sub doFPad {
    my ($val, $len) = @_;
    if(!defined($val) || !defined($len)) {
        print STDERR "ERROR: Undefined variable!\n";
    }
    while(length($val) < $len) {
        $val = "0$val";
    }
    return $val;
}

sub doSpacePad {
    my ($val, $len) = @_;
    while(length($val) < $len) {
        $val = "$val ";
    }
    return $val;
}

sub doLeftSpacePad {
    my ($val, $len) = @_;
    while(length($val) < $len) {
        $val = " $val";
    }
    return $val;
}

sub trim
{
    my $string = shift;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
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

=head2 trim

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

Copyright (C) 2008-2016 by Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
