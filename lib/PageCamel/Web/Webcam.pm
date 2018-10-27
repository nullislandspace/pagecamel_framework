package PageCamel::Web::Webcam;
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

use base qw(PageCamel::Web::BaseWebSocket);
use PageCamel::Helpers::DateStrings;
use Net::Clacks::Client;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{extrasettings} = [];
    $self->{template} = 'webcam';

    foreach my $item (@{$self->{item}}) {
        my $htmlname = lc $item->{camname};
        $htmlname =~ s/\:/_/g;
        $item->{htmlname} = $htmlname;
        $item->{clacksname} = 'Webcam::' . $item->{camname} . '::imagedata';
    }

    return $self;
}


sub wsmaskget {
    my ($self, $ua, $settings, $webdata) = @_;

    $webdata->{cameras} = $self->{item};
    if(defined($self->{bodytext})) {
        $webdata->{bodytext} = $self->{bodytext};
    }
    
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
        $self->{clacks}->listen($item->{clacksname});
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
            my $imagedata = $self->{clacks}->retrieve($item->{clacksname});
            if(defined($imagedata) && $imagedata ne '') {
                my %msg = (
                    type => 'IMAGE',
                    cameraname => $item->{htmlname},
                    varval => $imagedata,

                );

                if(!$self->wsprint(\%msg)) {
                    return 0;
                    last;
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
                next unless($cmsg->{name} eq $item->{clacksname});
                my %msg = (
                    type => 'IMAGE',
                    cameraname => $item->{htmlname},
                    varval => $cmsg->{data},

                );

                if(!$self->wsprint(\%msg)) {
                    return 0;
                    last;
                }
            }
        }
    }

    $self->{clacks}->doNetwork();

    return 1;
}

1;
__END__
