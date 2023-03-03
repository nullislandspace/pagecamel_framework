package PageCamel::Helpers::ClacksCache;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.2;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(Net::Clacks::ClacksCache);

sub extraInits($self) {

    $self->{oldtime} = 0;

    $self->{clacks}->disablePing(); # Don't use clacks pings for ClacksCache

    if(defined($self->{APPNAME})) {
        $self->set("VERSION::" . $self->{APPNAME}, $VERSION);
    }

    return;
}

sub extraDestroys($self) {

    my $tickkey = "LIFETICK::" . $PID;
    $self->delete($tickkey);
    return;
}


sub endconfig($self) {

    if($self->{forking}) {
        # Disconnect all sockets prior to forking,
        delete $self->{clacks};
    }
    return;
}

sub handle_child_start($self) {

    # Handle forking correctly by opening a new socket
    if(defined($self->{clacks})) {
        delete $self->{clacks};
    }
    $self->reconnect();

    return;
}

sub refresh_lifetick($self) {

    my $ticktime = time;

    if(($ticktime - $self->{oldtime}) > 10) {
        # only refresh every 10 seconds or so to keep
        # resource usage low - otherwise we'd be setting
        # the lifetick 1000 times a second or so
        my $tickkey = "pagecamel_services::LIFETICK";
        my $tickval = $PID . ' ' . $ticktime;
        $self->clacks_set($tickkey, $tickval);
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
sub disable_lifetick($self) {

    my $ticktime = 0;
    my $tickkey = "pagecamel_services::LIFETICK";
    my $tickval = $PID . ' -1';
    $self->clacks_set($tickkey, $tickval);
    $self->{oldtime} = $ticktime;

    return 1;
}

1;
__END__
