package PageCamel::Web::Webcam;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseWebSocket);
use PageCamel::Helpers::DateStrings;
use Net::Clacks::Client;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{extrasettings} = [];
    $self->{template} = 'webcam';

    if(!defined($self->{adminmode}) || $self->{adminmode} != 1) {
        $self->{adminmode} = 0;
    }

    foreach my $item (@{$self->{item}}) {
        my $htmlname = lc $item->{camname};
        $htmlname =~ s/\:/_/g;
        $item->{htmlname} = $htmlname;
        $item->{clacksname} = 'Webcam::' . $item->{camname} . '::imagedata';
    }

    return $self;
}


sub wsmaskget($self, $ua, $settings, $webdata) {

    $webdata->{cameras} = $self->{item};
    if(defined($self->{bodytext})) {
        $webdata->{bodytext} = $self->{bodytext};
    }

    $webdata->{WebcamAdminMode} = $self->{adminmode};
    
    return;
}

sub wshandlerstart($self, $ua, $settings) {

    $self->{nextping} = time + 10;

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);

    $self->{clacks}->doNetwork();

    $self->{retrievecached} = 1;

    foreach my $item (@{$self->{item}}) {
        $self->{clacks}->listen($item->{clacksname});
    }

    if($self->{adminmode}) {
        $self->{clacks}->listen($self->{camname} . '::Config');
    }

    $self->{clacks}->doNetwork();

    return;
}

sub wscleanup($self) {

    delete $self->{nextping};
    delete $self->{clacks};

    return;
}

sub wshandlemessage($self, $message) {

    if($message->{type} eq 'COMMAND') {
        $self->{clacks}->set($self->{camname} . '::Command', $message->{cmdstring});
        $self->{clacks}->doNetwork();
    }

    return 1;
}

sub wscyclic($self) {

    if($self->{retrievecached}) {
        $self->{retrievecached} = 0;
        foreach my $item (@{$self->{item}}) {
            my $imagedata = $self->{clacks}->retrieve($item->{clacksname});
            if(defined($imagedata) && $imagedata ne '') {
                my %msg = (
                    type => 'IMAGE',
                    cameraname => $item->{htmlname},
                    varval => $imagedata,

                );

                if(!$self->wsprint(\%msg)) {
                    return 0;
                }
            }
        }
    }

    $self->{clacks}->doNetwork();
    my $now = time;
    if($now > $self->{nextping}) {
        $self->{clacks}->ping();
        $self->{nextping} = $now + 10;
    }

    while(1) {
        my $cmsg = $self->{clacks}->getNext();
        last unless defined($cmsg);

        if($cmsg->{type} eq 'set') {
            if($cmsg->{name} eq $self->{camname} . '::Config') {
                next unless($self->{adminmode});

                my @parts = split/\&/, $cmsg->{data};
                my %msg = (
                    type => 'SETTINGS',
                );
                foreach my $part (@parts) {
                    my ($key, $val) = split/\=/, $part;
                    $msg{$key} = $val;
                }
                if(!$self->wsprint(\%msg)) {
                    return 0;
                }

                next;
            }
            foreach my $item (@{$self->{item}}) {
                next unless($cmsg->{name} eq $item->{clacksname});
                my %msg = (
                    type => 'IMAGE',
                    cameraname => $item->{htmlname},
                    varval => $cmsg->{data},

                );

                if(!$self->wsprint(\%msg)) {
                    return 0;
                }
            }
        }
    }

    $self->{clacks}->doNetwork();

    return 1;
}

1;
__END__
