package PageCamel::Worker::HomeAutomation::FritzBox;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

# Do some updates and advanced parsing for accesslog. Run at once an hour. The
# Exception here is: If workCount > 0 then it will ru in the next loop too

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DBSerialize;
use Net::Clacks::Client;
use Data::Dumper;
use AHA;

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
    $self->{clacks} = Net::Clacks::Client->new($clconf->get('host'), $clconf->get('port'), $clconf->get('user'), $clconf->get('password'), $self->{PSAPPNAME} . ':' . $self->{modname}, 0);
    foreach my $key (keys %{$self->{switches}}) {
        $self->{clacks}->listen($self->{switches}->{$key}->{clacksname_setswitch});
    }

    $self->{clacks}->doNetwork();
    $self->{nextping} = 0;

    return;
}

sub reload {
    my ($self) = @_;

    my $fritz = AHA->new({host => $self->{hostname}, user => $self->{username}, password => $self->{password}})
            or croak("Can't connect to Fritz!Box");
    $self->{fritz} = $fritz;

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
            foreach my $key (keys %{$self->{switches}}) {
                if($cmsg->{name} eq $self->{switches}->{$key}->{clacksname_setswitch}) {
                    if(!defined($self->{switches}->{$key}->{state})) {
                        $reph->debuglog("Clacks: Can't set switch $key because Fritz!Box doesn't know about it!");
                    } elsif($cmsg->{data} == $self->{switches}->{$key}->{state}) {
                        $reph->debuglog("Clacks: Switch $key already in state " . $cmsg->{data});
                    } elsif($self->{switches}->{$key}->{state} == -1) {
                        $reph->debuglog("Clacks: Can't swwitch $key, currently not present at Fritz!Box");
                    } else {
                        if($cmsg->{data} == 1) {
                            $reph->debuglog("Clacks: Switching $key to ON");
                            $self->{fritz}->on($self->{switches}->{$key}->{ain});
                            $self->{nextrun} = time + 5;
                        } else {
                            $reph->debuglog("Clacks: Switching $key to OFF");
                            $self->{fritz}->off($self->{switches}->{$key}->{ain});
                            $self->{nextrun} = time + 5;
                        }
                        $workCount++;
                    }
                    last;
                }
            }
        }
    }
    $self->{clacks}->doNetwork();
    
    # Only read states from Fritz!Box every 10 seconds, unless switches have been changed via clacks
    if($now > $self->{nextrun}) {
        #$reph->debuglog("_");
        $self->{nextrun} = time + 10;
    } else {
        return $workCount;
    }

    my $switches = $self->{fritz}->list;
    foreach my $switch (@{$switches}) {
        my $sname = $switch->name();
        next unless defined($self->{switches}->{$sname});
        if(!$switch->is_present) {
            $reph->debuglog("Switch $sname NOT PRESENT!");
            $self->{clacks}->setAndStore($self->{switches}->{$sname}->{clacksname_ispresent}, 0);
            $self->{clacks}->setAndStore($self->{switches}->{$sname}->{clacksname_state}, -1); # "Unknown"
            $self->{switches}->{$sname}->{state} = -1;
            $self->{clacks}->setAndStore($self->{switches}->{$sname}->{clacksname_power}, -1); # "Unknown"
            $self->{clacks}->setAndStore($self->{switches}->{$sname}->{clacksname_energy}, -1); # "Unknown"

            # "Forget" the AIN
            $self->{switches}->{$sname}->{ain} = 0;
        } else {
            $self->{clacks}->setAndStore($self->{switches}->{$sname}->{clacksname_ispresent}, 1);
            if($switch->is_on()) {
                $self->{clacks}->setAndStore($self->{switches}->{$sname}->{clacksname_state}, 1); # ON
                $self->{switches}->{$sname}->{state} = 1;
            } else {
                $self->{clacks}->setAndStore($self->{switches}->{$sname}->{clacksname_state}, 0); # OFF
                $self->{switches}->{$sname}->{state} = 0;
            }
            $self->{clacks}->setAndStore($self->{switches}->{$sname}->{clacksname_power}, $switch->power);
            $self->{clacks}->setAndStore($self->{switches}->{$sname}->{clacksname_energy}, $switch->energy); # "Unknown"

            # Remember the AIN
            $self->{switches}->{$sname}->{ain} = $switch->ain();
        }
    }

    foreach my $key (keys %{$self->{switches}}) {
        if(!defined($self->{switches}->{$key}->{state})) {
            $reph->debuglog("Switch $key not known to Fritz!Box");
        }
    }

    $self->{clacks}->doNetwork();


    return $workCount;
}

1;
__END__
