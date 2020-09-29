package PageCamel::Worker::HomeAutomation::PowerShare;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.3;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
use Data::Dumper;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);
use Net::Clacks::Client;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{nextrun} = 0;

    return $self;
}


sub register {
    my $self = shift;
    $self->register_worker("work");

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);
    $self->{clacks}->doNetwork();
    $self->{nextping} = 0;

    return;
}

sub work {
    my ($self) = @_;

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

    my (undef, $curminute) = localtime time;

    foreach my $item (@{$self->{item}}) {
        my $curstate = $self->{clacks}->retrieve($item->{clacksname_state});
        my $nextstate = 1; # Inhibit by default

        if($curminute >= $item->{startminute} && $curminute <= $item->{endminute}) {
            $nextstate = 0;
        }

        if(!defined($curstate) || $curstate != $nextstate) {
            if($nextstate) {
                $reph->debuglog("Powershare: Disabling switch " . $item->{itemname});
            } else {
                $reph->debuglog("Powershare: Enabling switch " . $item->{itemname});
            }
        }
        $self->{clacks}->set($item->{clacksname_switch}, $nextstate);
    }

    $self->{clacks}->doNetwork();

    return $workCount;
}


1;
__END__
