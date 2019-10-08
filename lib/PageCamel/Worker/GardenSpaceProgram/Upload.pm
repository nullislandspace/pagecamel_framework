package PageCamel::Worker::GardenSpaceProgram::Upload;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.3;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

# Do some updates and advanced parsing for accesslog. Run at once an hour. The
# Exception here is: If workCount > 0 then it will ru in the next loop too

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DBSerialize;
use MIME::Base64;
use Net::Clacks::Client;
use PageCamel::Helpers::FileSlurp qw(slurpBinFile);
use MIME::Base64;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my $clconf = $self->{server}->{modules}->{$self->{local}};
    $self->{localclacks} = Net::Clacks::Client->new($clconf->get('host'), $clconf->get('port'), $clconf->get('user'), $clconf->get('password'), $self->{PSAPPNAME} . ':' . $self->{modname});

    $clconf = $self->{server}->{modules}->{$self->{remote}};
    $self->{remoteclacks} = Net::Clacks::Client->new($clconf->get('host'), $clconf->get('port'), $clconf->get('user'), $clconf->get('password'), $self->{PSAPPNAME} . ':' . $self->{modname});

    return $self;
}


sub register {
    my $self = shift;
    $self->register_worker("work");
    return;
}

sub crossregister {
    my ($self) = @_;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    # Listen for new files
    foreach my $framename (@{$self->{item}}) {
        print "Listening for frame $framename\n";
        $self->{localclacks}->listen('GSP::' . $framename);
    }
    $self->{localclacks}->doNetwork();
    $self->{remoteclacks}->doNetwork();
    $self->{localnextping} = 0;
    $self->{remotenextping} = 0;

    return;

}


sub work {
    my ($self) = @_;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $workCount = 0;

    my $now = time;
    if($now > $self->{localnextping}) {
        $self->{localclacks}->ping();
        $self->{localnextping} = $now + 30;
        $workCount++;
    }
    if($now > $self->{remotenextping}) {
        $self->{remoteclacks}->ping();
        $self->{remotenextping} = $now + 30;
        $workCount++;
    }

    $self->{localclacks}->doNetwork();
    $self->{remoteclacks}->doNetwork();

    my $first = 1;
    while((my $message = $self->{localclacks}->getNext())) {
        $workCount++;
        if($message->{type} eq 'disconnect') {
            foreach my $framename (@{$self->{item}}) {
                print "Listening for frame $framename\n";
                $self->{localclacks}->listen('GSP::' . $framename);
            }
            $self->{localclacks}->ping();
            $self->{localclacks}->doNetwork();
            $self->{localnextping} = $now + 30;
            next;
        } elsif($message->{type} eq 'set') {
            my $key = $message->{name};
            #$reph->debuglog("Sending $key");

            $self->{remoteclacks}->set($key, $message->{data});
        }

    }

    while((my $message = $self->{remoteclacks}->getNext())) {
        $workCount++;
        if($message->{type} eq 'disconnect') {
            # Empty local queue
            $self->{localclacks}->doNetwork();
            while((my $message = $self->{localclacks}->getNext())) {
                $reph->debuglog("Ignoring local data due to remote disconnect");
            }

            $self->{remoteclacks}->ping();
            $self->{remoteclacks}->doNetwork();
            $self->{remotenextping} = $now + 30;
            next;
        }
    }
    $self->{localclacks}->doNetwork();
    $self->{remoteclacks}->doNetwork();

    return $workCount;
}


1;
