package PageCamel::Helpers::AsyncUA;
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

use IO::Socket::SSL;
use IO::Socket::INET;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = bless \%config, $class;

    my $ok = 1;
    foreach my $required (qw[host use_ssl reph ua]) {
        if(!defined($self->{$required})) {
            print STDERR "Configuration $required not defined\n";
            $ok = 0;
        }
    }
    if(!$ok) {
        croak("Configuration error");
    }

    $self->{state} = 'ready';

    return $self;
}

sub get($self, $path) {
    return $self->_start_request('GET', $path);
}


sub post($self, $path, $contenttype, $body) {
    return $self->_start_request('POST', $path, $contenttype, $body);
}

sub _start_request($self, $method, $path, $contenttype = undef, $body = undef) {
    if($self->{state} ne 'ready') {
        $self->{reph}->debuglog("Trying to start a request when not ready, we are in state ", $self->{state});
        return 0;
    }

    $self->{headers} = [];
    $self->{parsedheaders} = {};
    $self->{body} = '';
    $self->{returncode} = '';
    $self->{outbox} = '';
    $self->{headerline} = '';

    $self->{outbox} .= $method . ' ' . $path . ' ' . "HTTP/1.1\r\n";
    $self->{outbox} .= 'Host: ' . $self->{host} . "\r\n";
    $self->{outbox} .= 'User-Agent: ' . $self->{ua} . "\r\n";
    if(defined($contenttype) && length($contenttype)) {
        $self->{outbox} .= 'Content-Type: ' . $contenttype . "\r\n";
    }
    if(defined($body) && length($body)) {
        $self->{outbox} .= 'Content-Length: ' . length($body) . "\r\n";
    }
    $self->{outbox} .= "\r\n";
    if(defined($body) && length($body)) {
        $self->{outbox} .= $body;
    }

    #print Dumper($self->{outbox});

    my $socket;
    if($self->{use_ssl}) {
        $socket = IO::Socket::SSL->new($self->{host} . ':443');
        if(!defined($socket)) {
            $self->{reph}->debuglog("Connection failed! error=", $ERRNO, ", ssl_error=", $SSL_ERROR);
            return 0;
        }
    } else {
        $socket = IO::Socket::INET->new($self->{host} . ':443');
        if(!defined($socket)) {
            $self->{reph}->debuglog("Connection failed: ", $IO::Socket::errstr);
            return 0;
        }
    }

    $socket->blocking(0);

    $self->{socket} = $socket;

    $self->{state} = 'sending';
    return 1;
}

sub finished($self) {
    if($self->{state} eq 'ready') {
        return 0;
    }

    if($self->{state} eq 'sending') {
        $self->_sendData();
        return 0;
    }

    if($self->{state} eq 'readheaders') {
        $self->_readHeaders();
        return 0;
    }

    if($self->{state} eq 'readbody') {
        $self->_readBody();
        return 0;
    }

    if($self->{state} eq 'finished') {
        return 1;
    }

    return 0;
}

sub _sendData($self) {
    my $brokenpipe = 0;

    my $full = $self->{outbox};
    my $written;

    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
        $written = syswrite($self->{socket}, $full);
    };
    if($EVAL_ERROR) {
        print STDERR "Write error: $EVAL_ERROR\n";
        $self->{state} = 'finished';
        $self->{returncode} = 599;
        delete $self->{socket};
        return;
    }
    if(!defined($written)) {
        $written = 0;
    } elsif($self->{socket}->error || $ERRNO ne '') {
        print STDERR "AsyncUA write failure: $ERRNO / ", $self->{socket}->opened, " / ", $self->{socket}->error, "\n";
        return;
    }
    if($written) {
        $full = substr($full, $written);
        $self->{outbox} = $full;
    }

    if(!length($full)) {
        # We are done writing
        #$self->{reph}->debuglog("Request sent");
        $self->{state} = 'readheaders';
    }

    return;
}

sub _readHeaders($self) {
    #$self->{reph}->debuglog("Read headers");
    while(1) {
        my $buf = undef;
        my $bufstatus = $self->{socket}->sysread($buf, 1);

        my $errorstatus = $self->{socket}->error;
        if(defined($errorstatus) || $ERRNO ne '') {
            if(defined($errorstatus) && $errorstatus ne '') {
                print STDERR "AsyncUA read headers failure: $ERRNO / ", $self->{socket}->opened, " / ", $self->{socket}->error, "\n";
            }
            return;
        }

        if(!defined($buf) || !length($buf)) {
            last;
        }

        if($buf eq "\r") {
            next;
        }

        if($buf eq "\n") {
            if(!length($self->{headerline})) {
                $self->{state} = 'readbody';
                last;
            }

            push @{$self->{headers}}, $self->{headerline};
            #$self->{reph}->debuglog('< ', $self->{headerline});
            $self->{headerline} = '';
            next;
        }

        $self->{headerline} .= $buf;
    }

    if($self->{state} eq 'readbody') {
        my $statusline = shift @{$self->{headers}};
        #$self->{reph}->debuglog("Status line: ", $statusline);
        my ($proto, $status, $statustext) = split/\ /, $statusline, 3;
        $self->{returncode} = $status;

        foreach my $line (@{$self->{headers}}) {
            my ($key, $val) = split/\:\ /, $line, 2;
            $self->{parsedheaders}->{lc $key} = $val;
        }
        #$self->{reph}->debuglog("Headers read");
    }

    return;
}

sub _readBody($self) {
    if(!defined($self->{parsedheaders}->{'content-length'}) || !$self->{parsedheaders}->{'content-length'}) {
        # No content, short circuit
        $self->{state} = 'finished';
        delete $self->{socket};
        $self->{reph}->debuglog("No body to read");
        return;
    }

    while(1) {
        my $buf = undef;
        my $bufstatus = $self->{socket}->sysread($buf, 1);

        my $errorstatus = $self->{socket}->error;
        if(defined($errorstatus) || $ERRNO ne '') {
            if(defined($errorstatus) && $errorstatus ne '') {
                print STDERR "AsyncUA read headers failure: $ERRNO / ", $self->{socket}->opened, " / ", $self->{socket}->error, "\n";
            }
            return;
        }

        if(!defined($buf) || !length($buf)) {
            last;
        }

        $self->{body} .= $buf;

        if(length($self->{body}) == $self->{parsedheaders}->{'content-length'}) {
            $self->{state} = 'finished';
            delete $self->{socket};
            return;
        }
    }

    return;
}

sub result($self) {
    if($self->{state} ne 'finished') {
        $self->{reph}->debuglog("Tried to get result, but we are not in state finished but in state ", $self->{state});
    }

    $self->{state} = 'ready';
    return ($self->{returncode}, $self->{parsedheaders}, $self->{body});
}

1;
