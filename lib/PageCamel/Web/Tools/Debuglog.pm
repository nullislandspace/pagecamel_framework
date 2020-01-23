package PageCamel::Web::Tools::Debuglog;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 2.5;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
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
    $self->{clacks} = $self->newClacksFromConfig($clconf);

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
            }
        }
    }

    $self->{clacks}->doNetwork();

    return 1;
}

1;
__END__
