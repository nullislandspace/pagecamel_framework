package PageCamel::Worker::TemplateCache;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.6;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule PageCamel::Helpers::TemplateEngine::Main);

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{uninlineJavascript} = 0;
    $self->{preventCSS} = 0;
    $self->{prerenderCallback} = 0;

    if(!defined($self->{reporting})) {
        croak($self->{modname} . " requires reporting config");
    }

    $self->init();

    return $self;
}

sub reload($self, $ofh = undef) {
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    return $self->reloadFiles($reph);
}

sub finalcheck($self) {
    return $self->runFinalcheck();
}

1;
__END__

=head1 NAME

PageCamel::Worker::TemplateCache -

=head1 SYNOPSIS

  use PageCamel::Worker::TemplateCache;



=head1 DESCRIPTION



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
