package PageCamel::Helpers::ClacksCache;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.4;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use base qw(Net::Clacks::ClacksCache);

sub extraInits {
    my ($self) = @_;

    $self->{oldtime} = 0;

    $self->{clacks}->disablePing(); # Don't use clacks pings for ClacksCache

    if(defined($self->{APPNAME})) {
        $self->set("VERSION::" . $self->{APPNAME}, $VERSION);
    }

    return;
}

sub extraDestroys {
    my ($self) = @_;

    my $tickkey = "LIFETICK::" . $PID;
    $self->delete($tickkey);
    return;
}


sub endconfig {
    my ($self) = @_;

    if($self->{forking}) {
        # Disconnect all sockets prior to forking,
        delete $self->{clacks};
    }
    return;
}

sub handle_child_start {
    my ($self) = @_;

    # Handle forking correctly by opening a new socket
    if(defined($self->{clacks})) {
        delete $self->{clacks};
    }
    $self->reconnect();

    return;
}

sub refresh_lifetick {
    my ($self) = @_;

    my $ticktime = time;

    if(($ticktime - $self->{oldtime}) > 10) {
        # only refresh every 10 seconds or so to keep
        # resource usage low - otherwise we'd be setting
        # the lifetick 1000 times a second or so
        my $tickkey = "LIFETICK::" . $PID;
        $self->set($tickkey, $ticktime);
        $self->{oldtime} = $ticktime;

        #$self->{clacks}->ping();
        $self->{clacks}->doNetwork();

        return 1;
    }
    return 0;
}

# disable_lifetick is used to temporarly suspend lifetick operation
# for long-running database commands; normal lifetick handling is resumed with
# the following refresh_lifetick call.
sub disable_lifetick {
    my ($self) = @_;

    my $ticktime = 0;
    my $tickkey = "LIFETICK::" . $PID;
    $self->set($tickkey, $ticktime);
    $self->{oldtime} = $ticktime;

    return 1;
}

1;
__END__
