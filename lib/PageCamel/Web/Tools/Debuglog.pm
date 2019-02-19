package PageCamel::Web::Tools::Debuglog;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.1;
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
    $self->{template} = 'tools/debuglog';

    my $name = 'Debuglog::' . $self->{worker};
    $name =~ s/\ /\_/g;
    $self->{clacksname} = $name;

    return $self;
}


sub wshandlerstart {
    my ($self, $ua, $settings) = @_;

    $self->{nextping} = time + 10;

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = Net::Clacks::Client->new($clconf->get('host'), $clconf->get('port'), $clconf->get('user'), $clconf->get('password'), $self->{PSAPPNAME} . ':' . $self->{modname});

    $self->{clacks}->listen($self->{clacksname} . '::new');
    $self->{clacks}->listen($self->{clacksname} . '::overwrite');
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

    my $now = time;
    if($now > $self->{nextping}) {
        $self->{clacks}->ping();
        $self->{nextping} = $now + 10;
    }

    while(1) {
        my $cmsg = $self->{clacks}->getNext();
        last unless defined($cmsg);

        if($cmsg->{type} eq 'set' && $cmsg->{name} =~ /^$self->{clacksname}/) {
            my %msg = (
                type => 'VALUE',
                varname => 'Debugline_new',
                varval => $cmsg->{data},
            );
            if($cmsg->{name} =~ /overwrite$/) {
                $msg{varname} = "Debugline_overwrite";
            }

            if(!$self->wsprint(\%msg)) {
                return 0;
                last;
            }
        }
    }

    $self->{clacks}->doNetwork();

    return 1;
}

1;
__END__
