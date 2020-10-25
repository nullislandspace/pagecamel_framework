package PageCamel::Worker::GardenSpaceProgram::Solstice2Decoder;
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

# Do some updates and advanced parsing for accesslog. Run at once an hour. The
# Exception here is: If workCount > 0 then it will ru in the next loop too

use base qw(PageCamel::Worker::BaseModule);
use Net::Clacks::Client;
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::Padding qw[doFPad];

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);

    $self->{calibrated_system_volts} = 3.3;

    return $self;
}


sub register {
    my $self = shift;
    $self->register_worker("work");
    return;
}

sub crossregister {
    my ($self) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    $dbh->{disconnectIsFatal} = 1; # Don't automatically reconnect but exit instead!
    $dbh->commit;

    $self->{clacks}->listen('GSP::RECIEVE::PD'); # Only listen for Solstice frames
    $self->{clacks}->doNetwork();
    $self->{nextping} = 0;


    return;

}


sub work {
    my ($self) = @_;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $workCount = 0;

    my $now = time;
    if($now > $self->{nextping}) {
        $self->{clacks}->ping();
        $self->{nextping} = $now + 30;
        $workCount++;
    }

    $self->{clacks}->doNetwork();

    while((my $message = $self->{clacks}->getNext())) {
        if($message->{type} eq 'disconnect') {
            $self->{clacks}->listen('GSP::RECIEVE::PD'); # Only listen for Solstice frames
            $self->{clacks}->ping();
            $self->{clacks}->doNetwork();
            $self->{nextping} = $now + 30;
            next;
        }
        next unless($message->{type} eq 'set');

        next unless($message->{name} eq 'GSP::RECIEVE::PD');

        my ($ok) = $self->decodeFrame($message->{data});

    }

    return $workCount;
}

sub decodeFrame {
    my ($self, $line) = @_;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my @chars = split//, $line;
    my @frame;

    # Decode to bytes
    while(@chars) {
        my $high = shift @chars;
        my $low = shift @chars;

        my $val = ((ord($high) - 65) << 4) + (ord($low) - 65);
        push @frame, $val;
    }

    if($frame[6] != 0xf3) {
        # Not originating from Solstice2
        return 0;
    }

    if($frame[8] == 1) {
        return $self->decodeStatusFrame(@frame);
    } elsif($frame[8] == 11) {
        return $self->decodeDHTFrame(@frame);
    } elsif($frame[8] == 13) {
        return $self->decodeSwitchFrame(@frame);
    } elsif($frame[8] == 40) {
        return $self->decodeStatus2Frame(@frame);
    } elsif($frame[8] == 41) {
        return $self->decodeVrefFrame(@frame);
    } elsif($frame[8] == 60) {
        return $self->decodeBatteryStatus(@frame);
    } elsif($frame[8] == 61) {
        return $self->decodePanelStatus(@frame);
    } elsif($frame[8] == 62) {
        return $self->decodeLoadStatus(@frame);
        #return $self->dumpFramePayload(@frame);
    } elsif($frame[8] == 63) {
        return $self->dumpFramePayload(@frame);
    } elsif($frame[8] == 255) {
        return $self->dumpErrorFrame(@frame);
    } elsif($frame[8] == 33) {
        # Wake up from powersave
        my %decoded;
        $decoded{statechange_timestamp} = getISODate();
        $decoded{statechange_text} = 'WakeUp from PowerSave';
        my @parts;
        foreach my $key (sort keys %decoded) {
            push @parts, $key . '=' . $decoded{$key};
        }
        my $clacksdata = join(',', @parts);
        $self->{clacks}->set('GSP::SOLSTICE::STATECHANGE', $clacksdata);
    } elsif($frame[8] == 36) {
        # powersave shutdown
        my %decoded;
        $decoded{statechange_timestamp} = getISODate();
        $decoded{statechange_text} = 'Shutdown for PowerSave';
        my @parts;
        foreach my $key (sort keys %decoded) {
            push @parts, $key . '=' . $decoded{$key};
        }
        my $clacksdata = join(',', @parts);
        $self->{clacks}->set('GSP::SOLSTICE::STATECHANGE', $clacksdata);
    }
    return;
}

