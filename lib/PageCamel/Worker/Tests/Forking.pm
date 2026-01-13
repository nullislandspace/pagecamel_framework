package PageCamel::Worker::Tests::Forking;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 5.0;
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{nextRun} = 0;

    $self->{child} = 0;

    return $self;
}


sub register($self) {
    $self->register_worker("work");
    $self->register_sigchld("sigchld");
    return;
}

sub reload($self) {
    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);
    $self->{clacks}->ping();
    $self->{clacks}->doNetwork();
    return;
}


sub work($self) {
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $workCount = 0;

    my $now = time;
    if($now < $self->{nextRun}) {
        return $workCount;
    }
    $self->{nextRun} = $now + 10;

    $self->{clacks}->ping();
    $self->{clacks}->doNetwork();

    while((my $cmsg = $self->{clacks}->getNext())) {
        $workCount++;
        $reph->debuglog("CLACKS MESSAGE RECEIVED, TYPE ", $cmsg->{type});
    }

    my $selsth = $dbh->prepare_cached("SELECT count(*) AS usercount FROM users")
            or croak($dbh->errstr);
    if(!$selsth->execute) {
        $reph->debuglog("DATABASE ERROR ", $dbh->errstr);
        $dbh->rollback;
    } else {
        my $line = $selsth->fetchrow_hashref;
        $selsth->finish;
        $dbh->commit;
        if(!defined($line) || !defined($line->{usercount})) {
            $reph->debuglog("SELECT went wrong");
        } else {
            $reph->debuglog("Found ", $line->{usercount}, " users");
        }
    }

    if($self->{child}) {
        $reph->debuglog("Child ", $self->{child}, " is still alive?");
        return $workCount;
    }

    my $childpid = fork();
    if(!defined($childpid)) {
        $reph->debuglog("FORK FAILED");
        return $workCount;
    }

    if($childpid) {
        # Parent
        $reph->debuglog("Forked child ", $childpid);
        $self->{child} = $childpid;
    } else {
        # Child
        $self->doChildStuff();
        $reph->debuglog("Child finished");

        # Suicide, don't run any DESTROY callbacks
        $self->suicide();
    }

    return $workCount;
}

sub sigchld($self, $childpid) {
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $workCount = 0;

    if($childpid != $self->{child}) {
        $reph->debuglog($childpid, " is not my child ", $self->{child});
        return $workCount;
    }

    $workCount++;
    $reph->debuglog("Child ", $childpid, " has gone the way of the dodo");
    $self->{child} = 0;

    return $workCount;
}

sub doChildStuff($self) {
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    $reph->debuglog("Child snoozing...");
    sleep(2);
    $reph->debuglog("Child wakeup...");

    return;
}


1;
__END__

=head1 NAME

PageCamel::Worker::TableStatistics -

=head1 SYNOPSIS

  use PageCamel::Worker::TableStatistics;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 work



=head1 IMPORTANT NOTE

This module is part of the PageCamel framework. Currently, only limited support
and documentation exists outside my DarkPAN repositories. This source is
currently only provided for your reference and usage in other projects (just
copy&paste what you need, see license terms below).

To see PageCamel in action and for news about the project,
visit my blog at L<https://cavac.at>.

=head1 AUTHOR

Rene Schickbauer, E<lt>pagecamel@cavac.atE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
