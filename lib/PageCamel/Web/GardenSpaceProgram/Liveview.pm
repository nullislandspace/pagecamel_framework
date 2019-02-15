package PageCamel::Web::GardenSpaceProgram::Liveview;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseWebSocket);
use PageCamel::Helpers::DateStrings;
use Net::Clacks::Client;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{extrasettings} = [];

    return $self;
}


sub wsmaskget {
    my ($self, $ua, $settings, $webdata) = @_;

    return;
}

sub wshandlerstart {
    my ($self, $ua, $settings) = @_;

    $self->{nextping} = time + 10;

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = Net::Clacks::Client->new($clconf->get('host'), $clconf->get('port'), $clconf->get('user'), $clconf->get('password'), $self->{PSAPPNAME} . ':' . $self->{modname});

    $self->{clacks}->doNetwork();

    $self->{retrievecached} = 1;

    foreach my $item (@{$self->{item}}) {
        $self->{clacks}->listen('GSP::' . $item);
    }
    $self->{clacks}->doNetwork();


    return;
}

sub wscleanup {
    my ($self) = @_;

    delete $self->{nextping};
    delete $self->{clacks};

    return;
}

sub wscyclic {
    my ($self) = @_;

    if($self->{retrievecached}) {
        $self->{retrievecached} = 0;
        foreach my $item (@{$self->{item}}) {
            my $gspdata = $self->{clacks}->retrieve('GSP::' . $item);
            if(defined($gspdata) && $gspdata ne '') {
                my @parts = split/\,/, $gspdata;
                foreach my $part (@parts) {
                    my ($key, $val) = split/\=/, $part, 2;
                    my %msg = (
                        type => 'probedata',
                        sensor => $key,
                        measurement => $val,
                    );

                    if(!$self->wsprint(\%msg)) {
                        return 0;
                        last;
                    }
                }
            }
        }
    }

    $self->{clacks}->doNetwork();
    my $now = time;
    if($now > $self->{nextping}) {
        $self->{clacks}->ping();
        $self->{nextping} = $now + 10;
    }

    while(1) {
        my $cmsg = $self->{clacks}->getNext();
        last unless defined($cmsg);

        if($cmsg->{type} eq 'set') {
            foreach my $item (@{$self->{item}}) {
                next unless($cmsg->{name} eq 'GSP::' . $item);

                my @parts = split/\,/, $cmsg->{data};
                foreach my $part (@parts) {
                    my ($key, $val) = split/\=/, $part, 2;
                    my %msg = (
                        type => 'probedata',
                        sensor => $key,
                        measurement => $val,
                    );

                    if(!$self->wsprint(\%msg)) {
                        return 0;
                        last;
                    }
                }
            }
        }
    }

    $self->{clacks}->doNetwork();

    return 1;
}

1;
__END__
