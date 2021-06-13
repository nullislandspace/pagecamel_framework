package PageCamel::Worker::HomeAutomation::KeepRange;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.6;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
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
    $self->{clacks} = $self->newClacksFromConfig($clconf);
    $self->{clacks}->listen($self->{clacksname_mode});
    $self->{clacks}->listen($self->{clacksname_inhibit});
    $self->{clacks}->listen($self->{clacksname_min});
    $self->{clacks}->listen($self->{clacksname_max});
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
        ]) or croak("Failed to create setting switch_mode!");

    $sysh->createText(modulename => $self->{modname},
                    settingname => 'inhibit_device',
                    settingvalue => 0,
                    description => 'Inhibit device without changing its control mode',
                    processinghints => [
                        'type=switch'
                                        ])
        or croak("Failed to create setting inhibit_device!");

    $sysh->createNumber(modulename => $self->{modname},
                    settingname => 'min_value',
                    settingvalue => $self->{min},
                    description => 'Switch ON of sensor falls below this value',
                    value_min => -999_999.0,
                    value_max =>  999_999.0,
                    processinghints => [
                        'decimal=3',
                    ],
                    )
        or croak("Failed to create setting min_value!");

    $sysh->createNumber(modulename => $self->{modname},
                    settingname => 'max_value',
                    settingvalue => $self->{max},
                    description => 'Switch ON of sensor falls below this value',
                    value_min => -999_999.0,
                    value_max =>  999_999.0,
                    processinghints => [
                        'decimal=3',
                    ],
                    )
        or croak("Failed to create setting max_value!");

    my %sysmap = (
        switch_mode => 'clacksname_mode',
        inhibit_device => 'clacksname_inhibit',
        min_value => 'clacksname_min',
        max_value => 'clacksname_max',
    );
    $self->{sysmap} = \%sysmap;

    foreach my $key (keys %{$self->{sysmap}}) {
        my ($ok, $setref) = $sysh->get($self->{modname}, $key);
        if(!$ok || !defined($setref->{settingvalue})) {
            croak("Failed to read setting $key");
        }

        # Store only, don't broadcast
        $self->{clacks}->store($self->{$self->{sysmap}->{$key}}, $setref->{settingvalue});
    }

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
        if($cmsg->{type} eq 'set') {
            $self->{nextrun} = 0; # Make sure we react quickly to clacks input
        }
        if($cmsg->{type} eq 'disconnect') {
            $self->debuglog("Restarting clacks connection");
            $self->{clacks}->listen($self->{clacksname_mode});
            $self->{clacks}->listen($self->{clacksname_inhibit});
            $self->{clacks}->listen($self->{clacksname_min});
            $self->{clacks}->listen($self->{clacksname_max});
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
        } elsif($cmsg->{type} eq 'set' && $cmsg->{name} eq $self->{clacksname_inhibit}) {
            my $val = $cmsg->{data};
            if($val eq '0' || $val eq '1') {
                # Store in clacks and systemsettings
                $reph->debuglog($self->{modname} . ' setting inhibit mode to ' . $val);
                $self->{clacks}->store($self->{clacksname_inhibit}, $val);
                $sysh->set($self->{modname}, 'inhibit_device', $val);
            }
        } elsif($cmsg->{type} eq 'set' && $cmsg->{name} eq $self->{clacksname_min}) {
            my $val = $cmsg->{data};
            if($val ne '') {
                # Store in clacks and systemsettings
                $reph->debuglog($self->{modname} . ' setting min_value mode to ' . $val);
                $self->{clacks}->store($self->{clacksname_min}, $val);
                $sysh->set($self->{modname}, 'min_value', $val);
            }
        } elsif($cmsg->{type} eq 'set' && $cmsg->{name} eq $self->{clacksname_max}) {
            my $val = $cmsg->{data};
            if($val ne '') {
                # Store in clacks and systemsettings
                $reph->debuglog($self->{modname} . ' setting max_value mode to ' . $val);
                $self->{clacks}->store($self->{clacksname_max}, $val);
                $sysh->set($self->{modname}, 'max_value', $val);
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
    foreach my $key (keys %{$self->{sysmap}}) {
        my ($ok, $setref) = $sysh->get($self->{modname}, $key);
        if(!$ok || !defined($setref->{settingvalue})) {
            croak("Failed to read setting $key");
        }


        my $clacksval = $self->{clacks}->retrieve($self->{$self->{sysmap}->{$key}});
        if($clacksval ne $setref->{settingvalue}) {
            # Store only, don't broadcast
            $self->{clacks}->store($self->{$self->{sysmap}->{$key}}, $setref->{settingvalue});
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
    my $switchmode = $self->{clacks}->retrieve($self->{clacksname_mode});
    my $switchstate = $self->{clacks}->retrieve($self->{clacksname_switchstate});
    my $inhibit = $self->{clacks}->retrieve($self->{clacksname_inhibit});
    my $min = $self->{clacks}->retrieve($self->{clacksname_min});
    my $max = $self->{clacks}->retrieve($self->{clacksname_max});
    if(!defined($switchstate) || $switchstate == -1) {
        # There is really nothing we can do if we can't reach the switch except wait
        # to see if it will "come back"
        $reph->debuglog($self->{modname} . ' invalid switch state');
    } elsif($inhibit) {
        # "Inhibit" means inhibit control, not shutdown the controlled devices
        # So just do nothing
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
        } elsif($switchstate == 0 && $sensorvalue < $min) {
            $reph->debuglog($self->{modname} . ' switching ON');
            $self->{clacks}->set($self->{clacksname_switchcommand}, 1);
        } elsif($switchstate == 1 && $sensorvalue > $max) {
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
