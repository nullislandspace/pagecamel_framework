package PageCamel::Helpers::SVCHelper;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.7;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use WWW::Mechanize::GZip;
use JSON::XS;
use PageCamel::Helpers::DateStrings;
use Time::HiRes qw(sleep);

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = bless \%config, $class;

    my $ok = 1;
    foreach my $key (qw[reph clacks]) {
        if(!defined($self->{$key})) {
            print STDERR "$key not defined\n";
            $ok = 0;
        }
    }
    if(!$ok) {
        croak("Missing configuration");
    }

    return $self;
}

sub start_workers($self, @workernames) {
    foreach my $workername (@workernames) {
        $self->feedback("Starting worker ", $workername);
        $self->_change_worker_state($workername, 1);
    }

    my $ok = 1;
    foreach my $workername (@workernames) {
        $self->feedback("Waiting for worker ", $workername, " start");
        if($self->_wait_worker_state($workername, 1)) {
            $self->feedback("Started worker ", $workername);
        } else {
            $self->feedback("Failed to start worker ", $workername);
            $ok = 0;
        }
    }

    return $ok;
}

sub stop_workers($self, @workernames) {
    foreach my $workername (@workernames) {
        $self->feedback("Stopping worker ", $workername);
        $self->_change_worker_state($workername, 0);
    }

    my $ok = 1;
    foreach my $workername (@workernames) {
        $self->feedback("Waiting for worker ", $workername, " stop");
        if($self->_wait_worker_state($workername, 0)) {
            $self->feedback("Stopped worker ", $workername);
        } else {
            $self->feedback("Failed to stop worker ", $workername);
            $ok = 0;
        }
    }

    return $ok;
}

sub restart_workers($self, @workernames) {
    return $self->stop_workers(@workernames) && $self->start_workers(@workernames);
}

sub _change_worker_state($self, $workername, $newstate) {
    my $endtime = time + 60;

    my $fullname = $ENV{PC_PROJECTNAME_LC} . '_' . $workername;

    my $mode = 'enable';
    if(!$newstate) {
        $mode = 'disable';
    }
    my $command1name = 'pagecamel_services::' . $fullname. '_enable';
    my $command2name = 'pagecamel_services::' . $mode . '::service';

    $self->{clacks}->set($command1name, $newstate);
    $self->{clacks}->set($command2name, $fullname);
    $self->{clacks}->doNetwork();

    return 1;
}

sub _wait_worker_state($self, $workername, $newstate) {
    my $endtime = time + 60;

    my $fullname = $ENV{PC_PROJECTNAME_LC} . '_' . $workername;

    my $statusname = 'pagecamel_services::' . $fullname . '_status';

    my $ok = 0;
    while(time < $endtime) {
        $self->{clacks}->doNetwork();
        my $curstate = $self->{clacks}->retrieve($statusname);
        if(!defined($curstate)) {
            $self->feedback($statusname, " not defined in clacks");
            last;
        }

        #$self->feedback("CURSTATE: $curstate");
        if($curstate == $newstate) {
            $ok = 1;
            last;
        }
        sleep(0.1);
    }

    return $ok;
}

sub register_feedback($self, $object, $function) {
    $self->{feedback} = {
        object => $object,
        function => $function,
    };
    return;
}

sub feedback($self, @parts) {
    my $line = join('', @parts);

    if(defined($self->{feedback})) {
        my $obj = $self->{feedback}->{object};
        my $func = $self->{feedback}->{function};
        $obj->$func($line);
    } else {
        $self->{reph}->debuglog($line);
    }
    return;
}

sub DESTROY($self) {
    if(defined($self->{feedback})) {
        delete $self->{feedback};
    }

    return;
}

1;
