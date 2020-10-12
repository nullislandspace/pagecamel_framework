package PageCamel::Worker::GardenSpaceProgram::DGN1Decoder;
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

    $self->{clacks}->listen('GSP::RECIEVE::AC'); # Only listen for DGN1 frames
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
            $self->{clacks}->listen('GSP::RECIEVE::AC'); # Only listen for DGN1 frames
            $self->{clacks}->ping();
            $self->{clacks}->doNetwork();
            $self->{nextping} = $now + 30;
            next;
        }
        next unless($message->{type} eq 'set');

        next unless($message->{name} eq 'GSP::RECIEVE::AC');

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

    $reph->debuglog("Frame type ", $frame[8], " from ", $frame[6], " recieved!");
    if($frame[6] != 0x02) {
        # Not originating from DGN1
        return 0;
    }

    if($frame[8] == 1) {
        return $self->decodeStatusFrame(@frame);
    } elsif($frame[8] == 11) {
        return $self->decodeDHTFrame(@frame);
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
        $self->{clacks}->set('GSP::DGN1::STATECHANGE', $clacksdata);
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
        $self->{clacks}->set('GSP::DGN1::STATECHANGE', $clacksdata);
    } elsif($frame[8] == 19) {
        return $self->decodeSoilCapacityData(@frame);
    } elsif($frame[8] == 32) {
        return $self->decodeRFISeriesData(@frame);
    }
    return;
}


sub decodeStatusFrame {
    my ($self, @frame) =@_;
    
    my $data = 12;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.dgn1_status
                                        (ticks, vcc, packets_in, packets_out, firmware_version, keepawake_enabled, powersave_enabled)
                                        VALUES (?, ?, ?, ?, ?, ?, ?)")
            or croak($dbh->errstr);


    my %decoded;
    $decoded{ticks} = ($frame[$data + 0] << 24) + ($frame[$data + 1] << 16) + ($frame[$data + 2] << 8) + $frame[$data + 3];
    $decoded{vcc} = ($frame[$data + 6] << 8) + $frame[$data + 13];


    $decoded{packets_in} = ($frame[$data + 12] << 8) + $frame[$data + 13];
    $decoded{packets_out} = ($frame[$data + 14] << 8) + $frame[$data + 15];

    $decoded{keepawake_enabled} = $frame[$data + 4];
    $decoded{powersave_enabled} = $frame[$data + 5];

    my $vcc = (($frame[$data + 6] << 8) + $frame[$data + 7])/1000;
    $decoded{vcc} = $vcc;

    $decoded{firmware_version} = $frame[$data + 10];

    $decoded{status_timestamp} = getISODate();
    my @parts;
    foreach my $key (sort keys %decoded) {
        push @parts, $key . '=' . $decoded{$key};
    }
    my $clacksdata = join(',', @parts);
    $self->{clacks}->set('GSP::DGN1::STATUS', $clacksdata);
    $self->{clacks}->doNetwork();
    $reph->debuglog("DGN1 status frame: $clacksdata");

    if(!$insth->execute(
                $decoded{ticks},
                $decoded{vcc},
                $decoded{packets_in},
                $decoded{packets_out},
                $decoded{firmware_version},
                $decoded{keepawake_enabled},
                $decoded{powersave_enabled},
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

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.dgn1_dht
                                        (status, temperature, humidity)
                                        VALUES (?, ?, ?)")
            or croak($dbh->errstr);


    my %decoded;

    $decoded{status} = 'UNKNOWN_ERROR';
    $decoded{temperature} = '999';
    $decoded{humidity} = '999';
    if($frame[$data + 0] == 0x00) {
        $decoded{status} = 'OK';
        $decoded{humidity} = ($frame[$data + 1] << 8) + $frame[$data + 2];
        $decoded{temperature} = ($frame[$data + 3] << 8) + $frame[$data + 4];

        # Convert back to original values
        $decoded{humidity} = $decoded{humidity} / 10;
        $decoded{temperature} = ($decoded{temperature} / 10) - 100;

        # Round
        $decoded{humidity} = $self->roundFloat($decoded{humidity}, 2);
        $decoded{temperature} = $self->roundFloat($decoded{temperature}, 2);
    } elsif($frame[$data + 0] == 0x01) {
        $decoded{status} = 'CHECKSUM_ERROR';
    } elsif($frame[$data + 0] == 0x02) {
        $decoded{status} = 'TIMEOUT_ERROR';
    } else {
        $decoded{status} = 'OTHER_ERROR';
    }

    $decoded{dht_timestamp} = getISODate();
    my @parts;
    foreach my $key (sort keys %decoded) {
        push @parts, $key . '=' . $decoded{$key};
    }
    my $clacksdata = join(',', @parts);
    $self->{clacks}->set('GSP::DGN1::DHT', $clacksdata);
    $self->{clacks}->setAndStore('GSP::DGN1::TEMPERATURE', 0 + $decoded{temperature});
    $self->{clacks}->setAndStore('GSP::DGN1::HUMIDITY', 0 + $decoded{humidity});
    $self->{clacks}->doNetwork();
    $reph->debuglog("DGN1 DHT frame: $clacksdata");

    if(!$insth->execute(
                $decoded{status},
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
