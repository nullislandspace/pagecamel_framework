package PageCamel::Worker::GardenSpaceProgram::LocalCache;
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
use PageCamel::Helpers::FileSlurp qw(slurpBinFile);
use MIME::Base64;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = Net::Clacks::Client->new($clconf->get('host'), $clconf->get('port'), $clconf->get('user'), $clconf->get('password'), $self->{PSAPPNAME} . ':' . $self->{modname});

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
        $self->{clacks}->listen('GSP::' . $framename);
    }
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

    my $first = 1;
    my %sessions;
    while((my $message = $self->{clacks}->getNext())) {
        $workCount++;
        if($message->{type} eq 'disconnect') {
            foreach my $framename (@{$self->{item}}) {
                print "Listening for frame $framename\n";
                $self->{clacks}->listen('GSP::' . $framename);
            }
            $self->{clacks}->ping();
            $self->{clacks}->doNetwork();
            $self->{nextping} = $now + 30;
            next;
        } elsif($message->{type} eq 'set') {
            my $key = $message->{name};
            $reph->debuglog("Storing " . length($message->{data}) . " bytes of image data for $key");

            $self->{clacks}->store($key, $message->{data});
        }

    }

    $self->{clacks}->doNetwork();

    return $workCount;
}


1;