sub decodeStatusFrame {
    my ($self, @frame) =@_;
    
    my $data = 12;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.solstice_status
                                        (ticks, memfree, packets_in, packets_out, firmware_version)
                                        VALUES (?, ?, ?, ?, ?)")
            or croak($dbh->errstr);


    my %decoded;
    $decoded{ticks} = ($frame[$data + 0] << 24) + ($frame[$data + 1] << 16) + ($frame[$data + 2] << 8) + $frame[$data + 3];

    $decoded{memfree} = ($frame[$data + 4] << 24) + ($frame[$data + 5] << 16) + ($frame[$data + 6] << 8) + $frame[$data + 7];

    $decoded{packets_in} = ($frame[$data + 12] << 8) + $frame[$data + 13];
    $decoded{packets_out} = ($frame[$data + 14] << 8) + $frame[$data + 15];

    $decoded{firmware_version} = $frame[$data + 10];

    $decoded{status_timestamp} = getISODate();
    my @parts;
    foreach my $key (sort keys %decoded) {
        push @parts, $key . '=' . $decoded{$key};
    }
    my $clacksdata = join(',', @parts);
    $self->{clacks}->set('GSP::SOLSTICE::STATUS', $clacksdata);
    $self->{clacks}->doNetwork();
    $reph->debuglog("SOLSTICE status frame: $clacksdata");

    if(!$insth->execute(
                $decoded{ticks},
                $decoded{memfree},
                $decoded{packets_in},
                $decoded{packets_out},
                $decoded{firmware_version},
        )) {
        $reph->debuglog("DB ERROR: " . $dbh->errstr);
        $dbh->rollback;
        return 0;
    }

    $dbh->commit;
    return 1;
}

sub decodeStatus2Frame {
    my ($self, @frame) =@_;
    
    my $data = 12;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.solstice_status2
                                        (keepawake_flag, powersave_enabled, reboot_counter_current, reboot_counter_trigger,
                                         powersave_sleepcycle_count, powersave_keepawake_seconds)
                                        VALUES (?, ?, ?, ?, ?, ?)")
            or croak($dbh->errstr);


    my %decoded;
    $decoded{keepawake_flag} = $frame[$data + 0];
    $decoded{powersave_enabled} = $frame[$data + 2];
    $decoded{reboot_counter_current} = $frame[$data + 3];
    $decoded{reboot_counter_trigger} = $frame[$data + 4];
    $decoded{powersave_sleepcycle_count} = $frame[$data + 5];
    $decoded{powersave_keepawake_seconds} = $frame[$data + 6];

    $decoded{status2_timestamp} = getISODate();
    my @parts;
    foreach my $key (sort keys %decoded) {
        push @parts, $key . '=' . $decoded{$key};
    }
    my $clacksdata = join(',', @parts);
    $self->{clacks}->set('GSP::SOLSTICE::STATUS2', $clacksdata);
    $self->{clacks}->doNetwork();
    $reph->debuglog("SOLSTICE status2 frame: $clacksdata");

    if(!$insth->execute(
                $decoded{keepawake_flag},
                $decoded{powersave_enabled},
                $decoded{reboot_counter_current},
                $decoded{reboot_counter_trigger},
                $decoded{powersave_sleepcycle_count},
                $decoded{powersave_keepawake_seconds},
        )) {
        $reph->debuglog("DB ERROR: " . $dbh->errstr);
        $dbh->rollback;
        return 0;
    }

    $dbh->commit;
    return 1;
}

sub decodeVrefFrame {
    my ($self, @frame) =@_;
    
    my $data = 12;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.solstice_vref
                                         (system_voltage_millivolts, system_voltage_volts)
                                        VALUES (?, ?)")
            or croak($dbh->errstr);


    my %decoded;

    my $rawvolt_uncal = ($frame[$data + 0] << 8) + $frame[$data + 1];
    my $calcvolt_uncal = int(($rawvolt_uncal / 1024.0 * 20) * 100) / 100;
    $decoded{vref_voltage_uncal_raw} = $rawvolt_uncal;
    $decoded{vref_voltage_uncal_calculated} = $calcvolt_uncal;

    my $rawvolt_cal = ($frame[$data + 2] << 8) + $frame[$data + 3];
    my $calcvolt_cal = int(($rawvolt_cal / 1024.0 * 20) * 100) / 100;
    $decoded{vref_voltage_cal_raw} = $rawvolt_cal;
    $decoded{vref_voltage_cal_calculated} = $calcvolt_cal;

    $decoded{vref_system_voltage_mv} = ($frame[$data + 4] << 24) + ($frame[$data + 5] << 16) + ($frame[$data + 6] << 8) + $frame[$data + 7];
    $decoded{vref_system_voltage_volts} = int($decoded{vref_system_voltage_mv} / 10) / 100;

    $self->{calibrated_system_volts} = $decoded{vref_system_voltage_volts};

    $decoded{vref_timestamp} = getISODate();
    my @parts;
    foreach my $key (sort keys %decoded) {
        push @parts, $key . '=' . $decoded{$key};
    }
    my $clacksdata = join(',', @parts);
    $self->{clacks}->set('GSP::SOLSTICE::VREF', $clacksdata);
    $self->{clacks}->doNetwork();
    $reph->debuglog("SOLSTICE VREF frame: $clacksdata");

    if(!$insth->execute(
                $decoded{vref_system_voltage_mv},
                $decoded{vref_system_voltage_volts},
        )) {
        $reph->debuglog("DB ERROR: " . $dbh->errstr);
        $dbh->rollback;
        return 0;
    }

    $dbh->commit;
    return 1;
}

