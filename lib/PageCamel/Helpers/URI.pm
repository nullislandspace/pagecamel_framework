package PageCamel::Helpers::URI;
#---AUTOPRAGMASTART---
use 5.032;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
use feature 'signatures';
no warnings qw(experimental::signatures);
#---AUTOPRAGMAEND---


use base qw(Exporter);
use PageCamel::Helpers::Padding qw(doFPad);
our @EXPORT_OK = qw(decode_uri decode_uri_part decode_uri_path encode_uri encode_uri_part encode_uri_path);

sub encode_uri {
    my ($orig) = @_;

    my @oparts = split/\//, $orig;
    my @eparts;
    foreach my $opart (@oparts) {
        push @eparts, encode_uri_part($opart);
    }

    return join('/', @eparts);
}

sub encode_uri_part {
    my ($orig) = @_;

    my $encoded = '';

    my @parts = split//, $orig;
    foreach my $part (@parts) {
        if($part =~ /^[a-zA-Z0-9\/\:\~]/) {
            $encoded .= $part;
        }elsif($part eq ' ') {
            $encoded .= '+';
        } else {
            $encoded .= '%' . uc(doFPad(sprintf("%x", ord($part)), 2));
        }
    }

    return $encoded;
}

sub encode_uri_path {
    my ($orig) = @_;

    my $encoded = '';

    my @parts = split//, $orig;
    foreach my $part (@parts) {
        if($part =~ /^[a-zA-Z0-9\/\:\~]/) {
            $encoded .= $part;
        }elsif($part eq ' ') {
            $encoded .= '%20';
        } else {
            $encoded .= '%' . uc(doFPad(sprintf("%x", ord($part)), 2));
        }
    }

    return $encoded;
}

sub decode_uri {
    my ($orig) = @_;

    my @oparts = split/\//, $orig;
    my @dparts;
    foreach my $opart (@oparts) {
        push @dparts, decode_uri_part($opart);
    }

    return join('/', @dparts);
}

sub decode_uri_part {
    my ($orig) = @_;

    my $decoded = '';
    return $decoded unless defined($orig);
    my @parts = split//, $orig;
    while(scalar @parts) {
        my $part = shift @parts;
        if($part eq '+') {
            $decoded .= ' ';
        } elsif($part eq '%') {
            $decoded .= chr(hex(shift @parts) * 16 + hex(shift @parts));
        } else {
            $decoded .= $part;
        }
    }

    return $decoded;
}

# This is similar to decode_uri_part, but treats the plus sign literally instead of as space
sub decode_uri_path {
    my ($orig) = @_;

    my $decoded = '';
    return $decoded unless defined($orig);
    my @parts = split//, $orig;
    while(scalar @parts) {
        my $part = shift @parts;
        if($part eq '%') {
            $decoded .= chr(hex(shift @parts) * 16 + hex(shift @parts));
        } else {
            $decoded .= $part;
        }
    }

    return $decoded;
}

1;
__END__

=head1 NAME

PageCamel::Helpers::URI - URI encoders/decoders

=head1 SYNOPSIS

  use PageCamel::Helpers::URI;



=head1 DESCRIPTION

This helper module provides functions to encode and decode URIs

=head2 encode_uri

Encode a string into an URI.

=head2 encode_uri_part

Encode a string into an URI part.

=head2 decode_uri

Decode an URI.

=head2 decode_uri_part

Decode an URI part.

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
