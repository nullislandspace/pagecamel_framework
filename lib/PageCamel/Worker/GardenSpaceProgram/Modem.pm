package PageCamel::Worker::GardenSpaceProgram::Modem;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 1;
use Fatal qw( close );
use Array::Contains;
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
    $self->{clacks} = Net::Clacks::Client->new($clconf->get('host'), $clconf->get('port'), $clconf->get('user'), $clconf->get('password'), $self->{PSAPPNAME} . ':' . $self->{modname});

    my $modem = Device::SerialPort->new('/dev/ttyACM0') or die("Modem error $!");

    $modem->baudrate(115200);
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

    my $insth = $dbh->prepare_cached("INSERT INTO gsp.rawlog(mission, rawpacket, direction)
                                        VALUES ('FASTCORE', ?, ?)")
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
        if(!$insth->execute($message->{data}, 'UPLINK')) {
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
            my $senderid = substr $frame, 12, 2;
            $reph->debuglog('< ' . $frame);
            $self->{clacks}->set('GSP::RECIEVE', $frame);
            $self->{clacks}->set('GSP::RECIEVE::' . $senderid, $frame);
            $self->{clacks}->doNetwork();
            if(!$insth->execute($frame, 'DOWNLINK')) {
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


1;
__END__
