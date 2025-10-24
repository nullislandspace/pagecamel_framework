package PageCamel::Worker::Firewall::SyslogForwarder;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

# Do some updates and advanced parsing for accesslog. Run at once an hour. The
# Exception here is: If workCount > 0 then it will ru in the next loop too

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DBSerialize;
use MIME::Base64;
use Net::Clacks::Client;
use Net::Syslogd;
use IO::Socket::IP;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{nextrun} = 0;

    return $self;
}


sub register($self) {
    $self->register_worker("work");

    #$self->{syslogd} = Net::Syslogd->new(-LocalAddr => $self->{syslog}->{ip}, -LocalPort => 17000)
    #  or die "Error creating Syslogd listener: ", Net::Syslogd->error;
    
    $self->{udpsocket} = IO::Socket::IP->new(
        LocalAddr => $self->{syslog}->{ip},
        LocalPort => $self->{syslog}->{port},
        Proto => 'udp',
        Listen => 1,
        ReuseAddr => 1,
        Blocking => 0,
    ) or croak("$EVAL_ERROR");

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);
    $self->{clacks}->doNetwork();
    $self->{nextping} = 0;

    return;
}

sub work($self) {
    my $workCount = 0;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $now = time;
    if($now > $self->{nextping}) {
        $self->{clacks}->ping();
        $self->{nextping} = $now + 30;
        $workCount++;
    }

    $self->{clacks}->doNetwork();

    my $first = 1;
    while((my $message = $self->{clacks}->getNext())) {
        $workCount++;
        if($message->{type} eq 'disconnect') {
            $self->debuglog("Restarting clacks connection of Syslog forwarder");
            $self->{clacks}->ping();
            $self->{clacks}->doNetwork();
            $self->{nextping} = $now + 30;
            next;
        }
    }


    while(1) {
        my $message;
        $self->{udpsocket}->recv($message, 1024);
        if(!defined($message) || !length($message)) {
            last;
        }

        my $parsed = Net::Syslogd::process_message($message);
        if(!defined($parsed)) {
            $reph->debuglog("Could not parse syslog message:", Net::Syslogd->error);
            next;
        }
       my $logtext = $parsed->message();
       if(!defined($logtext)) {
            $reph->debuglog("Could not parse syslog message!");
            next;
        }

        $self->{clacks}->set('Firewall::Syslog', $logtext);
        $workCount++;

        #$reph->debuglog('Syslog: ' . $logtext);

    }
    $self->{clacks}->doNetwork();


    return $workCount;
}

1;
__END__
