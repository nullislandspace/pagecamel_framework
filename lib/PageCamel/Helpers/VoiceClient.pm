package PageCamel::Helpers::VoiceClient;
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

use IO::Socket::IP;
use Time::HiRes qw[sleep];
use Sys::Hostname;

sub new($class, $server, $port, $username = 'unknown') {
    my $self = bless {}, $class;

    $self->{server} = $server;
    $self->{port} = $port;

    if(!defined($username)) {
        $username = 'unknown';
    }
    $self->{username} = $username;

    $self->reconnect();

    return $self;
}

sub reconnect($self) {
    if(defined($self->{socket})) {
        delete $self->{socket};
    }

    my $socket = IO::Socket::IP->new(
        PeerHost => $self->{server},
        PeerPort => $self->{port},
        Type => SOCK_STREAM,
    ) or croak("Failed to connect to VOICE service: $ERRNO");

    binmode($socket, ':bytes');
    $socket->blocking(0);

    $self->{socket} = $socket;
    $self->{lastping} = time;
    $self->{inbuffer} = '';
    $self->{outbuffer} = '';
    $self->{inlines} = ();
    $self->{serverinfo} = 'UNKNOWN';

    # Startup "handshake". As everything else, this is asyncronous, both server and
    # client send their respective version strings and then wait to recieve their counterparts
    # Also, this part is REQUIRED, just to make sure we actually speek to CLACKS protocol
    #
    # In this implementation, we wait until we recieve the server header. If we don't recieve it within
    # 20 seconds, we time out and fail.
    $self->{outbuffer} .= "PageCamel SPEAK Client $VERSION " . $self->{username} . "\r\n";
    my $timeout = time + 20;
    while(1) {
        $self->doNetwork();
        my $serverinfo = $self->getNext();
        if(!defined($serverinfo)) {
            sleep(0.0001);
            next;
        }
        if($serverinfo->{type} eq 'serverinfo') {
            $self->{serverinfo} = $serverinfo->{data};
            last;
        }
        if($timeout < time) {
            croak("TIMEOUT waiting for Clacks handshake!");
        }
    }

    return;
}

sub doNetwork($self) {
    # doNetwork interleaves handling incoming and outgoing traffic.
    # This is only relevant on slow links.
    #
    # It returns even if the outgoing or incoming buffers are not empty
    # (meaning that partially buffered data can exists). This way we use the
    # available bandwidth without blocking unduly the application (we assume it's a realtime
    # application with multiple things going on at the same time)-
    #
    # The downside of this is that doNetwork() needs to be called on a regular basis and sending
    # and recieving might be delayed until the next cycle. This delay can be minimized by simply
    # not transfering huge values over clacks, but instead using it the way it was intended to be used:
    # Small variables can be SET directly by clacks, huge datasets should be stored in the
    # database and the recievers only NOTIFY'd that a change has taken place.

    my $workCount = 0;

    if(length($self->{outbuffer})) {
        my $written = syswrite($self->{socket}, $self->{outbuffer});
        if(defined($written) && $written) {
            $workCount += $written;
            $self->{outbuffer} = substr($self->{outbuffer}, $written);
        }
    }

    while(1) {
        my $buf;
        sysread($self->{socket}, $buf, 1);
        last if(!defined($buf) || !length($buf));
        $workCount++;
        if($buf eq "\r") {
            next;
        } elsif($buf eq "\n") {
            push @{$self->{inlines}}, $self->{inbuffer};
            $self->{inbuffer} = '';
        } else {
            $self->{inbuffer} .= $buf;
        }
    }

    return $workCount;
}

sub ping($self) {
    if($self->{lastping} < (time - 120)) {
        # Only send a ping every 120 seconds or less
        $self->{outbuffer} .= "PING\r\n";
        $self->{lastping} = time;
    }

    return;
}

sub disablePing($self) {
    $self->{outbuffer} .= "NOPING\r\n";

    return;
}

sub setmike($self, $value) {
    if($value) {
        $self->{outbuffer} .= "MIKE=on\r\n";
    } else {
        $self->{outbuffer} .= "MIKE=off\r\n";
    }
    return;
}

sub setspeaker($self, $value) {
    if($value) {
        $self->{outbuffer} .= "SPEAKER=on\r\n";
    } else {
        $self->{outbuffer} .= "SPEAKER=off\r\n";
    }
    return;
}

sub setmonitor($self, $value) {
    if($value) {
        $self->{outbuffer} .= "MONITOR=on\r\n";
    } else {
        $self->{outbuffer} .= "MONITOR=off\r\n";
    }
    return;
}

sub sendvoice($self, $value) {
    $self->{outbuffer} .= "DATA=" . $value . "\r\n";
    return;
}

sub getServerinfo($self) {
    return $self->{serverinfo};
}

sub getNext($self) {
    # Recieve next incoming message (if any)

    my $line = shift @{$self->{inlines}};

    if(!defined($line)) {
        return;
    }

    my %data;
    if($line =~ /^DATA\=(.*)/) {
        %data = (
            type => 'getvoice',
            data => $1,
        );
    } elsif($line =~ /^MIKEBIAS\=(.+?)\|(.*)/) {
        %data = (
            type => 'mikebias',
            bias => $1,
            buffersize => $2,
        );
    } elsif($line =~ /PageCamel\ SPEAK\ Server\ (.*)/) {
        %data = (
            type => 'serverinfo',
            data => $1,
        );
    } else {
        # UNKNOWN, ignore
        print STDERR "####### $line\n";
        return;
    }

    return \%data;
}

1;
__END__
