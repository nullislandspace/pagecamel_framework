package PageCamel::Web::Tools::AdConfig;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 2.5;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);

use MIME::Base64;

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

    $sysh->createText(modulename => $self->{modname},
                    settingname => 'display_ads',
                    settingvalue => 0,
                    description => 'Globally enable/disable showing ads',
                    processinghints => [
                        'type=switch'
                                        ])
        or croak("Failed to create setting display_ads!");

    $sysh->createText(modulename => $self->{modname},
                        settingname => 'header_code',
                        settingvalue => '',
                        description => 'Code that is inserted into the header of each page',
                        processinghints => [
                            "type=textfield",
                                            ])
            or croak("Failed to create setting header_code!");

    $sysh->createText(modulename => $self->{modname},
                        settingname => 'ads_txt',
                        settingvalue => '',
                        description => 'Content of /ads.txt',
                        processinghints => [
                            "type=textfield",
                                            ])
            or croak("Failed to create setting ads_txt!");
}

sub register {
    my $self = shift;
    $self->register_webpath('/ads.txt', "get_adstxt");
    $self->register_webpath($self->{webpath}, "get_settings");
    $self->register_prerender("prerender");
    return;
}

sub get_adstxt {
    my ($self, $ua) = @_;

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    my ($ok, $data) = $sysh->get($self->{modname}, 'ads_txt');
    if(!$ok || !defined($data) || $data eq '') {
        return(status => 404);
    }

    return (status => 200,
            type => 'text/plain',
            data => $data);
}

sub get_settings {
    my ($self, $ua) = @_;

    my $webpath = $ua->{url};
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    
    # Save the input
    my $mode = $ua->{postparams}->{'mode'} || 'view';
    if($mode eq "update") {
        my $code = $ua->{postparams}->{header_code} || '';
        $code =~ s/\r//g;
        $code =~ s/\n{3,}/\n\n/g;
        $code =~ s/\n+$//g;
        $sysh->set($self->{modname}, 'header_code', $code);

        my $adstxt = $ua->{postparams}->{ads_txt} || '';
        $adstxt =~ s/\r//g;
        $adstxt =~ s/\n{3,}/\n\n/g;
        $adstxt =~ s/\n+$//g;
        $sysh->set($self->{modname}, 'ads_txt', $adstxt);
        
        foreach my $key (qw[display_ads]) {
            my $val = $ua->{postparams}->{$key};
            if($val ne '') {
                $sysh->set($self->{modname}, $key, $val);
            }
        }
    }

    # Load systemsettings
    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{pagetitle},
        webpath         =>  $self->{webpath},
        showads => $self->{showads},
    );
    foreach my $key (qw[header_code display_ads ads_txt]) {
        my ($ok, $data) = $sysh->get($self->{modname}, $key);
        if($ok) {
            $webdata{$key} = $data->{settingvalue};
        }
    }
    
    my $template = $self->{server}->{modules}->{templates}->get("tools/adconfig", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub prerender {
    my ($self, $webdata) = @_;

    if(!defined($webdata->{showads})) {
        $webdata->{showads} = 0;
    }

    return unless($webdata->{showads});

    my $seth = $self->{server}->{modules}->{$self->{usersettings}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    # Get system settings
    my %sets;
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    foreach my $key (qw[display_ads header_code]) {
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

    if($sets{display_ads}) {
        $webdata->{AdsHeaderCode} = $sets{header_code};
    } else {
        $webdata->{AdsHeaderCode} = '';
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

Copyright (C) 2008-2019 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
