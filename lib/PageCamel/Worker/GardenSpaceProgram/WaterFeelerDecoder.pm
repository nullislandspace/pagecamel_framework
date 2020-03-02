package PageCamel::Worker::GardenSpaceProgram::WaterFeelerDecoder;
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

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);

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

    $self->{clacks}->listen('GSP::RECIEVE::CB'); # Only listen for WaterFeeler frames
    $self->{clacks}->listen('GSP::WATERFEELER::CREATESOILMEASUREMENT'); # Also do the work of creating a new soil measurement row in db
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
            $self->{clacks}->listen('GSP::RECIEVE::CB'); # Only listen for WaterFeeler frames
            $self->{clacks}->listen('GSP::WATERFEELER::CREATESOILMEASUREMENT'); # Also do the work of creating a new soil measurement row in db
            $self->{clacks}->ping();
            $self->{clacks}->doNetwork();
            $self->{nextping} = $now + 30;
            next;
        }
        next unless($message->{type} eq 'set');

        if($message->{name} eq 'GSP::WATERFEELER::CREATESOILMEASUREMENT') {
            $self->createSoilRow($message->{data});
            $workCount++;
        }
        next unless($message->{name} eq 'GSP::RECIEVE::CB');

        my ($ok) = $self->decodeFrame($message->{data});

    }

    return $workCount;
}

sub createSoilRow {
    my ($self, $rawconf) =@_;

    my ($resistance, $delay, $description) = split/\|/, $rawconf;
    
    my $data = 12;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.waterfeeler_soilcapacity
                                        (selectedresistance_ohm, measurementinterval_milliseconds, description)
                                        VALUES (?, ?, ?)")
            or croak($dbh->errstr);

    if(!$insth->execute($resistance, $delay, $description)) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return 0;
    }

    $dbh->commit;
    return 1;
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

    if($frame[0] != 0x21) {
        # Not directly from WaterFeeler
        # (Linksender does not match)
        # We ignore non-direct frames here
        return 0;
    }

    if($frame[6] != 0x21) {
        # Not originating from WaterFeeler
        return 0;
    }

    if($frame[8] == 1) {
        return $self->decodeStatusFrame(@frame);
    } elsif($frame[8] == 11) {
        return $self->decodeDHTFrame(@frame);
    } elsif($frame[8] == 12) {
        return $self->decodeWaterfeelerFrame(@frame);
    } elsif($frame[8] == 15) {
        my %decoded;
        $decoded{statechange_timestamp} = getISODate();
        $decoded{statechange_text} = 'Soil capacity measurement started';
        my @parts;
        foreach my $key (sort keys %decoded) {
            push @parts, $key . '=' . $decoded{$key};
        }
        my $clacksdata = join(',', @parts);
        $self->{clacks}->set('GSP::WATERFEELER::STATECHANGE', $clacksdata);
    } elsif($frame[8] == 16) {
        my %decoded;
        $decoded{statechange_timestamp} = getISODate();
        $decoded{statechange_text} = 'Soil capacity measurement finished';
        my @parts;
        foreach my $key (sort keys %decoded) {
            push @parts, $key . '=' . $decoded{$key};
        }
        my $clacksdata = join(',', @parts);
        $self->{clacks}->set('GSP::WATERFEELER::STATECHANGE', $clacksdata);
    } elsif($frame[8] == 17) {
        my %decoded;
        $decoded{statechange_timestamp} = getISODate();
        $decoded{statechange_text} = 'Soil capacity downlink started';
        my @parts;
        foreach my $key (sort keys %decoded) {
            push @parts, $key . '=' . $decoded{$key};
        }
        my $clacksdata = join(',', @parts);
        $self->{clacks}->set('GSP::WATERFEELER::STATECHANGE', $clacksdata);
    } elsif($frame[8] == 18) {
        my %decoded;
        $decoded{statechange_timestamp} = getISODate();
        $decoded{statechange_text} = 'Soil capacity downlink finished';
        my @parts;
        foreach my $key (sort keys %decoded) {
            push @parts, $key . '=' . $decoded{$key};
        }
        my $clacksdata = join(',', @parts);
        $self->{clacks}->set('GSP::WATERFEELER::STATECHANGE', $clacksdata);
    } elsif($frame[8] == 24) {
        my %decoded;
        $decoded{statechange_timestamp} = getISODate();
        $decoded{statechange_text} = 'Testimage downlink started';
        my @parts;
        foreach my $key (sort keys %decoded) {
            push @parts, $key . '=' . $decoded{$key};
        }
        my $clacksdata = join(',', @parts);
        $self->{clacks}->set('GSP::WATERFEELER::STATECHANGE', $clacksdata);
    } elsif($frame[8] == 25) {
        my %decoded;
        $decoded{statechange_timestamp} = getISODate();
        $decoded{statechange_text} = 'Testimage downlink finished';
        my @parts;
        foreach my $key (sort keys %decoded) {
            push @parts, $key . '=' . $decoded{$key};
        }
        my $clacksdata = join(',', @parts);
        $self->{clacks}->set('GSP::WATERFEELER::STATECHANGE', $clacksdata);
    } elsif($frame[8] == 19) {
        return $self->decodeSoilCapacityData(@frame);
    } elsif($frame[8] == 26) {
        return $self->decodeImageData(@frame);
    }
    return;
}


