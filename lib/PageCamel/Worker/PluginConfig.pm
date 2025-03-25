package PageCamel::Worker::PluginConfig;
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

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    #$self->pluginConfig();

    return $self;
}

sub crossregister($self) {
    
    if(defined($self->{templates})) {
        # Configure an additional path in the TemplateCache module
        my $tch = $self->{server}->{modules}->{$self->{templates}->{templatecache}};
        $tch->addView($self->{templates}->{path}, $self->{templates}->{base});
    }

    if(defined($self->{staticfiles})) {
        # Configure an additional path in the StaticCache module
        my $sch = $self->{server}->{modules}->{$self->{staticfiles}->{staticcache}};
        foreach my $view (@{$self->{staticfiles}->{view}}) {
            $sch->addView($view->{path}, $view->{base});
        }
    }


    return;
}


1;
__END__

=head1 NAME

PageCamel::Worker::PluginConfig -

=head1 SYNOPSIS

  use PageCamel::Worker::PluginConfig;



=head1 DESCRIPTION



=head2 new



=head2 crossregister



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
