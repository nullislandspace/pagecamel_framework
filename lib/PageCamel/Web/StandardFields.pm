package PageCamel::Web::StandardFields;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.3;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::DBSerialize;
use Sys::Hostname;

use JSON::XS;
use MIME::Base64 qw(encode_base64);

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    # copy general config options to field-hash
    foreach my $keyname (keys %{$self->{static}->{fields}}) {
        next if($keyname eq 'hosts');
        $self->{fields}->{$keyname} = $self->{static}->{fields}->{$keyname};
    }


    # copy host-specific settings from sub-hash to field-hash
    my $hname = hostname;
    print "   Host-specific configuration for '$hname'\n";
    if(defined($self->{static}->{fields}->{hosts}->{$hname})) {
        foreach my $keyname (keys %{$self->{static}->{fields}->{hosts}->{$hname}}) {
            $self->{fields}->{$keyname} = $self->{static}->{fields}->{hosts}->{$hname}->{$keyname};
        }
    }

    $self->{lastUpdate} = 0;
    $self->{valueCache} = {};

    return $self;
}

sub reload($self) {

    # Create fields in system settings (if not existing)
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    foreach my $keyname (keys %{$self->{fields}}) {
        next if($keyname eq "hosts");

        my $r = ref($self->{fields}->{$keyname});
        if($r eq 'HASH') {
            # Workaround some XML parsing issues
            $self->{fields}->{$keyname} = '';
        }

        my $type = "textfield";
        if($keyname eq 'header_info' || $keyname eq 'header_message') {
            $type = 'textarea';
        }

        $sysh->createText(modulename => $self->{modname},
                            settingname => $keyname,
                            settingvalue => $self->{fields}->{$keyname},
                            description => 'created from XML',
                            processinghints => [
                                "type=$type",
                                                ])
                or croak("Failed to create setting $keyname!");
    }

    $sysh->createText(modulename => $self->{modname},
                    settingname => 'enable_april_fools',
                    settingvalue => 'auto',
                    description => 'April Fools stuff',
                    processinghints => [
                        'type=tristate',
                        'on=Always',
                        'off=Disable',
                        'auto=Automatic'
                                        ])
        or croak("Failed to create setting enable_april_fools!");

    $self->{LastReloadDate} = getFileDate();

    # Check if we have settings in the database that are not in the config file
    my ($ok, @allsets) = $sysh->list($self->{modname});
    if($ok) {
        foreach my $setting (@allsets) {
            if(!defined($self->{fields}->{$setting})) {
                # Just make a dummy entry so the value gets loaded in get_defaultwebdata()
                $self->{fields}->{$setting} = '';
                print "    ** registering DB-only key $setting\n";
            }
        }
    }

    return;
}

sub register($self) {
    $self->register_defaultwebdata("get_defaultwebdata");
    $self->register_lateprerender("lateprerender");
    return;
}

sub crossregister($self) {
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    my $hname = lc hostname;
    if($hname =~ /lin.*dev/) {
        print "    DEV system: force header_info\n";
        $sysh->set($self->{modname}, 'header_info', "Development system ($hname)");
    }

    return;
}

sub get_defaultwebdata($self, $webdata) {

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    $webdata->{CurrentTime} = PageCamel::Helpers::DateStrings::getISODate();
    $webdata->{IsAprilFoolsDayRNG} = int(rand(1000));
    $webdata->{PageCamelVersion} = $VERSION;

    { # Check the enable_april_fools flag
        my ($ok, $data) = $sysh->get($self->{modname}, 'enable_april_fools');
        if($ok && $data->{settingvalue} eq 'on') {
            $webdata->{IsAprilFoolsDay} = 1;
        } elsif($ok && $data->{settingvalue} eq 'off') {
            $webdata->{IsAprilFoolsDay} = 0;
        } else {
            # Auto
            $webdata->{IsAprilFoolsDay} = PageCamel::Helpers::DateStrings::isAprilFoolsDay();
        }
    }

    my $needUpdate = 0;
    {
        my $data = 0 + $memh->get("SystemSettings::lastUpdate");
        if($data != $self->{lastUpdate}) {
          $needUpdate = 1;
          $self->{lastUpdate} = $data;
        }

    }

    foreach my $key (sort keys %{$self->{fields}}) {
        next if($key eq "hosts");
        if($needUpdate || !defined($self->{valueCache}->{$key})) {
            my ($ok, $data) = $sysh->get($self->{modname}, $key);
            if($ok) {
                $webdata->{$key} = $data->{settingvalue};
                $self->{valueCache}->{$key} = $data->{settingvalue};
            } else {
                delete $self->{valueCache}->{$key};
            }
        } else {
            $webdata->{$key} = $self->{valueCache}->{$key};
        }
    }

    foreach my $key (keys %{$self->{memory}->{fields}}) {
        my $data = $memh->get($self->{memory}->{fields}->{$key});
        if(defined($data) && $self->{memory}->{fields}->{$key} =~ /^(VERSION)\:\:/go) {
            $data = dbderef($data);
        }
        $webdata->{$key} = $data;

    }

    if($webdata->{IsAprilFoolsDay}) {
        $webdata->{ProjectName} = "Hic qua videum";
        $webdata->{ProjectMotto} = "Nou ani Anquietas!";
        #$webdata->{ProjectHeaderColor} = '#46382b';
        #$webdata->{ProjectMottoColor} = '#ebd7b6';
        #$webdata->{ProjectNameColor} = '#ebd7b6';
    }

    $webdata->{LastReloadDate} = $self->{LastReloadDate};
    $webdata->{URLReloadPostfix} = '*' . $self->{LastReloadDate};

    $webdata->{isDebugging} = $self->{isDebugging};

    return;
}

sub lateprerender($self, $webdata) {
    if(!defined($webdata->{MaskHasConfigObject}) || !$webdata->{MaskHasConfigObject}) {
        $webdata->{MaskHasConfigObject} = 0;
    } elsif($webdata->{MaskHasConfigObject}) {
        if(!defined($webdata->{ConfigObject})) {
            my %tmp;
            $webdata->{ConfigObject} = \%tmp;
        }
        $self->{server}->{modules}->{templates}->addTranslations($webdata);
        $webdata->{MaskConfigObject} = encode_base64(encode_json($webdata->{ConfigObject}), '');
        #print STDERR Dumper($webdata->{ConfigObject});
    }
    return;
}

1;
__END__

=head1 NAME

PageCamel::Web::StandardFields -

=head1 SYNOPSIS

  use PageCamel::Web::StandardFields;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 crossregister



=head2 get_defaultwebdata



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
