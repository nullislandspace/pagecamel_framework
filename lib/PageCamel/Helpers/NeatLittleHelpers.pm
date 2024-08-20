package PageCamel::Helpers::NeatLittleHelpers;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.5;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(Exporter);
our @EXPORT_OK = qw(arraytohashkeys hashcountfromarray);
use File::Binary;

# Note: Usually you shouldn't use that functions but copy the small pieces of code inline to where
# you need it.
#
# This module is mostly my notepad for neat little Perl tricks to speed up some
# stuff

# Get unique elements of array as hash keys
sub arraytohashkeys(@in) {

    my %out = map {$_=>1} @in;

    return %out;
}

# count how many times each unique element exists in array, return
# as hash
sub hashcountfromarray(@in) {

    my %out;
    $out{$_}++ for (@in);

    return %out;
}
1;
__END__

=head1 NAME

PageCamel::Helpers::NeatLittleHelpers - various helpers that don't fit into other Helper modules

=head1 SYNOPSIS

  use PageCamel::Helpers::NeatLittleHelpers;

=head1 DESCRIPTION

This module holds a mishmash of functions that (currently) don't fit other Helper modules.

=head2 arraytohashkeys

Get a hash with all unique elements of an array.

=head2 hashcountfromarray

Get the counts of each unique element in an array as hash.

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
