package PageCamel::Helpers::UTF;
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
#---AUTOPRAGMAEND---

use Encode qw(encode decode);

use base qw(Exporter);
use PageCamel::Helpers::Padding qw(doSpacePad);
our @EXPORT = qw(encode_utf8 decode_utf8 encode_utf8_array decode_utf8_array encode_utf16 decode_utf16 is_utf8); ## no critic (Modules::ProhibitAutomaticExportation)

sub encode_utf8($orig) {
    return encode('UTF-8', $orig);
}

sub decode_utf8($orig) {
    return decode('UTF-8', $orig);
}

sub encode_utf8_array {
    my @orig = @_;
    my @newarray;

    foreach my $val (@orig) {
        push @newarray, encode('UTF-8', $val);
    }

    return @newarray;
}

sub decode_utf8_array {
    my @orig = @_;
    my @newarray;

    foreach my $val (@orig) {
        push @newarray, decode('UTF-8', $val);
    }

    return @newarray;
}


sub encode_utf16($orig) {
    return encode('UTF-16', $orig);
}

sub decode_utf16($orig) {
    return decode('UTF-16', $orig);
}

sub is_utf8($orig) {
    return Encode::is_utf8($orig);
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
