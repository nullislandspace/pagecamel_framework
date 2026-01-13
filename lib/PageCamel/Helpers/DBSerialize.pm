package PageCamel::Helpers::DBSerialize;
#---AUTOPRAGMASTART---
use v5.40;
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

# Serialize/deserialize complex data structures in a way compatible to a
# postgres TEXT field (achieved through Storable and Base64 encoding)

use base qw(Exporter);
our @EXPORT = qw(dbfreeze dbthaw dbderef); ## no critic (Modules::ProhibitAutomaticExportation)

use YAML::Syck;

sub dbfreeze($data) {
    if(!defined($data)) {
        croak('$data is undefined in dbfreeze');
    } elsif(ref($data) eq "REF") {
        return Dump($data);
    } else {
        return Dump(\$data);
    }

}

sub dbthaw($data) {
    return Load($data);
}

sub dbderef($val) {
    return if(!defined($val));

    while(ref($val) eq "SCALAR" || ref($val) eq "REF") {
        $val = ${$val};
        last if(!defined($val));
    }

    return $val;
}

1;
__END__

=head1 NAME

PageCamel::Helpers::DBSerialize - serialize data structure to use in PostgreSQL text fields

=head1 SYNOPSIS

  use PageCamel::Helpers::DBSerialize;

=head1 DESCRIPTION

This module helps in using PostgreSQL text fields to store arbitrary Perl data structures.

=head2 dbfreeze

Turn a data structure into a string.

=head2 dbthaw

Reverse the process.

=head2 dbderef

Dereference a structure as much as possible.

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
