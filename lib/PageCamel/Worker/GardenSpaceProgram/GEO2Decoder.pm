package PageCamel::Worker::GardenSpaceProgram::GEO2Decoder;
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

    $self->{clacks}->listen('GSP::RECIEVE::BC'); # Only listen for GEO-2 frames
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
            $self->{clacks}->listen('GSP::RECIEVE::BC'); # Only listen for GEO-2 frames
            $self->{clacks}->ping();
            $self->{clacks}->doNetwork();
            $self->{nextping} = $now + 30;
            next;
        }
        next unless($message->{type} eq 'set');
        next unless($message->{name} eq 'GSP::RECIEVE::BC');

        $workCount += $self->decodeFrame($message->{data});
    }

    return $workCount;
}

sub decodeFrame {
    my ($self, $line) = @_;

    my @chars = split//, $line;
    my @frame;

    # Decode to bytes
    while(@chars) {
        my $high = shift @chars;
        my $low = shift @chars;

        my $val = ((ord($high) - 65) << 4) + (ord($low) - 65);
        push @frame, $val;
    }

    if($frame[0] != 0x12) {
        # Not directly from GEO-2
        # (Linksender does not match)
        # We ignore non-direct frames here
        return 0;
    }

    if($frame[6] != 0x12) {
        # Not originating from GEO-1
        return 0;
    }

    if($frame[8] != 1) {
        # Not a status frame
        return 0;
    }

    if($frame[8] == 1) {
        return $self->decodeStatusFrame(@frame);
    } elsif($frame[8] == 17) {
        return $self->decodeDHT11Frame(@frame);
    } elsif($frame[8] == 18) {
        return $self->decodeFRAMStatusFrame(@frame);
    }

    # Wrong frame type
    return 0;
}

sub decodeStatusFrame {
    my ($self, @frame) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.geo2_status
                                        (ticks, memfree, voltage_raw, voltage_calculated, packets_in, packets_out)
                                        VALUES (?, ?, ?, ?, ?, ?)")
            or croak($dbh->errstr);

    my $data = 12;

    my %decoded;
    $decoded{ticks} = ($frame[$data + 0] << 24) + ($frame[$data + 1] << 16) + ($frame[$data + 2] << 8) + $frame[$data + 3];

    $decoded{memfree} = ($frame[$data + 4] << 24) + ($frame[$data + 5] << 16) + ($frame[$data + 6] << 8) + $frame[$data + 7];

    my $rawvolt = ($frame[$data + 8] << 8) + $frame[$data + 9];
    my $calcvolt = int(($rawvolt / 1023.0 * 13.2) * 100) / 100;
    $decoded{voltage_raw} = $rawvolt;
    $decoded{voltage_calculated} = $calcvolt;

    $decoded{packets_in} = ($frame[$data + 12] << 8) + $frame[$data + 13];
    $decoded{packets_out} = ($frame[$data + 14] << 8) + $frame[$data + 15];


    $decoded{timestamp_statusframe} = getISODate();
    my @parts;
    foreach my $key (sort keys %decoded) {
        push @parts, $key . '=' . $decoded{$key};
    }
    my $clacksdata = join(',', @parts);
    $self->{clacks}->set('GSP::GEO2::STATUS', $clacksdata);
    $self->{clacks}->doNetwork();
    $reph->debuglog("GEO-2 status frame: $clacksdata");


    if(!$insth->execute(
                $decoded{ticks},
                $decoded{memfree},
                $decoded{voltage_raw},
                $decoded{voltage_calculated},
                $decoded{packets_in},
                $decoded{packets_out},
        )) {
        $reph->debuglog("DB ERROR: " . $dbh->errstr);
        $dbh->rollback;
        return 0;
    } else {
        $dbh->commit;
        return 1;
    }
}

sub decodeDHT11Frame {
    my ($self, @frame) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.geo2_dht11
                                        (is_ok, errortype, temperature, humidity)
                                        VALUES (?, ?, ?, ?)")
            or croak($dbh->errstr);

    my $data = 12;

    my %decoded;
    $decoded{status} = $frame[$data + 0];
    if($decoded{is_ok} == 0) {
        $decoded{errortype} = '';
    } elsif($decoded{status} == 1) {
        $decoded{errortype} = 'CHECKSUM';
    } elsif($decoded{status} == 2) {
        $decoded{errortype} = 'TIMEOUT';
    } else {
        $decoded{errortype} = 'UNKNOWN';
    }

    if($decoded{status} == 0) {
        $decoded{is_ok} = 1;

        $decoded{humidity} = $frame[$data + 1];

        my $calctemp = ($frame[$data + 2] << 8) + $frame[$data + 3];
        $calctemp -= 300;
        $decoded{temperature} = $calctemp;

    } else {
        $decoded{is_ok} = 0;
        $decoded{temperature} = 0;
        $decoded{humidity} = 0;
    }


    $decoded{timestamp_dht11frame} = getISODate();
    my @parts;
    foreach my $key (sort keys %decoded) {
        push @parts, $key . '=' . $decoded{$key};
    }
    my $clacksdata = join(',', @parts);
    $self->{clacks}->set('GSP::GEO2::DHT11', $clacksdata);
    $self->{clacks}->doNetwork();
    $reph->debuglog("GEO-2 DHT11 frame: $clacksdata");


    if(!$insth->execute(
                $decoded{is_ok},
                $decoded{errortype},
                $decoded{temperature},
                $decoded{humidity},
        )) {
        $reph->debuglog("DB ERROR: " . $dbh->errstr);
        $dbh->rollback;
        return 0;
    } else {
        $dbh->commit;
        return 1;
    }
}

sub decodeFRAMStatusFrame {
    my ($self, @frame) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.geo2_framstatus
                                        (write_pointer, replay_start_pointer, replay_end_pointer, replay_current_pointer, replay_delay, replay_active)
                                        VALUES (?, ?, ?, ?)")
            or croak($dbh->errstr);

    my $data = 12;

    my %decoded;
    my $offs = 0;
    foreach my $key (qw/write_pointer replay_start_pointer replay_end_pointer replay_current_pointer replay_delay/) {
        my $val = ($frame[$data + $offs] << 8) + $frame[$data + $offs + 1];
        $decoded{$key} = $val;
        $offs += 2;
    }
    if($frame[$data + 10] == 0) {
        $decoded{replay_active} = 0;
    } else {
        $decoded{replay_active} = 1;
    }


    $decoded{timestamp_framframe} = getISODate();
    my @parts;
    foreach my $key (sort keys %decoded) {
        push @parts, $key . '=' . $decoded{$key};
    }
    my $clacksdata = join(',', @parts);
    $self->{clacks}->set('GSP::GEO2::FRAM', $clacksdata);
    $self->{clacks}->doNetwork();
    $reph->debuglog("GEO-2 FRAM frame: $clacksdata");


    if(!$insth->execute(
                $decoded{write_pointer},
                $decoded{replay_start_pointer},
                $decoded{replay_end_pointer},
                $decoded{replay_current_pointer},
                $decoded{replay_delay},
                $decoded{replay_active},
        )) {
        $reph->debuglog("DB ERROR: " . $dbh->errstr);
        $dbh->rollback;
        return 0;
    } else {
        $dbh->commit;
        return 1;
    }
}


1;
__END__
