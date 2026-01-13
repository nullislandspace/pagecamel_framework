package PageCamel::Worker::HomeAutomation::FritzBox;
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

# Do some updates and advanced parsing for accesslog. Run at once an hour. The
# Exception here is: If workCount > 0 then it will ru in the next loop too

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DBSerialize;
use Net::Clacks::Client;
use AHA;

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
    foreach my $key (keys %{$self->{switches}}) {
        $self->{clacks}->listen($self->{switches}->{$key}->{clacksname_setswitch});
        $self->{clacks}->listen($self->{switches}->{$key}->{clacksname_disable_switch});
    }

    $self->{clacks}->doNetwork();
    $self->{nextping} = 0;

    return;
}

sub reload($self) {
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    $reph->debuglog("Connecting to Fritz!Box");
    my $fritz = AHA->new({host => $self->{hostname}, user => $self->{username}, password => $self->{password}})
            or croak("Can't connect to Fritz!Box");
    $reph->debuglog("Connected to Fritz!Box");

    $self->{fritz} = $fritz;

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

    $self->{clacks}->doNetwork();


    my $updatenow = 0;
    while((my $cmsg = $self->{clacks}->getNext())) {
        $workCount++;
        if($cmsg->{type} eq 'disconnect') {
            $self->debuglog("Restarting clacks connection");
            foreach my $key (keys %{$self->{switches}}) {
                $self->{clacks}->listen($self->{switches}->{$key}->{clacksname_setswitch});
                $self->{clacks}->listen($self->{switches}->{$key}->{clacksname_disable_switch});
            }
            $self->{clacks}->ping();
            $self->{clacks}->doNetwork();
            $self->{nextping} = $now + 30;
            next;
        } elsif($cmsg->{type} eq 'set') {
            # Change switch if required
            #$reph->debuglog("GOT CLACKS: " . $cmsg->{name} . "=" . $cmsg->{data});
            foreach my $key (keys %{$self->{switches}}) {
                if($cmsg->{name} eq $self->{switches}->{$key}->{clacksname_disable_switch}) {
                    my $curstate = $self->{clacks}->retrieve($self->{switches}->{$key}->{clacksname_disable_state});
                    if($curstate != $cmsg->{data}) {
                        if($cmsg->{data}) {
                            $reph->debuglog("Disabling switch $key");
                        } else {
                            $reph->debuglog("Enabling switch $key");
                        }
                    }
                    $self->{clacks}->setAndStore($self->{switches}->{$key}->{clacksname_disable_state}, $cmsg->{data});
                } elsif($cmsg->{name} eq $self->{switches}->{$key}->{clacksname_setswitch}) {
                    if(!defined($self->{switches}->{$key}->{state})) {
                        $reph->debuglog("Clacks: Can't set switch $key because Fritz!Box doesn't know about it!");
                    } elsif($cmsg->{data} == $self->{switches}->{$key}->{state}) {
                        $reph->debuglog("Clacks: Switch $key already in state " . $cmsg->{data});
                    } elsif($self->{switches}->{$key}->{state} == -1) {
                        $reph->debuglog("Clacks: Can't switch $key, currently not present at Fritz!Box");
                    } else {
                        if($cmsg->{data} == 1) {
                            my $disablestate = $self->{clacks}->retrieve($self->{switches}->{$key}->{clacksname_disable_state}) || 0;
                            if($disablestate) {
                                $reph->debuglog("Switch $key is DISABLED, not allowed to switch to ON!");
                            } else {
                                $reph->debuglog("Clacks: Switching $key to ON");
                                $self->{fritz}->on($self->{switches}->{$key}->{ain});
                                $self->{nextrun} = time + 5;
                                $updatenow = 1;
                            }
                        } else {
                            $reph->debuglog("Clacks: Switching $key to OFF");
                            $self->{fritz}->off($self->{switches}->{$key}->{ain});
                            $updatenow = 1;
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
    if($updatenow || $now > $self->{nextrun}) {
        #$reph->debuglog("_");
        $self->{nextrun} = time + 10;
    } else {
        return $workCount;
    }

    $reph->debuglog("Loading list of switches...");
    my $switches = $self->{fritz}->list;
    foreach my $switch (@{$switches}) {
        my $sname = $switch->name();
        $reph->debuglog("Working on switch ", $sname);
        next unless defined($self->{switches}->{$sname});
        if(!$switch->is_present) {
            $reph->debuglog("Switch $sname NOT PRESENT!");
            $self->{clacks}->setAndStore($self->{switches}->{$sname}->{clacksname_ispresent}, 0);
            $self->{clacks}->setAndStore($self->{switches}->{$sname}->{clacksname_state}, -1); # "Unknown"
            $self->{switches}->{$sname}->{state} = -1;
            $self->{clacks}->setAndStore($self->{switches}->{$sname}->{clacksname_power}, -1); # "Unknown"
            $self->{clacks}->setAndStore($self->{switches}->{$sname}->{clacksname_energy}, -1); # "Unknown"
            $self->{clacks}->setAndStore($self->{switches}->{$sname}->{clacksname_temperature}, -1); # "Unknown"

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
            $self->{clacks}->setAndStore($self->{switches}->{$sname}->{clacksname_energy}, $switch->energy);
            my $temperature = 0;
            my $temperaturesupported = 0;
            eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                $temperature = $switch->temperature;
                $temperature /= 10.0; # Need to convert from 0.1°C units to 1°C Units
                $temperaturesupported = 1;
            };
            if(!$temperaturesupported) {
                print STDERR "****** 'TEMPERATURE' NOT SUPPORTED BY THIS VERSION OF AHA.pm\n";
                print STDERR "****** WE NEED 0.6\n";
                `kill -9 $PID`;
            }
            $self->{clacks}->setAndStore($self->{switches}->{$sname}->{clacksname_temperature}, $temperature);

            # Remember the AIN
            my $ain = $switch->ain();
            $self->{switches}->{$sname}->{ain} = $switch->ain();
        }
    }

    foreach my $key (keys %{$self->{switches}}) {
        if(!defined($self->{switches}->{$key}->{state})) {
            $reph->debuglog("Switch $key not known to Fritz!Box");
        } else {
            my $disablestate = $self->{clacks}->retrieve($self->{switches}->{$key}->{clacksname_disable_state});
            my $switchstate = $self->{clacks}->retrieve($self->{switches}->{$key}->{clacksname_state});
            if(defined($disablestate) && defined($switchstate) && $disablestate == 1 && $switchstate == 1) {
                $reph->debuglog("Forcing switch $key to OFF because it is DISABLED!");
                $self->{fritz}->off($self->{switches}->{$key}->{ain});
                $self->{nextrun} = time + 5;
            }
        }
    }

    $self->{clacks}->doNetwork();


    return $workCount;
}

1;
__END__
