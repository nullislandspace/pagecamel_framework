package PageCamel::Web::WebApps;
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

use base qw(PageCamel::Web::BaseModule);

use PageCamel::Helpers::DBSerialize;

# Santa = Santa wlking into the screen
# Eyes = similar to xeyes
# GST = Green Screen Technologies (e.g. simulate green screen in things like debuglogs)

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub reload {
    my ($self) = shift;

    # make sure the relevant system settings exist
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    foreach my $key (qw[santa_enable santa_default eyes_enable eyes_default gst_enable gst_default mousetrail_enable mousetrail_default]) {
        if(!defined($self->{key})) {
            if($key =~ /\_enable$/) {
                $self->{$key} = 1;
            } else {
                $self->{$key} = 0;
            }
        }
        $sysh->createBool(modulename => $self->{modname},
                            settingname => $key,
                            settingvalue => $self->{$key},
                            description => 'created from code',
                            processinghints => [
                                'type=switch',
                                                ])
                or croak("Failed to create setting $key!");
    }

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    return;
}

sub register {
    my $self = shift;
    $self->register_webpath($self->{settings}->{webpath}, "get_settings");
    $self->register_prerender("prerender");
    return;
}

sub crossregister {
    my ($self) = @_;

    return;
}

sub get_settings {
    my ($self, $ua) = @_;

    my $webpath = $ua->{url};
    my $seth = $self->{server}->{modules}->{$self->{usersettings}};

    # Get system settings
    my %sets;
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    foreach my $key (qw[santa_enable santa_default eyes_enable eyes_default gst_enable gst_default mousetrail_enable mousetrail_default]) {
        my ($ok, $data) = $sysh->get($self->{modname}, $key);
        if($ok) {
            $sets{$key} = $data->{settingvalue};
        } else {
            $sets{$key} = $self->{$key};
        }
    }


    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{settings}->{pagetitle},
        webpath         =>  $self->{settings}->{webpath},
        EnableSanta     =>  $sets{santa_enable},
        EnableEyes     =>  $sets{eyes_enable},
        EnableGST     =>  $sets{gst_enable},
        EnableMouseTrail =>  $sets{mousetrail_enable},
        showads => $self->{showads},
    );

    my %settings = (
        WebAppShowSanta     => $sets{santa_default},
        WebAppShowEyes      => $sets{eyes_default},
        WebAppUseGST      => $sets{gst_default},
        WebAppUseMouseTrail  => $sets{mousetrail_default},
    );

    foreach my $key (keys %settings) {
        my ($ok, $val) = $seth->get($webdata{userData}->{user}, $key);
        if(!$ok) {
            $val = $settings{$key};
            $seth->set($webdata{userData}->{user}, $key, \$val);
        } else {
            $val = dbderef($val);
            $settings{$key} = $val;
        }
    }

    # Just set the keys... the values are set in the prerender stage anyway
    my $mode = $ua->{postparams}->{'mode'} || 'view';
    if($mode eq "update") {
        foreach my $key (keys %settings) {
            my $val = $ua->{postparams}->{$key};
            next if(!defined($val));
            if($val eq '1' || $val eq 'on') {
                $val = "1";
            } else {
                $val = "0";
            }
            $seth->set($webdata{userData}->{user}, $key, \$val);
            $settings{$key} = $val;
        }
    }

    my $template = $self->{server}->{modules}->{templates}->get("webapps_settings", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub prerender {
    my ($self, $webdata) = @_;

    my $publicpage = 0;

    if(!defined($webdata->{userData}->{user})) {
        $publicpage = 1;
    }

    my $seth = $self->{server}->{modules}->{$self->{usersettings}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    # Get system settings
    my %sets;
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    foreach my $key (qw[santa_enable santa_default eyes_enable eyes_default gst_enable gst_default mousetrail_enable mousetrail_default]) {
        my ($ok, $data) = $sysh->get($self->{modname}, $key);
        if($ok) {
            $sets{$key} = $data->{settingvalue};
        } else {
            $sets{$key} = $self->{$key};
        }
        if(!defined($sets{$key})) {
            $sets{$key} = 0;
        }
    }

    my %settings = (
        WebAppShowSanta     => $sets{santa_default},
        WebAppShowEyes     => $sets{eyes_default},
        WebAppUseGST     => $sets{gst_default},
        WebAppUseMouseTrail => $sets{mousetrail_default},
    );

    if(!$publicpage) {
        foreach my $key (keys %settings) {
            my ($ok, $val) = $seth->get($webdata->{userData}->{user}, $key);
            if(!$ok) {
                $val = $settings{$key};
                $seth->set($webdata->{userData}->{user}, $key, \$val);
            } else {
                $val = dbderef($val);
                if(!defined($val)) {
                } else {
                    $settings{$key} = $val;
                }
            }
        }
    }

    foreach my $key (keys %settings) {
        $webdata->{$key} = $settings{$key};
    }

    # Disable settings that are disabled in config. Also disable all WebApps for embedded browsers
    # (keep to the bare essentials since they are not very good browsers on slow hardware to start with)

    if($sets{santa_enable} == 0) {
        $webdata->{WebAppShowSanta} = 0;
    }

    if($sets{eyes_enable} == 0) {
        $webdata->{WebAppShowEyes} = 0;
    }

    if($sets{gst_enable} == 0 ||
        (defined($webdata->{BrowserData}->{Embedded}) &&
         $webdata->{BrowserData}->{Embedded} == 1)) {
        $webdata->{WebAppUseGST} = 0;
    }

    if($sets{mousetrail_enable} == 0 ||
        (defined($webdata->{BrowserData}->{Embedded}) &&
         $webdata->{BrowserData}->{Embedded} == 1)) {
        $webdata->{WebAppUseMouseTrail} = 0;
    }
    
    return;
}

1;
__END__

=head1 NAME

PageCamel::Web::WebApps -

=head1 SYNOPSIS

  use PageCamel::Web::WebApps;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 crossregister



=head2 get_settings



=head2 prerender



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
