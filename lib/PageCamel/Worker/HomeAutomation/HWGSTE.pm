package PageCamel::Worker::HomeAutomation::HWGSTE;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.6;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

# Do some updates and advanced parsing for accesslog. Run at once an hour. The
# Exception here is: If workCount > 0 then it will ru in the next loop too

use base qw(PageCamel::Worker::BaseModule);
use Net::Clacks::Client;
use WWW::Mechanize;
use XML::Simple;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{nextrun} = 0;

    return $self;
}


sub register {
    my $self = shift;
    $self->register_worker("work");

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);
    $self->{clacks}->doNetwork();
    $self->{nextping} = 0;

    return;
}

sub work {
    my ($self) = @_;

    my $workCount = 0;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $now = time;
    if($now > $self->{nextping}) {
        $self->{clacks}->ping();
        $self->{nextping} = $now + 30;
        $workCount++;
    }

    $self->{clacks}->doNetwork();

    while((my $message = $self->{clacks}->getNext())) {
        $workCount++;
        if($message->{type} eq 'disconnect') {
            $self->debuglog("Restarting clacks connection");
            $self->{clacks}->ping();
            $self->{clacks}->doNetwork();
            $self->{nextping} = $now + 30;
            next;
        }
    }

    # Do the updates not dependant on recieving stuff over the
    # network only every 10 seconds to reduce processor and database load
    if($now > $self->{nextrun}) {
        $self->{nextrun} = time + 10;
    } else {
        return $workCount;
    }

    my $data = $self->getClimate();
    if(defined($data)) {
        $workCount++;
        # Both SET and STORE the data
        if(defined($data->{temperature}) && defined($self->{clacksname_temperature})) {
            $self->{clacks}->setAndStore($self->{clacksname_temperature}, $data->{temperature});
        }
        if(defined($data->{humidity}) && defined($self->{clacksname_humidity})) {
            $self->{clacks}->setAndStore($self->{clacksname_humidity}, $data->{humidity});
        }
        $reph->debuglog('HWGSTE ' . $self->{hostname} . ': ' . $data->{temperature} . 'C, ' . $data->{humidity} . '%');
    } 
    $self->{clacks}->doNetwork();

    return $workCount;
}

sub getClimate {
    my ($self) = @_;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my %pos = (
        temperature => 999,
        humidity => 999,
    );

    my $mech = WWW::Mechanize->new();
    my $result;
    my $success;
    if(!(eval {
        $result = $mech->get('http://' . $self->{hostname} . '/values.xml');
        $success = 1;
        1;
    })) {
        $success = 0;
    }

    if(!$success || !defined($result) || !$result->is_success || $result->code ne '200') {
        $reph->debuglog("Failed to connect to HWGSTE sensor at " . $self->{hostname});
        return;
    }

    my $doc = $result->content;
    my $xml = XMLin($doc, ForceArray => ['Entry']);

    foreach my $sensor (@{$xml->{SenSet}->{Entry}}) {
        my $value = $sensor->{Value};
        my $name = lc $sensor->{Name};
        $pos{$name} = $value;
    }

    return \%pos;
}

1;
__END__
