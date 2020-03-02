package PageCamel::Worker::GardenSpaceProgram::SolsticeDecoder;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.0;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

# Do some updates and advanced parsing for accesslog. Run at once an hour. The
# Exception here is: If workCount > 0 then it will ru in the next loop too

use base qw(PageCamel::Worker::BaseModule);
use Net::Clacks::Client;
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::Padding qw[doFPad];
use Data::Dumper;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);

    my $tmpstates = $self->{clacks}->retrieve('GSP::SOLSTICE::RELAISSTATE');
    if(defined($tmpstates) && length($tmpstates)) {
        @{$self->{relaisstates}} = split/,/, $tmpstates;
        print "Loaded relais states back from Clacks\n";
    } else {
        print "Loading relais states from Clacks failed, using 'unknown' value 2!\n";
        $self->{relaisstates} = [2, 2, 2, 2];
    }
    $self->{nextrelaisstate} = 0;


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

    $self->{clacks}->listen('GSP::RECIEVE::PB'); # Only listen for Solstice frames
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

    if($now > $self->{nextrelaisstate}) {
        $self->{nextrelaisstate} = $now + 60;
        $self->{clacks}->set('GSP::SOLSTICE::RELAISSTATE', join(',', @{$self->{relaisstates}}));
        $self->{clacks}->store('GSP::SOLSTICE::RELAISSTATE', join(',', @{$self->{relaisstates}}));
    }

    $self->{clacks}->doNetwork();

    while((my $message = $self->{clacks}->getNext())) {
        if($message->{type} eq 'disconnect') {
            $self->{clacks}->listen('GSP::RECIEVE::PB'); # Only listen for Solstice frames
            $self->{clacks}->ping();
            $self->{clacks}->doNetwork();
            $self->{nextping} = $now + 30;
            next;
        }
        next unless($message->{type} eq 'set');

        next unless($message->{name} eq 'GSP::RECIEVE::PB');

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

    if($frame[6] != 0xf1) {
        # Not originating from Solstice
        return 0;
    }

    if($frame[8] == 1) {
        return $self->decodeStatusFrame(@frame);
    } elsif($frame[8] == 40) {
        return $self->decodeStatus2Frame(@frame);
    } elsif($frame[8] == 41) {
        return $self->decodeVrefFrame(@frame);
    } elsif($frame[8] == 51) {
        print "Got relais state change\n";
        return $self->decodeRelaisStateChange(@frame);
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

sub decodeRelaisStateChange {
    my ($self, @frame) =@_;
    
    my $data = $frame[12];

    if($data == 1) {
        $self->{relaisstates}->[0] = 1;
    }
    if($data == 2) {
        $self->{relaisstates}->[0] = 0;
    }
    if($data == 4) {
        $self->{relaisstates}->[1] = 1;
    }
    if($data == 8) {
        $self->{relaisstates}->[1] = 0;
    }
    if($data == 16) {
        $self->{relaisstates}->[2] = 1;
    }
    if($data == 32) {
        $self->{relaisstates}->[2] = 0;
    }
    if($data == 64) {
        $self->{relaisstates}->[3] = 1;
    }
    if($data == 128) {
        $self->{relaisstates}->[3] = 0;
    }

    $self->{nextrelaisstate} = 0;
        
    return 1;
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
