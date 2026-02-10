# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license
package PageCamel::Web::Tools::KaffeeSim;
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

use base qw(PageCamel::Web::BaseWebSocket);
use Net::Clacks::Client;
sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{extrasettings} = [];
    $self->{template} = 'tools/kaffeesim';
    $self->{defaultDisconnectTimeout} = 25;  # Preserves 25s ping interval
    $self->{readonly} //= 0;

    return $self;
}

sub wsmaskget($self, $ua, $settings, $webdata) {
    $webdata->{Readonly} = $self->{readonly};
    return 200;
}

sub wshandlerstart($self, $ua, $settings) {
    $self->{nextping} = time + 10;

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);

    my @clackssettings = (
        'Production_Enable',
        'Manual_Override',
        'Boiler::Waterlevel',
        'Boiler::Invalve',
        'Boiler::Temp',
        'Boiler::Heater',
        'Boiler::Outvalve',
        'Boiler::Fullrefill',
        'Beans::Level',
        'Beans::Invalve',
        'Grinder::Power',
        'Mixer::Power',
        'Outcounter::Count',
        'Outcounter::Flowing',
        'Wastecounter::Count',
        'Wastecounter::Flowing',
    );
    my %reverselookup;
    my %lookup;

    foreach my $setname (@clackssettings) {
        $self->{clacks}->listen('Kaffee::' . $setname);
        my ($device, $sensor) = split/\:\:/, $setname;
        my $lname;
        if(defined($sensor)) {
            $lname = lc $device . '_' . lc $sensor;
        } else {
            $lname = lc $device;
        }
        $reverselookup{$lname} = $setname;
        $lookup{'Kaffee::' . $setname} = $lname;
    }
    $self->{clacks}->notify('Kaffee::update_all');

    $self->{reverselookup} = \%reverselookup;
    $self->{lookup} = \%lookup;

    $self->{clacks}->doNetwork();

    return;
}

sub wshandlemessage($self, $message) {
    if($message->{type} eq 'LISTEN') {
        $self->{clacks}->listen('Kaffee::' . $self->{reverselookup}{$message->{varname}}) unless $self->{readonly};
    } elsif($message->{type} eq 'NOTIFY') {
        $self->{clacks}->notify('Kaffee::' . $message->{varname}) unless $self->{readonly};
    } elsif($message->{type} eq 'SET') {
        $self->{clacks}->set('Kaffee::' . $self->{reverselookup}{$message->{varname}}, $message->{varvalue}) unless $self->{readonly};
    }
    return 1;
}

sub wscyclic($self, $ua) {
    my $now = time;
    if($now > $self->{nextping}) {
        $self->{clacks}->ping();
        $self->{nextping} = $now + 10;
    }

    while(1) {
        my $cmsg = $self->{clacks}->getNext();
        last unless defined($cmsg);

        if($cmsg->{type} eq 'set') {
            my %msg = (
                type => 'VALUE',
                varname => $self->{lookup}{$cmsg->{name}},
                varval => $cmsg->{data},
            );
            if(!$self->wsprint(\%msg)) {
                return 0;
            }
        }
    }

    $self->{clacks}->doNetwork();

    return 1;
}

sub wscleanup($self) {
    delete $self->{clacks};
    delete $self->{reverselookup};
    delete $self->{lookup};
    delete $self->{nextping};
    return;
}

1;
