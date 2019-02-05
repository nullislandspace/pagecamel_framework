package PageCamel::Worker::HomeAutomation::KeepRange;
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
    $self->{clacks} = Net::Clacks::Client->new($clconf->get('host'), $clconf->get('port'), $clconf->get('user'), $clconf->get('password'), $self->{PSAPPNAME} . ':' . $self->{modname}, 0);
    $self->{clacks}->listen($self->{clacksname_mode});
    $self->{clacks}->doNetwork();
    $self->{nextping} = 0;

    return;
}

sub reload {
    my ($self) = @_;

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    $sysh->createText(modulename => $self->{modname},
        settingname => 'switch_mode',
        settingvalue => 'auto',
        description => 'Switch control mode',
        processinghints => [
            'type=tristate',
            'on=ON',
            'off=OFF',
            'auto=Automatic'
        ]) or croak("Failed to create setting websocket_encryption!");

    my ($ok, $setref) = $sysh->get($self->{modname}, 'switch_mode');
    if(!$ok || !defined($setref->{settingvalue})) {
        croak("Failed to read setting switch_mode");
    }

    # Store only, don't broadcast
    $self->{clacks}->store($self->{clacksname_mode}, $setref->{settingvalue});

    return;
}

sub work {
    my ($self) = @_;

    my $workCount = 0;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

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
        if($cmsg->{type} eq 'disconnect') {
            $self->debuglog("Restarting clacks connection");
            $self->{clacks}->listen($self->{clacksname_mode});
            $self->{clacks}->ping();
            $self->{clacks}->doNetwork();
            $self->{nextping} = $now + 30;
            next;
        } elsif($cmsg->{type} eq 'set' && $cmsg->{name} eq $self->{clacksname_mode}) {
            my $val = $cmsg->{data};
            if($val eq 'on' || $val eq 'off' || $val eq 'auto') {
                # Store in clacks and systemsettings
                $reph->debuglog($self->{modname} . ' setting control mode to ' . $val);
                $self->{clacks}->store($self->{clacksname_mode}, $val);
                $sysh->set($self->{modname}, 'switch_mode', $val);
            }
        }
    }
    $self->{clacks}->doNetwork();

    # Only work every 10 seconds or so, no need to tax the system
    if($now > $self->{nextrun}) {
        $self->{nextrun} = time + 10;
    } else {
        return $workCount;
    }


    # Check if systemsettings is different than data in clacks. If so, override data in clacks store. (Data in clacks store is only
    # used for some display stuff. Clacks can *only* change systemsettings through SET
    my $switchmode = $self->{clacks}->retrieve($self->{clacksname_mode});
    {
        my ($ok, $setref) = $sysh->get($self->{modname}, 'switch_mode');
        if(!$ok || !defined($setref->{settingvalue})) {
            croak("Failed to read setting switch_mode");
        }
        my $realswitchmode = $setref->{settingvalue};
        if($switchmode ne $realswitchmode) {
            $self->{clacks}->setAndStore($self->{clacksname_mode}, $realswitchmode);
            $switchmode = $realswitchmode;
        }
    }

    # This is the actual switching logic. We can NOT assume that everything "just works".
    # There is very little we can do in case of a switch malfunction, but it the sensor
    # fails me MUST switch to the defined "safe" state
    #
    # Safestate isn't necessarily completely safe, but is defined as the lesser of two evils.
    # For example, a humidifier without internal shutoff sensor has a safestate of "off", because
    # it's better for people to notice a dry throat than to have it rain from the ceiling.
    # On the other hand, a heater in the house with an internal overheat cutoff with the main
    # goal of preventing pipes freezing has a safestate of "on". It might heat the house to
    # tropical temperatures and waste lots of power (money), but thats still cheaper than
    # bursting pipes. Of course, it the heater (for some obscure reason) doesn't have an internal
    # safety cutoff, it has no usable safe state and should be thrown into the garbage.
    my $switchstate = $self->{clacks}->retrieve($self->{clacksname_switchstate});
    if(!defined($switchstate) || $switchstate == -1) {
        # There is really nothing we can do if we can't reach the switch except wait
        # to see if it will "come back"
        $reph->debuglog($self->{modname} . ' invalid switch state');
    } elsif($switchmode eq 'off') {
        if($switchstate == 1) {
            # Mode "manual off", but switch is still on. So turn of the device.
            $reph->debuglog($self->{modname} . ' manual OFF');
            $self->{clacks}->set($self->{clacksname_switchcommand}, 0);
        }
    } elsif($switchmode eq 'on') {
        if($switchstate == 0) {
            # Similar to above, enforce "manual on"
            $reph->debuglog($self->{modname} . ' manual ON');
            $self->{clacks}->set($self->{clacksname_switchcommand}, 1);
        }
    } elsif($switchmode eq 'auto' && ($switchstate == 0 || $switchstate == 1)) {
        # In auto mode AND if switchstate is valid check against min/max and
        # change switch if needed
        my $sensorvalue = $self->{clacks}->retrieve($self->{clacksname_sensor});
        if(!defined($sensorvalue)) {
            # Whoops, invalid sensor, switch the device to the safe state
            if($self->{safestate} eq 'on') {
                $reph->debuglog($self->{modname} . ' sensor malfunction, force ON (safestate)');
                $self->{clacks}->set($self->{clacksname_switchcommand}, 1);
            } else {
                $reph->debuglog($self->{modname} . ' sensor malfunction, force OFF (safestate)');
                $self->{clacks}->set($self->{clacksname_switchcommand}, 0);
            }
        } elsif($switchstate == 0 && $sensorvalue < $self->{min}) {
            $reph->debuglog($self->{modname} . ' switching ON');
            $self->{clacks}->set($self->{clacksname_switchcommand}, 1);
        } elsif($switchstate == 1 && $sensorvalue > $self->{max}) {
            $reph->debuglog($self->{modname} . ' switching OFF');
            $self->{clacks}->set($self->{clacksname_switchcommand}, 0);
        }
    } else {
        # Uhm, something went horribly wrong during development?
        # Try to switch to the safe state "in the blind". This might or might not work!
        $reph->debuglog($self->{modname} . ' invalid internal state, trying to switch to safestate in the blind');
        $reph->debuglog($switchstate, ' * ', $switchmode);
        if($self->{safestate} eq 'on') {
            $reph->debuglog($self->{modname} . ' internal malfunction, force ON (safestate)');
            $self->{clacks}->set($self->{clacksname_switchcommand}, 1);
        } else {
            $reph->debuglog($self->{modname} . ' internal malfunction, force OFF (safestate)');
            $self->{clacks}->set($self->{clacksname_switchcommand}, 0);
        }
    }
    $self->{clacks}->doNetwork();

    return $workCount;
}


1;
__END__
