package PageCamel::Worker::AutoScheduler;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::DBSerialize;
use PageCamel::Helpers::Padding qw(doFPad);

use Readonly;

Readonly my $SHIFTMEMKEY => "AutoScheduler::lastShift";
Readonly my $DAYMEMKEY => "AutoScheduler::lastDay";
Readonly my $HOURMEMKEY => "AutoScheduler::lastHour";
Readonly my $MINUTEMEMKEY => "AutoScheduler::lastMinute";


sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub reload($self) {
    # Nothing to do.. in here, we are pretty much self contained
    return;
}

sub register($self) {

    $self->register_worker("work_minute");
    $self->register_worker("work_shift");
    $self->register_worker("work_hour");
    $self->register_worker("work_day");

    return;
}


sub work_shift($self) {

    my $workCount = 0;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $now = getCurrentHour();
    my $lastRun = $memh->get($SHIFTMEMKEY);
    if(!defined($lastRun)) {
        $lastRun = "";
    } else {
        $lastRun = dbderef($lastRun);
    }

    if($lastRun eq $now) {
        return $workCount;
    }

    $memh->set($SHIFTMEMKEY, $now);

    if($now !~ /(?:06|14|22)$/) {
        return $workCount;
    }


    my $csth = $dbh->prepare_cached("INSERT INTO commandqueue
                                    (command, arguments)
                                    VALUES (?,?)")
            or croak($dbh->errstr);
    my @args = ();

    $reph->debuglog("Scheduling backup");
    if($csth->execute('BACKUP', \@args)) {
        $workCount++;
        $dbh->commit;
    } else {
        $dbh->rollback;
        $reph->debuglog("Scheduling backup FAILED!");
    }

    $dbh->commit;
    return $workCount;
}

sub work_hour($self) {

    my $workCount = 0;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $now = getCurrentHour();
    my $lastRun = $memh->get($HOURMEMKEY);
    if(!defined($lastRun)) {
        $lastRun = "";
    } else {
        $lastRun = dbderef($lastRun);
    }


    if($lastRun eq $now) {
        return $workCount;
    }

    $memh->set($HOURMEMKEY, $now);

    { # Clean up the status log
        my %lifetimes = (
            'PRODLINE_ACCESS'   => '10 hours',
            'COMMAND'           => '5 days',
            'OTHER'             => '3 days',

        );

        foreach my $cmd (keys %lifetimes) {
            my $ltime = $lifetimes{$cmd};
            $reph->debuglog("Cleaning errors for $cmd ($ltime)");
            my $csth = $dbh->prepare("DELETE FROM errors
                                            WHERE error_type = '$cmd'
                                            AND reporttime < now() - INTERVAL '$ltime'")
                    or croak($dbh->errstr);
            if($csth->execute()) {
                $dbh->commit;
                $workCount++;
            } else {
                $dbh->rollback;
                $reph->debuglog("Cleaning FAILED!");
            }
        }
        $dbh->commit;
    }

    { # Delete empty tables in the "partitions" schema
        my $csth = $dbh->prepare_cached("SELECT partitions.delete_empty_partitions() AS tname")
            or croak($dbh->errstr);

        $reph->debuglog("Removing empty partition tables");
        if($csth->execute()) {
            while((my $line = $csth->fetchrow_hashref)) {
                $reph->debuglog("  Dropped table " . $line->{tname});
            }
            $csth->finish;
            $dbh->commit;
            $workCount++;
        } else {
            $dbh->rollback;
            $reph->debuglog("Partitions cleanup FAILED!");
        }

        $dbh->commit;

    }

    return $workCount;
}

sub work_day($self) {

    my $workCount = 0;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $now = getCurrentDay();
    my $lastRun = $memh->get($DAYMEMKEY);
    if(!defined($lastRun)) {
        $lastRun = "";
    } else {
        $lastRun = dbderef($lastRun);
    }


    if($lastRun eq $now) {
        return $workCount;
    }

    $memh->set($DAYMEMKEY, $now);


    my $csth = $dbh->prepare_cached("INSERT INTO commandqueue
                                    (command, arguments, starttime)
                                    VALUES (?,?,?)")
            or croak($dbh->errstr);

    { # Schedule DirSync
        my $selsth = $dbh->prepare_cached("SELECT * FROM dirsync ORDER BY sync_name")
                or croak($dbh->errsttr);
        my @syncs;
        if($selsth->execute) {
            while((my $line = $selsth->fetchrow_hashref)) {
                push @syncs, $line;
            }
            $selsth->finish;
        } else {
            $dbh->rollback;
            $reph->debuglog("Reading DIRSYNC lines for scheduling FAILED!");
        }

        my ($ndate, $ntime) = getDateAndTime();

        foreach my $sync (@syncs) {
            $reph->debuglog("Scheduling daily DIRSYNC for " . $sync->{sync_name});
            my $starttime = "$ndate 00:00:00";
            my @args = ($sync->{sync_name});
            if($csth->execute('SCHEDULE_DIRSYNC', \@args, $starttime)) {
                $workCount++;
                $dbh->commit;
            } else {
                $dbh->rollback;
                $reph->debuglog("Scheduling daily DIRSYNC FAILED!");
            }
        }
    }

    if(!defined($self->{workday_run_since_startup})) {
        # Don't run the stuff below unless we have already had a real date change
        $self->{workday_run_since_startup} = 1;
        return $workCount;
    }

    { # Schedule SVC Service Reset
        my ($ndate, $ntime) = getDateAndTime();

        $reph->debuglog("Scheduling daily Service reset");
        my $starttime = "$ndate 01:40:00";
        my @args = ();
        if($csth->execute('SVC_RESET_ALL_SERVICES', \@args, $starttime)) {
            $workCount++;
            $dbh->commit;
        } else {
            $dbh->rollback;
            $reph->debuglog("Scheduling daily Service reset FAILED!");
        }
    }



    return $workCount;
}

sub work_minute($self) {

    my $workCount = 0;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $now = getCurrentMinute();
    my $lastRun = $memh->get($MINUTEMEMKEY);
    if(!defined($lastRun)) {
        $lastRun = "";
    } else {
        $lastRun = dbderef($lastRun);
    }


    if($lastRun eq $now) {
        return $workCount;
    }

    $memh->set($MINUTEMEMKEY, $now);

    {
        $reph->debuglog("Deleting stale templatecache_dynamic_scripting entries");
        my $delsth = $dbh->prepare_cached("WITH deleted AS (
                                          DELETE FROM templatecache_dynamic_scripting
                                          WHERE valid_until < now()
                                          RETURNING *)
                                          SELECT count(*) as delcount FROM deleted")
                or croak($dbh->errstr);
        if($delsth->execute) {
            my $line = $delsth->fetchrow_hashref;
            $delsth->finish;
            $dbh->commit;
            $workCount += $line->{delcount};
            $reph->debuglog("Deleted " . $line->{delcount} . " entries");
        } else {
            $dbh->rollback;
            $reph->debuglog("Deletion failed: " . $dbh->errstr);
        }
    }


    return $workCount;
}

1;
__END__

=head1 NAME

PageCamel::Worker::AutoScheduler - Automatically scheduler commands

=head1 SYNOPSIS

  use PageCamel::Worker::AutoScheduler;

=head1 DESCRIPTION

Schedule various commands in commandqueue

=head2 new

Create new instance

=head2 reload

Currently does nothing

=head2 register

Register callbacks

=head2 work_shift

Schedule specific work every 8 hours (at 06:00, 14:00, 22:00)

=head2 work_hour

Schedule work at the start of every hour

=head2 work_day

Schedule work at the start of every day

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
