package PageCamel::Worker::GardenSpaceProgram::GEO1Decoder;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp;
our $VERSION = 2.4;
use autodie qw( close );
use Array::Contains;
use utf8;
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

    $self->{clacks}->listen('GSP::RECIEVE::BB'); # Only listen for GEO-1 frames
    $self->{clacks}->doNetwork();
    $self->{nextping} = 0;


    return;

}


sub work {
    my ($self) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $workCount = 0;

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.geo1_status
                                        (ticks, memfree, voltage_raw, voltage_calculated, thermistor_raw, packets_in, packets_out)
                                        VALUES (?, ?, ?, ?, ?, ?, ?)")
            or croak($dbh->errstr);

    my $now = time;
    if($now > $self->{nextping}) {
        $self->{clacks}->ping();
        $self->{nextping} = $now + 30;
        $workCount++;
    }

    $self->{clacks}->doNetwork();

    while((my $message = $self->{clacks}->getNext())) {
        if($message->{type} eq 'disconnect') {
            $self->{clacks}->listen('GSP::RECIEVE::BB'); # Only listen for GEO-1 frames
            $self->{clacks}->ping();
            $self->{clacks}->doNetwork();
            $self->{nextping} = $now + 30;
            next;
        }
        next unless($message->{type} eq 'set');
        next unless($message->{name} eq 'GSP::RECIEVE::BB');

        my ($ok, $decoded) = $self->decodeFrame($message->{data});

        next unless($ok);

        if(!$insth->execute(
                    $decoded->{ticks},
                    $decoded->{memfree},
                    $decoded->{voltage_raw},
                    $decoded->{voltage_calculated},
                    $decoded->{thermistor_raw},
                    $decoded->{packets_in},
                    $decoded->{packets_out},
            )) {
            $reph->debuglog("DB ERROR: " . $dbh->errstr);
            $dbh->rollback;
        } else {
            $dbh->commit;
        }
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

    if($frame[0] != 0x11) {
        # Not directly from GEO-1
        # (Linksender does not match)
        # We ignore non-direct frames here
        return 0;
    }

    if($frame[6] != 0x11) {
        # Not originating from GEO-1
        return 0;
    }

    if($frame[8] != 1) {
        # Not a status frame
        return 0;
    }


    my $data = 12;

    my %decoded;
    $decoded{ticks} = ($frame[$data + 0] << 24) + ($frame[$data + 1] << 16) + ($frame[$data + 2] << 8) + $frame[$data + 3];

    $decoded{memfree} = ($frame[$data + 4] << 24) + ($frame[$data + 5] << 16) + ($frame[$data + 6] << 8) + $frame[$data + 7];

    my $rawvolt = ($frame[$data + 8] << 8) + $frame[$data + 9];
    my $calcvolt = int(($rawvolt / 1023.0 * 6.6) * 100) / 100;
    $decoded{voltage_raw} = $rawvolt;
    $decoded{voltage_calculated} = $calcvolt;

    $decoded{thermistor_raw} = ($frame[$data + 10] << 8) + $frame[$data + 11];

    $decoded{packets_in} = ($frame[$data + 12] << 8) + $frame[$data + 13];
    $decoded{packets_out} = ($frame[$data + 14] << 8) + $frame[$data + 15];

    $decoded{timestamp} = getISODate();
    my @parts;
    foreach my $key (sort keys %decoded) {
        push @parts, $key . '=' . $decoded{$key};
    }
    my $clacksdata = join(',', @parts);
    $self->{clacks}->set('GSP::GEO1::STATUS', $clacksdata);
    $self->{clacks}->doNetwork();
    $reph->debuglog("GEO-1 status frame: $clacksdata");


    return (1, \%decoded);
}


1;
__END__
