package PageCamel::Worker::HomeAutomation::Allnet4076;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.4;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

# Do some updates and advanced parsing for accesslog. Run at once an hour. The
# Exception here is: If workCount > 0 then it will ru in the next loop too

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DBSerialize;
use Net::Clacks::Client;
use WWW::Mechanize;
use XML::Simple;
use Data::Dumper;

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
    foreach my $key (keys %{$self->{switches}}) {
        $self->{clacks}->listen($self->{switches}->{$key}->{clacksname_setswitch});
    }

    $self->{clacks}->doNetwork();
    $self->{nextping} = 0;

    return;
}

sub work {
    my ($self) = @_;

    my $workCount = 0;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    $self->{clacks}->doNetwork();

    my $now = time;
    if($now > $self->{nextping}) {
        $self->{clacks}->ping();
        $self->{nextping} = $now + 30;
        $workCount++;
    }

    $self->{clacks}->doNetwork();


    while((my $cmsg = $self->{clacks}->getNext())) {
        $workCount++;
        if($cmsg->{type} eq 'disconnect') {
            $self->debuglog("Restarting clacks connection");
            foreach my $key (keys %{$self->{switches}}) {
                $self->{clacks}->listen($self->{switches}->{$key}->{clacksname_setswitch});
            }
            $self->{clacks}->ping();
            $self->{clacks}->doNetwork();
            $self->{nextping} = $now + 30;
            next;
        } elsif($cmsg->{type} eq 'set') {
            # Change switch if required
            $reph->debuglog("GOT CLACKS: " . $cmsg->{name} . "=" . $cmsg->{data});
            $self->setSwitch($cmsg->{name}, $cmsg->{data});
            $self->{nextrun} = time + 5;
        }
    }
    $self->{clacks}->doNetwork();

    # Only read the states every 10 seconds (unless switch got updated)
    if($now > $self->{nextrun}) {
        #$reph->debuglog("_");
        $self->{nextrun} = time + 10;
    } else {
        return $workCount;
    }


    $self->updateStates();
    $self->{clacks}->doNetwork();


    return $workCount;
}

sub updateStates {
    my ($self) = @_;

    my $xml = $self->runCommand('mode=actor&type=list');
    if(!defined($xml)) {
        foreach my $key (%{$self->{switches}}) {
            $self->{clacks}->setAndStore($self->{switches}->{$key}->{clacksname_ispresent}, 0);
            $self->{clacks}->setAndStore($self->{switches}->{$key}->{clacksname_state}, -1);
        }
    } else {
        foreach my $actor (@{$xml->{actor}}) {
            foreach my $key (keys %{$self->{switches}}) {
                next unless($self->{switches}->{$key}->{switchid} eq $actor->{id});
                $self->{clacks}->setAndStore($self->{switches}->{$key}->{clacksname_ispresent}, 1);
                $self->{clacks}->setAndStore($self->{switches}->{$key}->{clacksname_state}, $actor->{state});
            }
        }
    }

    return;
}

sub setSwitch {
    my ($self, $clacksname, $value) = @_;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    if($value ne '0') {
        $value = '1';
    }
    my $id;
    my $name;
    foreach my $key (keys %{$self->{switches}}) {
        if($clacksname eq $self->{switches}->{$key}->{clacksname_setswitch}) {
            $id = $self->{switches}->{$key}->{switchid};
            $name = $key;
            last;
        }
    }

    if(!defined($id)) {
        $reph->debuglog("Can't change Allnet4076 " . $self->{hostname} . " switch. Internal error, unknown switch");
        return;
    }

    my $statenow = $self->{clacks}->retrieve($self->{switches}->{$name}->{clacksname_state});
    if(!defined($statenow)) {
        $reph->debuglog("Can't change Allnet4076 " . $self->{hostname} . " switch $id: Undefined state");
        return;
    }
    if($statenow == -1) {
        $reph->debuglog("Can't change Allnet4076 " . $self->{hostname} . " switch $id: Not present");
        return;
    }
    if($statenow eq $value) {
        $reph->debuglog("Can't change Allnet4076 " . $self->{hostname} . " switch $id: Already at correct state");
        return;
    }

    $reph->debuglog("Setting Allnet4076 " . $self->{hostname} . " switch $id to $value");

    my $xml = $self->runCommand('mode=actor&type=switch&id=' . $id . '&action=' . $value);
    if(!defined($xml)) {
        return 0;
    } else {
        return $xml->{result};
    }
}

sub runCommand {
    my ($self, $command) = @_;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $mech = WWW::Mechanize->new();
    my $result;
    my $success;
    if(!(eval {
        $result = $mech->get('http://' . $self->{hostname} . '/xml/?' . $command);
        $success = 1;
        1;
    })) {
        $success = 0;
    }

    if(!$success || !defined($result) || !$result->is_success || $result->code ne '200') {
        $reph->debuglog("Failed to connect to ALLNET4076 sensor at " . $self->{hostname});
        return;
    }

    my $doc = $result->content;
    my $xml = XMLin($doc);
    return $xml;
}

1;
__END__
