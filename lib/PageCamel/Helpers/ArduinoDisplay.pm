package PageCamel::Helpers::ArduinoDisplay;
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

use Device::SerialPort qw( :PARAM :STAT 0.07 );
use Time::HiRes qw[sleep];
use MIME::Base64;

sub new($proto, $config) {
    my $class = ref($proto) || $proto;

    my $self = bless $config, $class;

    my @displaybuffer = ('#');
    $self->{states}->{displaybuffer} = \@displaybuffer;

    $self->{arduino} = Device::SerialPort->new($self->{port}) or croak("Modem error $ERRNO");

    $self->{arduino}->baudrate(115_200);
    $self->{arduino}->parity('none');
    $self->{arduino}->databits(8);
    $self->{arduino}->stopbits(1);

    $self->{isReading} = 0;
    $self->{inSerial} = [];
    $self->{decodedEvents} = [];
    sleep(3);

    return $self;
}

sub getEvents($self) {
    while(1) {
        my ($count, $data) = $self->{arduino}->read(1);
        last if(!$count);


        if(!$self->{isReading} && ord($data) == 0x02) { # STX
            $self->{isReading} = 1;
            @{$self->{inSerial}} = ();
            next;
        }

        next unless($self->{isReading});

        if(ord($data) == 0x03) { # ETX
            $self->{isReading} = 0;
            $self->decodeSerial();
            next;
        }
        #print "** ", ord($data), " **\n";

        push @{$self->{inSerial}}, ord($data);
    }

    if(@{$self->{decodedEvents}}) {
        return shift @{$self->{decodedEvents}};
    }

    return;
}


sub decodeSerial($self) {
    my $cavacdecoded;

    while(scalar @{$self->{inSerial}} > 1) {
        my $upper = shift @{$self->{inSerial}};
        my $lower = shift @{$self->{inSerial}};
        $cavacdecoded .= chr((($upper - 65) << 4) + ($lower - 65));
    }

    push @{$self->{decodedEvents}}, $cavacdecoded;

    return;
}

sub blankDisplay($self) {
    for(my $i = 0; $i < 7; $i++) {
        $self->writeDisplay($i, $self->leftPad(''));
    }

    return;
}

sub writeDisplay($self, $displaynum, $data) {
    return if($data eq $self->{states}->{displaybuffer}->[$displaynum]); # already displayed

    $self->{states}->{displaybuffer}->[$displaynum] = $data;

    $data = join('', reverse split(//, $data));

    return $self->writePacket(chr($displaynum) . $data);
}

sub writePacket($self, $binarydata) {
    my $outdata = chr(0x02); # STX

    foreach my $part (split//, $binarydata) {
        my $upper = ((ord($part) & 0xf0) >> 4) + 65;
        my $lower = (ord($part) & 0x0f)  + 65;
        $outdata .= chr($upper) . chr($lower);
    }

    $outdata .= chr(0x03); # ETX

    $self->{arduino}->write($outdata);

    sleep(0.05);

    return;
}

# This is a very general call to "send your sensor data packet". The answer is very implementation dependant
sub sendEnquiry($self) {
    $self->{arduino}->write(chr(0x05)); # ENQ

    sleep(0.05);

    return;
}

sub secondsToTimestring($self, $val) {
    $val = 0 + $val;
    if($val < 0) {
        $val = 0;
    }

    my $seconds = $val % 60;
    $val = int($val / 60);
    my $minutes = $val % 60;
    my $hours = int($val / 60);
    while(length($seconds) < 2) {
        $seconds = '0' . $seconds;
    }
    while(length($minutes) < 2) {
        $minutes = '0' . $minutes;
    }
    while(length($hours) < 2) {
        $hours = '0' . $hours;
    }

    return $self->leftPad($self->numberToString($hours . '-' . $minutes . '-' . $seconds));
}

sub numberToString($self, $num) {
    my $val = '';
    my @binaries = $self->get7Segment();

    foreach my $part (split//, $num) {
        if($part eq ' ') { # Space
            $val .= chr(0x00);
            next;
        } elsif($part eq '.') {
            if($val eq '') {
                $val = 0x80;
            } else {
                # Add decimal point to the last pushed element
                my @elems = split//, $val;
                my $lastpart = pop @elems;
                $lastpart = chr(ord($lastpart) | 0x80);
                $val = join('', @elems, $lastpart);
                next;
            }
        } elsif($part eq '-') {
            $val .= chr(0x01);
            next;
        } elsif($part eq '_') {
            $val .= chr($binaries[24]);
            next;
        } elsif(uc $part eq 'A') {
            $val .= chr($binaries[0x0a]);
            next;
        } elsif(uc $part eq 'B') {
            $val .= chr($binaries[0x0b]);
            next;
        } elsif(uc $part eq 'C') {
            $val .= chr($binaries[0x0c]);
            next;
        } elsif(uc $part eq 'D') {
            $val .= chr($binaries[0x0d]);
            next;
        } elsif(uc $part eq 'E') {
            $val .= chr($binaries[0x0e]);
            next;
        } elsif(uc $part eq 'F') {
            $val .= chr($binaries[0x0f]);
            next;
        } elsif(uc $part eq 'P') {
            $val .= chr($binaries[19]);
            next;
        } elsif(ord($part) < 32 && defined($binaries[ord($part)])) {
            $val .= chr($binaries[ord($part)]);
            next;
        }

        $part = 0 + $part;

        $val .= chr($binaries[$part]);
    }

    return $val;
}

sub leftPad($self, $val, $padbyte = 0x00) {
    while(length($val) < 8) {
        $val = chr($padbyte) . $val;
    }

    return $val;
}

sub rightPad($self, $val, $padbyte = 0x00) {
    while(length($val) < 8) {
        $val .= chr($padbyte);
    }

    return $val;
}

sub get7Segment {
    return (
        0b01111110,  # 0
        0b00110000,  # 1
        0b01101101,  # 2
        0b01111001,  # 3
        0b00110011,  # 4
        0b01011011,  # 5
        0b01011111,  # 6
        0b01110000,  # 7
        0b01111111,  # 8
        0b01111011,  # 9
        0b01110111,  # A
        0b00011111,  # b
        0b01001110,  # C
        0b00111101,  # d
        0b01001111,  # E
        0b01000111,  # F
        0b01000000,  # 16 = I1
        0b01000001,  # 17 = I2
        0b01001001,  # 18 = I3
        0b01100111,  # 19 = P
        0b00001000,  # 20 = Escape
        0b01100011,  # 21 = IR
        0b00011101,  # 22 = POWER
        0b00000111,  # 23 = Backspace
        0b00001000,  # 24 = Underline
    );
}

1;
