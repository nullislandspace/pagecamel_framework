package PageCamel::Worker::DirSync::Scheduler;
#---AUTOPRAGMASTART---
use 5.032;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.0;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
use feature 'signatures';
no warnings qw(experimental::signatures);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;

use Readonly;


sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my %commands;

    foreach my $cmd (qw[SCHEDULE_DIRSYNC]) {
        my $cmdfunc = "do_" . lc($cmd);
        $commands{$cmd} = $cmdfunc;
    }
    $self->{extcommands} = \%commands;

    return $self;
}

sub reload {
    my ($self) = shift;
    # Nothing to do.. in here, we are pretty much self contained
    return;
}

sub register {
    my $self = shift;

    # Register ourselfs in the CommandQueue module with additional commands
    my $comh = $self->{server}->{modules}->{$self->{commands}};

    foreach my $cmd (sort keys %{$self->{extcommands}}) {
        $comh->register_extcommand($cmd, $self);
    }
    return;
}

sub execute {
    my ($self, $command, $arguments) = @_;

    if(defined($self->{extcommands}->{$command})) {
        my $cmdfunc = $self->{extcommands}->{$command};
        return $self->$cmdfunc($arguments);
    }
    return;
}

sub do_schedule_dirsync {
    my ($self, $arguments) = @_;

    my $logtype = "OTHER"; # make logging visible only to admin user

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my ($syncname, $isodate) = @{$arguments};
    my $selsth = $dbh->prepare_cached("SELECT * FROM dirsync
                                      WHERE sync_name = ?")
                or croak($dbh->errstr);
    my $csth = $dbh->prepare_cached("INSERT INTO commandqueue
                                    (command, arguments, starttime)
                                    VALUES (?,?,?)")
                or croak($dbh->errstr);

    $selsth->execute($syncname) or croak($dbh->errstr);
    my $sync = $selsth->fetchrow_hashref;
    $selsth->finish;

    if(!defined($sync)) {
        $dbh->rollback;
        return(0, $logtype);
    }

    if(defined($isodate)) {
        $sync->{starttime} = $isodate;
    } else {
        my ($ndate, $ntime) = getDateAndTime();
        $sync->{starttime} = "$ndate " . $sync->{sync_time};
    }

    my $command = "DIRSYNC_" . $sync->{sync_server};
    my @args;
    foreach my $argname (qw[sync_name source_dir destination_dir max_age_days]) {
        push @args, $sync->{$argname};
    }

    if(!$csth->execute($command, \@args, $sync->{starttime})) {
        $reph->debuglog("Scheduling failed for DIRSYNC sync_name '" . $sync->{sync_name} . "'");
        $dbh->rollback;
        return(0, $logtype);
    }

    $reph->debuglog("DIRSYNC sync_name '" . $sync->{sync_name} . "' scheduled at " . $sync->{starttime});

    $dbh->commit;
    return (1, $logtype);
}

1;
__END__

=head1 NAME

PageCamel::Worker::DirSync::Scheduler - Scheduler for dirsync commands

=head1 SYNOPSIS

  use PageCamel::Worker::DirSync::Scheduler;

=head1 DESCRIPTION

Auto-Schedule dirsync commands

=head2 new

New instance

=head2 reload

Does nothing

=head2 register

Register the execute callback

=head2 execute

Call the correct sub-function

=head2 do_schedule_dirsync

Schedule all dirsync commands

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
