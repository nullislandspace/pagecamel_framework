package PageCamel::Web::StaticPage;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.2;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    if(!defined($self->{usermasterlayout})) {
        $self->{usermasterlayout} = 1;
    }

    return $self;
}

sub reload {
    my ($self) = shift;
    # Nothing to do.. in here, we only use the template and database module
    return;
}

sub register {
    my ($self) = @_;
    $self->register_webpath($self->{webpath}, "get");

    if(defined($self->{sitemap}) && $self->{sitemap}) {
        $self->register_sitemap('sitemap');
    }

    return;
}

sub crossregister {
    my ($self) = @_;

    if(defined($self->{public}) && $self->{public} == 1) {
        $self->register_public_url($self->{webpath});
    }
}



sub get {
    my ($self, $ua) = @_;

    my $th = $self->{server}->{modules}->{templates};

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
    );

    my $template = $self->{server}->{modules}->{templates}->get($self->{templatename}, $self->{usemasterlayout}, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => $self->{type},
            data    => $template,
            expires         => $self->{expires},
            cache_control   =>  $self->{cache_control},
            );
}

sub sitemap {
    my ($self, $sitemap) = @_;

    push @{$sitemap}, $self->{webpath};

    return;
}

1;
__END__

=head1 NAME

PageCamel::Web::StaticPage -

=head1 SYNOPSIS

  use PageCamel::Web::StaticPage;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 get



=head2 sitemap



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

Copyright (C) 2008-2016 by Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
