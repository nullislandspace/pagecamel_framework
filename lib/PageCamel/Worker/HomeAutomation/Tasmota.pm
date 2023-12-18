package PageCamel::Worker::HomeAutomation::Tasmota;
#---AUTOPRAGMASTART---
use v5.38;
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

# Do some updates and advanced parsing for accesslog. Run at once an hour. The
# Exception here is: If workCount > 0 then it will ru in the next loop too

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DBSerialize;
use Net::Clacks::Client;
use WWW::Mechanize;
use JSON::XS qw(decode_json);

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
                        $reph->debuglog("Clacks: Can't set switch $key because Tasmota doesn't know about it!");
                    } elsif($cmsg->{data} == $self->{switches}->{$key}->{state}) {
                        $reph->debuglog("Clacks: Switch $key already in state " . $cmsg->{data});
                    } elsif($self->{switches}->{$key}->{state} == -1) {
                        $reph->debuglog("Clacks: Can't switch $key, currently not present at Tasmota");
                    } else {
                        if($cmsg->{data} == 1) {
                            my $disablestate = $self->{clacks}->retrieve($self->{switches}->{$key}->{clacksname_disable_state}) || 0;
                            if($disablestate) {
                                $reph->debuglog("Switch $key is DISABLED, not allowed to switch to ON!");
                            } else {
                                $reph->debuglog("Clacks: Switching $key to ON");
                                $self->switch_on($key);
                                $self->{nextrun} = time + 1;
                            }
                        } else {
                            $reph->debuglog("Clacks: Switching $key to OFF");
                            $self->switch_off($key);
                            $self->{nextrun} = time + 1;
                        }
                        $workCount++;
                    }
                    last;
                }
            }
        }
    }
    $self->{clacks}->doNetwork();
    
    # Only read states from Tasmota every 3 seconds, unless switches have been changed via clacks
    if($now > $self->{nextrun}) {
        #$reph->debuglog("_");
        $self->{nextrun} = time + 3;
    } else {
        return $workCount;
    }

    foreach my $switch (keys %{$self->{switches}}) {
        my $state = $self->switch_state($switch);
        if(!defined($state)) {
            $reph->debuglog("Switch $switch NOT PRESENT!");
            $self->{clacks}->setAndStore($self->{switches}->{$switch}->{clacksname_ispresent}, 0);
            $self->{clacks}->setAndStore($self->{switches}->{$switch}->{clacksname_state}, -1); # "Unknown"
            $self->{switches}->{$switch}->{state} = -1;
        } else {
            $self->{clacks}->setAndStore($self->{switches}->{$switch}->{clacksname_ispresent}, 1);
            if($state) {
                $self->{clacks}->setAndStore($self->{switches}->{$switch}->{clacksname_state}, 1); # ON
                $self->{switches}->{$switch}->{state} = 1;
            } else {
                $self->{clacks}->setAndStore($self->{switches}->{$switch}->{clacksname_state}, 0); # OFF
                $self->{switches}->{$switch}->{state} = 0;
            }

        }
    }

    foreach my $switch (keys %{$self->{switches}}) {
        if(!defined($self->{switches}->{$switch}->{state})) {
            $reph->debuglog("Switch $switch not known to Tasmota");
        } else {
            my $disablestate = $self->{clacks}->retrieve($self->{switches}->{$switch}->{clacksname_disable_state});
            my $switchstate = $self->{clacks}->retrieve($self->{switches}->{$switch}->{clacksname_state});
            if(defined($disablestate) && defined($switchstate) && $disablestate == 1 && $switchstate == 1) {
                $reph->debuglog("Forcing switch $switch to OFF because it is DISABLED!");
                $self->switch_off($switch);
                $self->{nextrun} = time + 1;
            }
        }
    }

    $self->{clacks}->doNetwork();


    return $workCount;
}

sub runCommand($self, $command, $option = undef) {

    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $url = 'http://' . $self->{hostname} . '/cm?user=' . $self->{username} . '&password=' . $self->{password} . '&cmnd=' . $command;
    if(defined($option)) {
        $url .= '%20' . $option;
    }

    my $mech = WWW::Mechanize->new(timeout => 10);
    my $result;
    my $success;
    if(!(eval {
        $result = $mech->get($url);
        $success = 1;
        1;
    })) {
        $success = 0;
    }

    if(!$success || !defined($result) || !$result->is_success || $result->code ne '200') {
        $reph->debuglog("Failed to connect to Tasmota sensor at " . $self->{hostname});
        return;
    }

    my $doc = $result->content;
    my $data = decode_json $doc;
    return $data;
}

sub switch_on($self, $switch) {

    my $tasmotaname = $self->{switches}->{$switch}->{switch};
    
    my $state = $self->runCommand($tasmotaname, 'ON');
    if(!defined($state) || !defined($state->{$tasmotaname})) {
        return;
    } elsif($state->{$tasmotaname} eq 'ON') {
        return 1;
    }

    return 0;

}

sub switch_off($self, $switch) {

    my $tasmotaname = $self->{switches}->{$switch}->{switch};
    
    my $state = $self->runCommand($tasmotaname, 'OFF');
    if(!defined($state) || !defined($state->{$tasmotaname})) {
        return;
    } elsif($state->{$tasmotaname} eq 'ON') {
        return 1;
    }

    return 0;
}

sub switch_state($self, $switch) {

    my $tasmotaname = $self->{switches}->{$switch}->{switch};
    
    my $state = $self->runCommand($tasmotaname);
    if(!defined($state) || !defined($state->{$tasmotaname})) {
        return;
    } elsif($state->{$tasmotaname} eq 'ON') {
        return 1;
    }

    return 0;
}

1;
__END__
