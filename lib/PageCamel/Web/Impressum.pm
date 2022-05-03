package PageCamel::Web::Impressum;
#---AUTOPRAGMASTART---
use 5.032;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.0;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
use feature 'signatures';
no warnings qw(experimental::signatures);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub reload {
    my ($self) = shift;
   #
    # make sure the relevant system settings exist
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    $sysh->createBool(modulename => $self->{modname},
                        settingname => 'impressum_enable',
                        settingvalue => 0,
                        description => 'Enable impressum',
                        processinghints => [
                            'type=switch',
                                            ])
            or croak("Failed to create setting impressum_enable!");

    $sysh->createText(modulename => $self->{modname},
                        settingname => 'impressum_html',
                        settingvalue => '<p>Not yet defined</p>',
                        description => 'HTML text for impressum',
                        processinghints => [
                            "type=textarea",
                                            ])
            or croak("Failed to create setting impressum_html!");
   
    return;
}

sub register {
    my ($self) = @_;
    $self->register_webpath($self->{webpath}, "get");
    $self->register_prerender("prerender");

    if(defined($self->{sitemap}) && $self->{sitemap}) {
        $self->register_sitemap('sitemap');
    }

    return;
}

sub crossregister {
    my ($self) = @_;

    $self->register_public_url($self->{webpath});
    return;
}



sub get {
    my ($self, $ua) = @_;

    my %sets;
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    foreach my $key (qw[impressum_enable impressum_html]) {
        my ($ok, $data) = $sysh->get($self->{modname}, $key);
        if($ok) {
            $sets{$key} = $data->{settingvalue};
        }
    }

    if(!defined($sets{impressum_enable}) || !$sets{impressum_enable}) {
        return (status => 404);
    }

    my $th = $self->{server}->{modules}->{templates};

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        ImpressumHTML => $sets{impressum_html},
        showads => $self->{showads},
    );

    my $template = $self->{server}->{modules}->{templates}->get('impressum', 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => 'text/html',
            data    => $template,
            expires         => $self->{expires},
            cache_control   =>  $self->{cache_control},
            );
}

sub prerender {
    my ($self, $webdata) = @_;

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    my ($ok, $data) = $sysh->get($self->{modname}, 'impressum_enable');
    if($ok && $data->{settingvalue}) {
        $webdata->{ImpressumURL} = $self->{webpath}
    } else {
        $webdata->{ImpressumURL} = '';
    }
    return;
}

sub sitemap {
    my ($self, $sitemap) = @_;

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    my ($ok, $data) = $sysh->get($self->{modname}, 'impressum_enable');
    if($ok && $data->{settingvalue}) {
        push @{$sitemap}, $self->{webpath};
    }

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

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
