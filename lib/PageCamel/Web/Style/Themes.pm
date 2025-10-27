package PageCamel::Web::Style::Themes;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
use autodie qw( close );
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

    my @themes;
    my @themenames;
    foreach my $key (sort keys %{$self->{view}}) {
        my %theme = %{$self->{view}->{$key}};
        $theme{name} = $key;

        push @themenames, $theme{theme};
        push @themes, \%theme;
    }
    $self->{Themes} = \@themes;
    $self->{ThemeNames} = \@themenames;

    return $self;
}

sub reload($self) {
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    $sysh->createEnum(modulename => $self->{modname},
                        settingname => "default_theme",
                        settingvalue => $self->{default_theme},
                        description => 'Default Theme',
                        enum_values => $self->{ThemeNames},
                        processinghints => [
                        'type=dropdown',
        ])
        or croak("Failed to create setting default_theme!");

    return;
}

sub register($self) {
    $self->register_webpath($self->{webpath}, "get");
    $self->register_prerender("prerender");
    $self->register_postauthfilter("redirect_themed_images");
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
        AvailThemes     =>  $self->{Themes},
        showads => $self->{showads},
    );

    # We don't actually set the Theme into webdata here, this is done during the prerender stage.
    # Also, we don't handle the "select a default theme if non set" case, TemplateCache falls back to
    # its own default theme anyway
    my $mode = $ua->{postparams}->{'mode'} || 'view';
    if($mode eq "setvalue") {
        my $theme = $ua->{postparams}->{'theme'} || "";
        if($theme ne "") {
            $seth->set($webdata{userData}->{user}, "UserTheme", \$theme);
        }
    }


    my $template = $self->{server}->{modules}->{templates}->get("style/themes", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub prerender($self, $webdata) {
    my $userTheme = $self->{default_theme};

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    {
        my ($ok, $data) = $sysh->get($self->{modname}, "default_theme");
        if($ok) {
            $userTheme = $data->{settingvalue};
        }
    }

    # Logged in user?
    if(defined($webdata->{userData}) &&
              defined($webdata->{userData}->{user}) &&
              $webdata->{userData}->{user} ne "") {
        my $seth = $self->{server}->{modules}->{$self->{usersettings}};
        {
            my ($uok, $tmpTheme) = $seth->get($webdata->{userData}->{user}, "UserTheme");
            if($uok && defined($tmpTheme)) {
                my $dref = dbderef($tmpTheme);

                # Check if theme is still available
                foreach my $temp (@{$self->{Themes}}) {
                    if($dref eq $temp->{theme}) {
                        $userTheme = $dref;
                        last;
                    }
                }
            }
        }
    }

    if(defined($webdata->{override_theme})) {
        # Check if theme is still available
        my $override = $webdata->{override_theme};
        foreach my $temp (@{$self->{Themes}}) {
            if($override eq $temp->{theme}) {
                $userTheme = $override;
                last;
            }
        }
    }

    $webdata->{UIThemeName} = $userTheme;

    return;
}

# Handle some path changes required for correct jquery-ui multi theme support
# This is a tad inefficient and it could lead to some bugs when the user switches themes,
# where they have to manually reload to overwrite the browsers cache. Sorry about that,
# but having a "307 Temporary redirect" forced the browser to load that every time. A
# "308 Permanent Redirect" is still an experimental RFC AND not what we want.
# Just rewrite the URL internally
# FIXME: Somehow fix the theme support so jQuery always goes to the correct path...
sub redirect_themed_images($self, $ua) {
    if($ua->{url} !~ /css\/themes/ && $ua->{url} =~ /^\/static\/images\/(ui\-.*\.png)$/) {
        my $oldfname = $1;

        # Let's try to find the corresponding image in the theme subfolder
        # So we need to know to username and their selected theme
        my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
        my %webdata =
        (
            $self->{server}->get_defaultwebdata(),
        );
        my $userTheme = $self->{default_theme};

        {
            my ($ok, $data) = $sysh->get($self->{modname}, "default_theme");
            if($ok) {
                $userTheme = $data->{settingvalue};
            }
        }

        # Logged in user?
        if(defined($webdata{userData}) &&
                  defined($webdata{userData}->{user}) &&
                  $webdata{userData}->{user} ne "") {
            my $seth = $self->{server}->{modules}->{$self->{usersettings}};
            {
                my ($uok, $tmpTheme) = $seth->get($webdata{userData}->{user}, "UserTheme");
                if($uok && defined($tmpTheme)) {
                    my $dref = dbderef($tmpTheme);

                    # Check if theme is still available
                    foreach my $temp (@{$self->{Themes}}) {
                        if($dref eq $temp->{theme}) {
                            $userTheme = $dref;
                            last;
                        }
                    }
                }
            }

        }

        my $newfname = "/static/jquery/css/themes/$userTheme/images/$oldfname";
        #if($self->{isDebugging}) {
        #    print STDERR "THEME SUPPORT: Redirecting " . $ua->{url} . " to $newfname\n";
        #}
        $ua->{url} = $newfname;
    }

    # Don't return a "result", we just "fix" the requested URL
    return;
}




1;
__END__

=head1 NAME

PageCamel::Web::Themes -

=head1 SYNOPSIS

  use PageCamel::Web::Themes;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 get



=head2 prerender



=head2 get_defaultwebdata



=head2 redirect_themed_images



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
