package PageCamel::Worker::GardenSpaceProgram::Modem;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

# Do some updates and advanced parsing for accesslog. Run at once an hour. The
# Exception here is: If workCount > 0 then it will ru in the next loop too

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DBSerialize;
use MIME::Base64;
use Net::Clacks::Client;
use Device::SerialPort qw( :PARAM :STAT 0.07 );

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);

    my $modem = Device::SerialPort->new('/dev/ttyACM0') or croak("Modem error $ERRNO");

    $modem->baudrate(115_200);
    $modem->parity('none');
    $modem->databits(8);
    $modem->stopbits(1);

    $self->{modem} = $modem;
    $self->{line} = "";

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

    $self->{clacks}->listen('GSP::SEND');
    $self->{clacks}->doNetwork();
    $self->{nextping} = 0;


    return;

}


sub work {
    my ($self) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $workCount = 0;

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.rawlog(rawpacket, direction, realsender, realreciever, command, linkpath)
                                        VALUES (?, ?, ?, ?, ?, ?)")
            or croak($dbh->errstr);

    my $now = time;
    if($now > $self->{nextping}) {
        $self->{clacks}->ping();
        $self->{nextping} = $now + 30;
        $workCount++;
    }

    $self->{clacks}->doNetwork();

    # Uplink
    while((my $message = $self->{clacks}->getNext())) {
        if($message->{type} eq 'disconnect') {
            $self->{clacks}->listen('GSP::SEND');
            $self->{clacks}->ping();
            $self->{clacks}->doNetwork();
            $self->{nextping} = $now + 30;
            next;
        }
        next unless($message->{type} eq 'set');
        next unless($message->{name} eq 'GSP::SEND');

        # Log to database
        my ($realsender, $realreciever, $command, $linkpath) = $self->decodePacket($message->{data});
        if(!$insth->execute($message->{data}, 'UPLINK', $realsender, $realreciever, $command, $linkpath)) {
            $reph->debuglog("DB ERROR: " . $dbh->errstr);
            $dbh->rollback;
        } else {
            $dbh->commit;
        }
        $reph->debuglog('> ' . $message->{data});
        $self->{modem}->write($message->{data} . "\n");
    }

    while(1) {
        my ($count, $data) = $self->{modem}->read(1);
        if(!$count) {
            last;
        }

        if($data ne "\n") {
            $self->{line} .= $data;
            next;
        }

        if($self->{line} =~ /^\<(.*)/) {
            my $frame = $1;
            if(length($frame) != 60) {
                $reph->debuglog("ERROR: INCORRECT FRAME LENGTH " . length($frame) . ' ' . $frame);
                $self->{line} = '';
                next;
            }
            my $senderid = substr $frame, 12, 2;
            $reph->debuglog('< ' . $frame . '   Sender: ' . $senderid);
            $self->{clacks}->set('GSP::RECIEVE', $frame);
            $self->{clacks}->set('GSP::RECIEVE::' . $senderid, $frame);
            $self->{clacks}->doNetwork();

            my ($realsender, $realreciever, $command, $linkpath) = $self->decodePacket($frame);
            if(!$insth->execute($frame, 'DOWNLINK', $realsender, $realreciever, $command, $linkpath)) {
                $reph->debuglog("DB ERROR: " . $dbh->errstr);
                $dbh->rollback;
            } else {
                $dbh->commit;
            }
        } elsif($self->{line} eq '+ OK') {
            $reph->debuglog("Transmitted");
        } else {
            $reph->debuglog("ERROR? " . $self->{line});
        }


        $self->{line} = '';
    }


    return $workCount;
}

sub decodePacket {
    my ($self, $rawpacket) = @_;

    my @chars = split//, $rawpacket;
    my @frame;

    # Decode to bytes
    while(@chars) {
        my $high = shift @chars;
        my $low = shift @chars;

        my $val = ((ord($high) - 65) << 4) + (ord($low) - 65);
        push @frame, $val;
    }

    my $realsender = $frame[6];
    my $realreciever = $frame[7];
    my $command = $frame[8];
    my @linkpath = (
        $frame[0], # LINKSENDER
        $frame[1], # NEXTLINK1
        $frame[2], # NEXTLINK2
        $frame[3], # NEXTLINK3
        $frame[4], # NEXTLINK4
        $frame[5], # NEXTLINK5
    );

    return($realsender, $realreciever, $command, \@linkpath);
}


1;
__END__
