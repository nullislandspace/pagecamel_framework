package PageCamel::Helpers::UTF;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
use Data::Dumper;
#---AUTOPRAGMAEND---

#use Encode qw(is_utf8 encode_utf8 decode_utf8);
use Encode qw(encode decode);

use base qw(Exporter);
use PageCamel::Helpers::Padding qw(doSpacePad);
our @EXPORT = qw(encode_utf8 decode_utf8 encode_utf16 decode_utf16 is_utf8);

sub encode_utf8 {
    my ($orig) = @_;

    return encode('UTF-8', $orig);
}

sub decode_utf8 {
    my ($orig) = @_;

    return decode('UTF-8', $orig);
}

sub encode_utf16 {
    my ($orig) = @_;

    return encode('UTF-16', $orig);
}

sub decode_utf16 {
    my ($orig) = @_;

    return decode('UTF-16', $orig);
}

sub is_utf8 {
    my ($orig) = @_;

    return Encode->is_utf8($orig);
}



1;
__END__


=head1 AUTHOR

Rene Schickbauer, E<lt>cavac@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
