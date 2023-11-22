package PageCamel::Web::Tools::DSKY;
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

use base qw(PageCamel::Web::BaseWebSocket);
use PageCamel::Helpers::DateStrings;
use Net::Clacks::Client;
use JSON::XS;
use MIME::Base64;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{extrasettings} = [];
    $self->{template} = 'tools/dsky';

    return $self;
}

sub wsmaskget($self, $ua, $settings, $webdata) {
    
    if(!defined($webdata->{HeadExtraScript})) {
        $webdata->{HeadExtraScript} = [];
    }
    
    if(0) {
        push @{$webdata->{HeadExtraScripts}}, '/static/canvasjs/canvasbuttons.js';
        push @{$webdata->{HeadExtraScripts}}, '/static/canvasjs/canvasitemlist.js';
        push @{$webdata->{HeadExtraScripts}}, '/static/canvasjs/canvas7segment.js';
        push @{$webdata->{HeadExtraScripts}}, '/static/canvasjs/canvashelpers.js';
    } else {
        push @{$webdata->{HeadExtraScripts}}, '/static/canvasjs.compiled-min.js';
    }
    
    return;
}

sub wshandlerstart($self, $ua, $settings) {

    $self->{nextping} = time + 10;

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);

    $self->{clacks}->listen('DSKY::Display0');
    $self->{clacks}->listen('DSKY::Display1');
    $self->{clacks}->listen('DSKY::Display2');
    $self->{clacks}->listen('DSKY::Display3');
    $self->{clacks}->listen('DSKY::Display4');
    $self->{clacks}->listen('DSKY::Display5');
    $self->{clacks}->listen('DSKY::Display6');
    $self->{clacks}->listen('DSKY::KeyPressed');
    $self->{clacks}->notify('DSKY::update_all');

    $self->{clacks}->doNetwork();
    
    return;
}

sub wshandlemessage($self, $message) {

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    

    if($message->{type} eq 'BUTTONPRESS') {
        if($message->{data} eq '00') {
            $self->{clacks}->set('DSKY::KeyPress', '0');
            $self->{clacks}->set('DSKY::KeyPress', '0');
        } else {
            $self->{clacks}->set('DSKY::KeyPress', $message->{data});
        }
        $self->{clacks}->doNetwork();
    }
            
    return 1;
}

sub wscleanup($self) {

    delete $self->{nextping};
    delete $self->{clacks};

    return;
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

        if($cmsg->{type} eq 'set' && $cmsg->{name} =~ /^DSKY::Display(\d)$/) {
            my $displaynum = $1;
            my $rawdata = decode_base64($cmsg->{data});
            my @rawparts = split//, $rawdata;
            my @bits;
            foreach my $rawpart (@rawparts) {
                $rawpart = ord($rawpart);
                for(my $offs = 0; $offs < 8; $offs++) {
                    if($rawpart & (0x01 << $offs)) {
                        push @bits, '1';
                    } else {
                        push @bits, '0';
                    }
                }
            }
            my $bitdata = join('', @bits);
            my %msg = (
                type => "SETDISPLAY",
                displaynum => $displaynum,
                data => $bitdata,
            );
            
            if(!$self->wsprint(\%msg)) {
                return 0;
            }
        } elsif($cmsg->{type} eq 'set' && $cmsg->{name} =~ /^DSKY::KeyPressed$/) {
            my %msg = (
                type => "KEYPRESSED",
                data => $cmsg->{data},
            );
            
            if(!$self->wsprint(\%msg)) {
                return 0;
            }
        }
    }

    $self->{clacks}->doNetwork();

    return 1;
}


1;
__END__