sub decodeBatteryStatus {
    my ($self, @frame) =@_;
    
    my $data = 12;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.solstice_battery
                                         (battery_volts, battery_current,
                                          battery_percentage, battery_max_voltage, battery_min_voltage)
                                        VALUES (?, ?, ?, ?, ?)")
            or croak($dbh->errstr);


    my %decoded;

    $decoded{battery_volts} = (($frame[$data + 0] << 8) + $frame[$data + 1]) / 100;

    # Battery current can be negative. Have to do the "Two's complement idiotic dance"
    my @currentbytes = ($frame[$data + 4], $frame[$data + 5], $frame[$data + 2],  $frame[$data + 3]);
    $decoded{battery_current} = unpack "N!", pack "C4", @currentbytes;
    $decoded{battery_current} = $decoded{battery_current} / 100;

    $decoded{battery_percentage} = ($frame[$data + 6] << 8) + $frame[$data + 7];
    $decoded{battery_max_voltage} = (($frame[$data + 8] << 8) + $frame[$data + 9]) / 100;
    $decoded{battery_min_voltage} = (($frame[$data + 10] << 8) + $frame[$data + 11]) / 100;

    $decoded{battery_power} = $self->roundFloat($decoded{battery_current} * $decoded{battery_volts}, 2);

    $decoded{battery_timestamp} = getISODate();

    if($decoded{battery_current} > 0) {
        $decoded{battery_mode} = 'CHARGING';
        if($decoded{battery_volts} >= 15) {
            $decoded{estimated_charge_state} = 'Equalization';
        } elsif($decoded{battery_volts} >= 14.4) {
            $decoded{estimated_charge_state} = '> 80%';
        } elsif($decoded{battery_volts} >= 12.0) {
            $decoded{estimated_charge_state} = '> 30%';
        } else {
            $decoded{estimated_charge_state} = '< 30%';
        }
    } else {
        $decoded{battery_mode} = 'DISCHARGING';
        if($decoded{battery_volts} >= 12.7) {
            $decoded{estimated_charge_state} = '100%';
        } elsif($decoded{battery_volts} >= 12.60) {
            $decoded{estimated_charge_state} = '95%';
        } elsif($decoded{battery_volts} >= 12.50) {
            $decoded{estimated_charge_state} = '90%';
        } elsif($decoded{battery_volts} >= 12.42) {
            $decoded{estimated_charge_state} = '80%';
        } elsif($decoded{battery_volts} >= 12.32) {
            $decoded{estimated_charge_state} = '70%';
        } elsif($decoded{battery_volts} >= 12.20) {
            $decoded{estimated_charge_state} = '60%';
        } elsif($decoded{battery_volts} >= 12.06) {
            $decoded{estimated_charge_state} = '50%';
        } elsif($decoded{battery_volts} >= 11.90) {
            $decoded{estimated_charge_state} = '40%';
        } elsif($decoded{battery_volts} >= 11.75) {
            $decoded{estimated_charge_state} = '30%';
        } elsif($decoded{battery_volts} >= 11.58) {
            $decoded{estimated_charge_state} = '20%';
        } elsif($decoded{battery_volts} >= 11.31) {
            $decoded{estimated_charge_state} = '10%';
        } else {
            $decoded{estimated_charge_state} = '0%';
        }
    }
    my @parts;
    foreach my $key (sort keys %decoded) {
        #    print $key, "=", $decoded{$key}, "\n";
        push @parts, $key . '=' . $decoded{$key};
    }
    my $clacksdata = join(',', @parts);
    $self->{clacks}->set('GSP::SOLSTICE::BATTERY', $clacksdata);
    $self->{clacks}->doNetwork();
    $reph->debuglog("SOLSTICE BATTERY frame: $clacksdata");

    if(!$insth->execute(
                $decoded{battery_volts},
                $decoded{battery_current},
                $decoded{battery_percentage},
                $decoded{battery_max_voltage},
                $decoded{battery_min_voltage},
        )) {
        $reph->debuglog("DB ERROR: " . $dbh->errstr);
        $dbh->rollback;
        return 0;
    }

    $dbh->commit;
    return 1;
}

