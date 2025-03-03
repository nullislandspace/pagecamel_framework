package PageCamel::Web::Tools::ClacksConsole;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.6;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseWebSocket);
use PageCamel::Helpers::DateStrings;
use Net::Clacks::Client;

# play -t raw -r 11025 -e signed-integer -b 16 -c 1 rawaudio.dat

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{extrasettings} = [];
    $self->{template} = 'tools/clacksconsole';

    return $self;
}


sub wshandlerstart($self, $ua, $settings) {

    $self->{nextping} = time + 10;

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);

    $self->{clacks}->doNetwork();

    return;
}

sub wshandlemessage($self, $message) {

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    if($message->{type} eq 'CLACKS') {
        $self->{clacks}->sendRawCommand($message->{command});
        print STDERR $message->{command}, "\n";
    }


    return 1;
}

sub wscleanup($self) {

    delete $self->{nextping};
    delete $self->{clacks};

    return;
}

sub wscyclic($self, $ua) {

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