sub decodeStatusFrame {
    my ($self, @frame) =@_;
    
    my $data = 12;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.waterfeeler_status
                                        (ticks, memfree, packets_in, packets_out, voltage_raw, voltage_calculated)
                                        VALUES (?, ?, ?, ?, ?, ?)")
            or croak($dbh->errstr);


    my %decoded;
    $decoded{ticks} = ($frame[$data + 0] << 24) + ($frame[$data + 1] << 16) + ($frame[$data + 2] << 8) + $frame[$data + 3];

    $decoded{memfree} = ($frame[$data + 4] << 24) + ($frame[$data + 5] << 16) + ($frame[$data + 6] << 8) + $frame[$data + 7];

    $decoded{packets_in} = ($frame[$data + 12] << 8) + $frame[$data + 13];
    $decoded{packets_out} = ($frame[$data + 14] << 8) + $frame[$data + 15];

    my $rawvolt = ($frame[$data + 8] << 8) + $frame[$data + 9];
    my $calcvolt = int(($rawvolt / 1023.0 * 20) * 100) / 100;
    $decoded{voltage_raw} = $rawvolt;
    $decoded{voltage_calculated} = $calcvolt;

    $decoded{status_timestamp} = getISODate();
    my @parts;
    foreach my $key (sort keys %decoded) {
        push @parts, $key . '=' . $decoded{$key};
    }
    my $clacksdata = join(',', @parts);
    $self->{clacks}->set('GSP::WATERFEELER::STATUS', $clacksdata);
    $self->{clacks}->doNetwork();
    $reph->debuglog("WATERFEELER status frame: $clacksdata");

    if(!$insth->execute(
                $decoded{ticks},
                $decoded{memfree},
                $decoded{packets_in},
                $decoded{packets_out},
                $decoded{voltage_raw},
                $decoded{voltage_calculated},
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

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.waterfeeler_dht
                                        (internal_status, internal_temperature, internal_humidity,
                                         external_status, external_temperature, external_humidity)
                                        VALUES (?, ?, ?, ?, ?, ?)")
            or croak($dbh->errstr);


    my %decoded;

    $decoded{internal_status} = 'UNKNOWN_ERROR';
    $decoded{internal_temperature} = '999';
    $decoded{internal_humidity} = '999';
    if($frame[$data + 0] == 0x00) {
        $decoded{internal_status} = 'OK';
        $decoded{internal_humidity} = ($frame[$data + 1] << 8) + $frame[$data + 2];
        $decoded{internal_temperature} = ($frame[$data + 3] << 8) + $frame[$data + 4];

        # Convert back to original values
        $decoded{internal_humidity} = $decoded{internal_humidity} / 10;
        $decoded{internal_temperature} = ($decoded{internal_temperature} / 10) - 100;

        # Round
        $decoded{internal_humidity} = $self->roundFloat($decoded{internal_humidity}, 2);
        $decoded{internal_temperature} = $self->roundFloat($decoded{internal_temperature}, 2);
    } elsif($frame[$data + 0] == 0x01) {
        $decoded{internal_status} = 'CHECKSUM_ERROR';
    } elsif($frame[$data + 0] == 0x02) {
        $decoded{internal_status} = 'TIMEOUT_ERROR';
    } else {
        $decoded{internal_status} = 'OTHER_ERROR';
    }


    $decoded{external_status} = 'UNKNOWN_ERROR';
    $decoded{external_temperature} = '999';
    $decoded{external_humidity} = '999';
    if($frame[$data + 5] == 0x00) {
        $decoded{external_status} = 'OK';
        $decoded{external_humidity} = ($frame[$data + 6] << 8) + $frame[$data + 7];
        $decoded{external_temperature} = ($frame[$data + 8] << 8) + $frame[$data + 9];

        # Convert back to original values
        $decoded{external_humidity} = $decoded{external_humidity} / 10;
        $decoded{external_temperature} = ($decoded{external_temperature} / 10) - 100;

        # Round
        $decoded{external_humidity} = $self->roundFloat($decoded{external_humidity}, 2);
        $decoded{external_temperature} = $self->roundFloat($decoded{external_temperature}, 2);
    } elsif($frame[$data + 5] == 0x01) {
        $decoded{external_status} = 'CHECKSUM_ERROR';
    } elsif($frame[$data + 5] == 0x02) {
        $decoded{external_status} = 'TIMEOUT_ERROR';
    } else {
        $decoded{external_status} = 'OTHER_ERROR';
    }

    $decoded{dht_timestamp} = getISODate();
    my @parts;
    foreach my $key (sort keys %decoded) {
        push @parts, $key . '=' . $decoded{$key};
    }
    my $clacksdata = join(',', @parts);
    $self->{clacks}->set('GSP::WATERFEELER::DHT', $clacksdata);
    $self->{clacks}->doNetwork();
    $reph->debuglog("WATERFEELER DHT frame: $clacksdata");

    if(!$insth->execute(
                $decoded{internal_status},
                $decoded{internal_temperature},
                $decoded{internal_humidity},
                $decoded{external_status},
                $decoded{external_temperature},
                $decoded{external_humidity},
        )) {
        $reph->debuglog("DB ERROR: " . $dbh->errstr);
        $dbh->rollback;
        return 0;
    }
    
    $dbh->commit;
    return 1;
}

sub decodeWaterfeelerFrame {
    my ($self, @frame) =@_;
    
    my $data = 12;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.waterfeeler_waterfeeler
                                        (volt_floating, volt_470ohm, volt_1kohm, volt_10kohm, volt_100kohm, volt_1mohm, waterlevel)
                                        VALUES (?, ?, ?, ?, ?, ?, ?)")
            or croak($dbh->errstr);


    my %decoded;

    $decoded{volt_floating} =  ($frame[$data + 0] << 8) + $frame[$data + 1];
    $decoded{volt_470ohm} =  ($frame[$data + 2] << 8) + $frame[$data + 3];
    $decoded{volt_1kohm} =  ($frame[$data + 4] << 8) + $frame[$data + 5];
    $decoded{volt_10kohm} =  ($frame[$data + 6] << 8) + $frame[$data + 7];
    $decoded{volt_100kohm} =  ($frame[$data + 8] << 8) + $frame[$data + 9];
    $decoded{volt_1mohm} =  ($frame[$data + 10] << 8) + $frame[$data + 11];
    $decoded{waterlevel} =  ($frame[$data + 12] << 8) + $frame[$data + 13];

    $decoded{waterfeeler_timestamp} = getISODate();
    my @parts;
    foreach my $key (sort keys %decoded) {
        push @parts, $key . '=' . $decoded{$key};
    }
    my $clacksdata = join(',', @parts);
    $self->{clacks}->set('GSP::WATERFEELER::WATERFEELER', $clacksdata);
    $self->{clacks}->doNetwork();
    $reph->debuglog("WATERFEELER WATERFEELER frame: $clacksdata");
    #(volt_floating, volt_470ohm, volt_1kohm, volt_10kohm, volt_100kohm, volt_1mohm, waterlevel)

    if(!$insth->execute(
                $decoded{volt_floating},
                $decoded{volt_470ohm},
                $decoded{volt_1kohm},
                $decoded{volt_10kohm},
                $decoded{volt_100kohm},
                $decoded{volt_1mohm},
                $decoded{waterlevel},
        )) {
        $reph->debuglog("DB ERROR: " . $dbh->errstr);
        $dbh->rollback;
        return 0;
    }
    
    $dbh->commit;
    return 1;
}

sub decodeSoilCapacityData {
    my ($self, @frame) =@_;
    
    my $data = 12;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};


    my %decoded;

    $decoded{framecount} = $frame[9]; # P_MEMORYOFFSET
    $decoded{payloadlength} = $frame[11] / 2; # We need number of measurements, not bytes
    for(my $i = 0; $i < $decoded{payloadlength}; $i++) {
        my $rname = 'resistance_' . doFPad(($decoded{framecount} * 8) + $i + 1, 3);
        $decoded{$rname} = $frame[$data + ($i * 2)];
        $decoded{$rname} = $decoded{$rname} << 8;
        $decoded{$rname} += $frame[$data + ($i * 2) + 1];
    }

    $decoded{soilcapacity_download_timestamp} = getISODate();
    my @parts;
    foreach my $key (sort keys %decoded) {
        push @parts, $key . '=' . $decoded{$key};
    }
    my $clacksdata = join(',', @parts);
    my $clacksname = 'GSP::WATERFEELER::SOILCAPACITY::DOWNLOAD::FRAME' . ($decoded{framecount} + 1);
    #$reph->debuglog("Sending $clacksname");
    $self->{clacks}->set($clacksname, $clacksdata);
    $self->{clacks}->doNetwork();
    $reph->debuglog("WATERFEELER SOIL CAPACITY frame: $clacksdata");

    my @cols;
    foreach my $col (sort keys %decoded) {
        next unless($col =~ /^resistance\_/);
        push @cols, $col . '=' . $decoded{$col};
    }
    my $colstring = join(',', @cols);

    # Row needs to be created when uplinking a measurement command, not on downlink
    # INSERT INTO gsp.waterfeeler_soilcapacity (selectedresistance_ohm, measurementinterval_milliseconds, description) VALUES (1000000, 500, 'test4');
    
    my $upsth = $dbh->prepare("UPDATE gsp.waterfeeler_soilcapacity
                               SET $colstring
                               WHERE logid = (
                                    SELECT max(logid) FROM gsp.waterfeeler_soilcapacity
                               )")
            or croak($dbh->errstr);

    if(!$upsth->execute()) {
        $reph->debuglog("DB ERROR: " . $dbh->errstr);
        $dbh->rollback;
        return 0;
    }
    
    $dbh->commit;
    return 1;
}

sub decodeImageData {
    my ($self, @frame) =@_;
    
    my $data = 12;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};


    my $framecount = ($frame[9] << 8) + $frame[10]; # P_MEMORYOFFSET
    my $payloadlength = $frame[11];
    my $byteoffs = $framecount * 16;
    for(my $i = 0; $i < $payloadlength; $i++) {
        my $clacksdata = 'pixeldata=' . doFPad($byteoffs + $i, 6) . '-' . doFPad($frame[$data + $i], 3);
        my $clacksname = 'GSP::WATERFEELER::SETPIXEL';
        $self->{clacks}->set($clacksname, $clacksdata);
        $self->{clacks}->doNetwork();
        #$reph->debuglog($clacksname . ' ' . $clacksdata . ' ' . $framecount);
    }

    $self->{clacks}->doNetwork();

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