sub decodePanelStatus {
    my ($self, @frame) =@_;
    
    my $data = 12;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.solstice_panel
                                         (panel_volts, panel_current, panel_power,
                                          panel_power_today, panel_power_total)
                                        VALUES (?, ?, ?, ?, ?)")
            or croak($dbh->errstr);


    my %decoded;

    $decoded{panel_volts} = (($frame[$data + 0] << 8) + $frame[$data + 1]) / 100;
    $decoded{panel_current} = (($frame[$data + 2] << 8) + $frame[$data + 3]) / 100;
    $decoded{panel_power} = (($frame[$data + 6] << 24) + ($frame[$data + 7] << 16) + ($frame[$data + 4] << 8) + $frame[$data + 5]) / 100;
    $decoded{panel_power_today} = (($frame[$data + 10] << 24) + ($frame[$data + 11] << 16) + ($frame[$data + 8] << 8) + $frame[$data + 9]) / 100;
    $decoded{panel_power_total} = (($frame[$data + 14] << 24) + ($frame[$data + 15] << 16) + ($frame[$data + 12] << 8) + $frame[$data + 13]) / 100;

    $decoded{panel_timestamp} = getISODate();
    my @parts;
    foreach my $key (sort keys %decoded) {
        #print $key, "=", $decoded{$key}, "\n";
        push @parts, $key . '=' . $decoded{$key};
    }
    my $clacksdata = join(',', @parts);
    $self->{clacks}->set('GSP::SOLSTICE::PANEL', $clacksdata);
    $self->{clacks}->doNetwork();
    $reph->debuglog("!!!! SOLSTICE PANEL frame: $clacksdata");

    if(!$insth->execute(
                $decoded{panel_volts},
                $decoded{panel_current},
                $decoded{panel_power},
                $decoded{panel_power_today},
                $decoded{panel_power_total},
        )) {
        $reph->debuglog("DB ERROR: " . $dbh->errstr);
        $dbh->rollback;
        return 0;
    }

    $dbh->commit;
    return 1;
}

sub decodeLoadStatus {
    my ($self, @frame) =@_;
    
    my $data = 12;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.solstice_load
                                         (load_volts, load_current, load_power,
                                          load_power_today, load_power_total)
                                        VALUES (?, ?, ?, ?, ?)")
            or croak($dbh->errstr);

    my %decoded;

    $decoded{load_volts} = (($frame[$data + 0] << 8) + $frame[$data + 1]) / 100;
    $decoded{load_current} = (($frame[$data + 2] << 8) + $frame[$data + 3]) / 100;
    $decoded{load_power} = (($frame[$data + 6] << 24) + ($frame[$data + 7] << 16) + ($frame[$data + 4] << 8) + $frame[$data + 5]) / 100;
    $decoded{load_power_today} = (($frame[$data + 10] << 24) + ($frame[$data + 11] << 16) + ($frame[$data + 8] << 8) + $frame[$data + 9]) / 100;
    $decoded{load_power_total} = (($frame[$data + 14] << 24) + ($frame[$data + 15] << 16) + ($frame[$data + 12] << 8) + $frame[$data + 13]) / 100;

    $decoded{load_timestamp} = getISODate();
    my @parts;
    foreach my $key (sort keys %decoded) {
        #print $key, "=", $decoded{$key}, "\n";
        push @parts, $key . '=' . $decoded{$key};
    }
    my $clacksdata = join(',', @parts);
    $self->{clacks}->set('GSP::SOLSTICE::LOAD', $clacksdata);
    $self->{clacks}->doNetwork();
    $reph->debuglog("!!!! SOLSTICE LOAD frame: $clacksdata");

    if(!$insth->execute(
                $decoded{load_volts},
                $decoded{load_current},
                $decoded{load_power},
                $decoded{load_power_today},
                $decoded{load_power_total},
        )) {
        $reph->debuglog("DB ERROR: " . $dbh->errstr);
        $dbh->rollback;
        return 0;
    }

    $dbh->commit;
    return 1;
}

