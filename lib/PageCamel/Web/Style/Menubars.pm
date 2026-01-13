package PageCamel::Web::Style::Menubars;
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

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::DBSerialize;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my @menubars;
    my @menubarnames;
    foreach my $key (sort keys %{$self->{view}}) {
        my %menubar = %{$self->{view}->{$key}};
        $menubar{name} = $key;

        push @menubarnames, $menubar{menubar};
        push @menubars, \%menubar;
    }
    $self->{Menubars} = \@menubars;
    $self->{MenubarNames} = \@menubarnames;

    return $self;
}

sub reload($self) {
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    $sysh->createEnum(modulename => $self->{modname},
                        settingname => "default_menubar",
                        settingvalue => $self->{default_menubar},
                        description => 'Default Menubar',
                        enum_values => $self->{MenubarNames},
                        processinghints => [
                        'type=dropdown',
        ])
        or croak("Failed to create setting default_menubar!");

    return;
}

sub register($self) {
    $self->register_webpath($self->{webpath}, "get");
    $self->register_prerender("prerender");
    return;
}

sub get($self, $ua) {
    my $webpath = $ua->{url};
    my $seth = $self->{server}->{modules}->{$self->{usersettings}};

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{pagetitle},
        webpath         =>  $self->{webpath},
        AvailMenubars     =>  $self->{Menubars},
        showads => $self->{showads},
    );

    # We don't actually set the Menubar into webdata here, this is done during the prerender stage.
    # Also, we don't handle the "select a default menubar if non set" case, TemplateCache falls back to
    # its own default menubar anyway
    my $mode = $ua->{postparams}->{'mode'} || 'view';
    if($mode eq "setvalue") {
        my $menubar = $ua->{postparams}->{'menubar'} || "";
        if($menubar ne "") {
            $seth->set($webdata{userData}->{user}, "UserMenubar", \$menubar);
        }
    }


    my $template = $self->{server}->{modules}->{templates}->get("style/menubars", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub prerender($self, $webdata) {
    my $userMenubar = $self->{default_menubar};

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    {
        my ($ok, $data) = $sysh->get($self->{modname}, "default_menubar");
        if($ok) {
            $userMenubar = $data->{settingvalue};
        }
    }

    # Logged in user?
    if(defined($webdata->{userData}) &&
              defined($webdata->{userData}->{user}) &&
              $webdata->{userData}->{user} ne "") {
        my $seth = $self->{server}->{modules}->{$self->{usersettings}};
        {
            my ($uok, $tmpMenubar) = $seth->get($webdata->{userData}->{user}, "UserMenubar");
            if($uok && defined($tmpMenubar)) {
                my $dref = dbderef($tmpMenubar);

                # Check if menubar is still available
                foreach my $temp (@{$self->{Menubars}}) {
                    if($dref eq $temp->{menubar}) {
                        $userMenubar = $dref;
                        last;
                    }
                }
            }
        }
    }


    $webdata->{UIMenubarName} = $userMenubar;

    return;
}

1;
__END__

=head1 NAME

PageCamel::Web::Menubars -

=head1 SYNOPSIS

  use PageCamel::Web::Menubars;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 get



=head2 prerender


=head2 redirect_menubard_images



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
