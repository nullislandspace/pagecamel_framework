package PageCamel::Worker::HomeAutomation::ResetDevice;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);
use Net::Clacks::Client;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{nextrun} = 0;

    return $self;
}


sub register($self) {
    $self->register_worker("work");

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);
    $self->{clacks}->doNetwork();
    $self->{nextping} = 0;

    return;
}

sub work($self) {
    my $workCount = 0;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $now = time;
    if($now > $self->{nextping}) {
        $self->{clacks}->ping();
        $self->{nextping} = $now + 30;
        $workCount++;
    }

    # Handle config changes through clacks
    $self->{clacks}->doNetwork();
    while((my $cmsg = $self->{clacks}->getNext())) {
        $workCount++;
        if($cmsg->{type} eq 'set') {
            $self->{nextrun} = 0; # Make sure we react quickly to clacks input
        }
        if($cmsg->{type} eq 'disconnect') {
            $reph->debuglog("Restarting clacks connection");
            $self->{nextping} = $now + 30;
            next;
        }
    }
    $self->{clacks}->doNetwork();

    # Only work every 10 seconds or so, no need to tax the system
    if($now > $self->{nextrun}) {
        $self->{nextrun} = time + 10;
    } else {
        return $workCount;
    }

    my (undef, $curminute, $curhour) = localtime time;
    my $nextstate = 1; # Default ON
    my $curstate = $self->{clacks}->retrieve($self->{clacksname_switchstate});

    if(defined($self->{minutes})) {
        foreach my $item (@{$self->{minutes}->{item}}) {

            if($curminute == $item) {
                #print STDERR "Minute matched!\n";
                $nextstate = 0;
            }
        }
    }

    if(defined($self->{hours})) {
        foreach my $item (@{$self->{hours}->{item}}) {

            if($curhour == $item) {
                #print STDERR "Hour matched!\n";
                $nextstate = 0;
            }
        }
    }

    if(defined($self->{time})) {
        foreach my $item (@{$self->{time}->{item}}) {

            if($curhour == $item->{hour} && $curminute == $item->{minute}) {
                #print STDERR "Time matched!\n";
                $nextstate = 0;
            }
        }
    }

    if(!defined($curstate) || $curstate != $nextstate) {
        if($nextstate) {
            $reph->debuglog("Turning ON device " . $self->{device_name});
        } else {
            $reph->debuglog("Turning OFF device " . $self->{device_name});
        }
        $self->{clacks}->set($self->{clacksname_switchcommand}, $nextstate);
    }

    $self->{clacks}->doNetwork();

    return $workCount;
}


1;
__END__