sub decodeDHTFrame {
    my ($self, @frame) =@_;
    
    my $data = 12;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.solstice_dht
                                        (status, temperature, humidity)
                                        VALUES (?, ?, ?)")
            or croak($dbh->errstr);


    my %decoded;

    $decoded{dht_status} = 'UNKNOWN_ERROR';
    $decoded{temperature} = '999';
    $decoded{humidity} = '999';
    if($frame[$data + 0] == 0x00) {
        $decoded{dht_status} = 'OK';
        $decoded{humidity} = ($frame[$data + 1] << 8) + $frame[$data + 2];
        $decoded{temperature} = ($frame[$data + 3] << 8) + $frame[$data + 4];

        # Convert back to original values
        $decoded{humidity} = $decoded{humidity} / 10;
        $decoded{temperature} = ($decoded{temperature} / 10) - 100;

        # Round
        $decoded{humidity} = $self->roundFloat($decoded{humidity}, 2);
        $decoded{temperature} = $self->roundFloat($decoded{temperature}, 2);
    } elsif($frame[$data + 0] == 0x01) {
        $decoded{dht_status} = 'CHECKSUM_ERROR';
    } elsif($frame[$data + 0] == 0x02) {
        $decoded{dht_status} = 'TIMEOUT_ERROR';
    } else {
        $decoded{dht_status} = 'OTHER_ERROR';
    }

    $decoded{dht_timestamp} = getISODate();
    my @parts;
    foreach my $key (sort keys %decoded) {
        push @parts, $key . '=' . $decoded{$key};
    }
    my $clacksdata = join(',', @parts);
    $self->{clacks}->set('GSP::SOLSTICE::DHT', $clacksdata);
    $self->{clacks}->setAndStore('GSP::DHT::TEMPERATURE', 0 + $decoded{temperature});
    $self->{clacks}->setAndStore('GSP::DHT::HUMIDITY', 0 + $decoded{humidity});
    $self->{clacks}->doNetwork();
    $reph->debuglog("SOLSTICE DHT frame: $clacksdata");

    if(!$insth->execute(
                $decoded{dht_status},
                $decoded{temperature},
                $decoded{humidity},
        )) {
        $reph->debuglog("DB ERROR: " . $dbh->errstr);
        $dbh->rollback;
        return 0;
    }
    
    $dbh->commit;
    return 1;
}

sub decodeSwitchFrame {
    my ($self, @frame) =@_;
    
    my $data = 12;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.solstice_switches
                                        (powerrail_1, powerrail_2, powerrail_3, powerrail_4, door_closed)
                                        VALUES (?, ?, ?, ?, ?)")
            or croak($dbh->errstr);


    my %decoded;

    $decoded{powerrail_1} = $frame[$data + 0];
    $decoded{powerrail_2} = $frame[$data + 1];
    $decoded{powerrail_3} = $frame[$data + 2];
    $decoded{powerrail_4} = $frame[$data + 3];
    $decoded{door_closed} = $frame[$data + 4];

    $decoded{switches_timestamp} = getISODate();
    my @parts;
    foreach my $key (sort keys %decoded) {
        push @parts, $key . '=' . $decoded{$key};
    }
    my $clacksdata = join(',', @parts);
    $self->{clacks}->set('GSP::SOLSTICE::SWITCHES', $clacksdata);
    $self->{clacks}->doNetwork();
    $reph->debuglog("SOLSTICE SWITCHES frame: $clacksdata");

    if(!$insth->execute(
                $decoded{powerrail_1},
                $decoded{powerrail_2},
                $decoded{powerrail_3},
                $decoded{powerrail_4},
                $decoded{door_closed},
        )) {
        $reph->debuglog("DB ERROR: " . $dbh->errstr);
        $dbh->rollback;
        return 0;
    }
    
    $dbh->commit;
    return 1;
}


sub dumpFramePayload {
    my ($self, @frame) =@_;
    
    my $data = 12;
    print "********* FRAME TYPE ", $frame[8], "\n";
    for(my $i = 0; $i < 16; $i++) {
        print $frame[$data + $i], " ";
    }
    print "\n";
    return 1;
}

sub roundFloat {
    my ($self, $val, $digits) = @_;

    my $factor = 10**$digits;

    $val = int($val * $factor) / $factor;

    if($val =~ /\./) {
        my ($pre, $post) = split/\./, $val;
        while(length($post) < $digits) {
            $post .= '0';
        }
        $val = $pre . '.' . $post;
    } else {
        my $post = '';
        while(length($post) < $digits) {
            $post .= '0';
        }
        $val .= '.' . $post;
    }

    return $val;
}

1;
__END__
