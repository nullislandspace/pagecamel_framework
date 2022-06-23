package PageCamel::Web::TT::Translate;
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
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

# WARNING: Template-Toolkit seems to have a special problem with Perl::Critic,
# disable this one check for this file
## no critic (BuiltinHomonyms)

use PageCamel::Helpers::Translator;
use HTML::Entities;
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::Strings;

use base qw(Template::Plugin);

use Template::Plugin;
use Template::Exception;

sub load($class, $context) {
    my $self = bless {
    }, $class;

    return $self;
}

sub new($self, $context) {
    return $self;
}

sub tr($self, $data) {

    return $data if($data eq '');

    my $lang = $self->getLang;
    my $trans = tr_translate($lang, $data);

    return $trans;
}

sub quote($self, $data) {

    my $quoted = encode_entities($data, "'<>&\"\n");
    $quoted =~ s/ä/&auml;/;
    $quoted =~ s/ö/&ouml;/;
    $quoted =~ s/ü/&uuml;/;
    $quoted =~ s/Ä/&Auml;/;
    $quoted =~ s/Ö/&Ouml;/;
    $quoted =~ s/Ü/&Uuml;/;
    $quoted =~ s/ß/&szlig;/;

    return $quoted;
}

sub trquote($self, $data) {

    return $self->quote($self->tr($data));
}

sub fixdate($self, $data) {

    return $self->quote(fixDateField($data));
}

sub elemNameQuote($self, $data) {
    return $self->quote(PageCamel::Helpers::Strings::elemNameQuote($data));
}

BEGIN {
    my $x_lang;

    sub setLang($unused, $newlang) {
        $x_lang = $newlang;
        return;
    }

    sub getLang {
        return $x_lang;
    }
}


1;
__END__

=head1 NAME

PageCamel::Web::TT::Translate -

=head1 SYNOPSIS

  use PageCamel::Web::TT::Translate;



=head1 DESCRIPTION



=head2 load



=head2 new



=head2 tr



=head2 quote



=head2 trquote



=head2 fixdate



=head2 elemNameQuote



=head2 setLang



=head2 getLang



=head1 IMPORTANT NOTE

This module is part of the PageCamel framework. Currently, only limited support
and documentation exists outside my DarkPAN repositories. This source is
currently only provided for your reference and usage in other projects (just
copy&paste what you need, see license terms below).

To see PageCamel in action and for news about the project,
visit my blog at L<https://cavac.at>.

=head1 AUTHOR

Rene Schickbauer, E<lt>pagecamel@cavac.atE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
