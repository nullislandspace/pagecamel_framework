package PageCamel::Web::Tools::ClacksConsole;
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

use base qw(PageCamel::Web::BaseWebSocket);
use PageCamel::Helpers::DateStrings;
use Net::Clacks::Client;

# play -t raw -r 11025 -e signed-integer -b 16 -c 1 rawaudio.dat

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{extrasettings} = [];
    $self->{template} = 'tools/clacksconsole';

    return $self;
}


sub wshandlerstart {
    my ($self, $ua, $settings) = @_;

    $self->{nextping} = time + 10;

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = Net::Clacks::Client->new($clconf->get('host'), $clconf->get('port'), $clconf->get('user'), $clconf->get('password'), $self->{PSAPPNAME} . ':' . $self->{modname});

    $self->{clacks}->doNetwork();

    return;
}

sub wshandlemessage {
    my ($self, $message) = @_;

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    if($message->{type} eq 'CLACKS') {
        $self->{clacks}->sendRawCommand($message->{command});
        print STDERR $message->{command}, "\n";
    }


    return 1;
}

sub wscleanup {
    my ($self) = @_;

    delete $self->{nextping};
    delete $self->{clacks};

    return;
}

sub wscyclic {
    my ($self) = @_;

    my $now = time;
    if($now > $self->{nextping}) {
        $self->{clacks}->ping();
        $self->{nextping} = $now + 10;
    }

    while(1) {
        my $cmsg = $self->{clacks}->getNext();
        last unless defined($cmsg);

        my %msg = (
            type => "CLACKSLINE",
            cmd => $cmsg->{rawline},
        );

        if(!$self->wsprint(\%msg)) {
            return 0;
        }
    }

    $self->{clacks}->doNetwork();

    return 1;
}

1;
__END__
