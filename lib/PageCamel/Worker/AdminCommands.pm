package PageCamel::Worker::AdminCommands;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.3;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;
use XML::Simple;
use Time::HiRes qw(sleep);

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my %commands;

    foreach my $cmd (qw[VACUUM_ANALYZE VACUUM_FULL REINDEX_ALL_TABLES REINDEX_TABLE ANALYZE_TABLE VACUUM_ANALYZE_TABLE
                        NOP_OK NOP_FAIL SVC_RESET_ALL_SERVICES]) {
        my $cmdfunc = "do_" . lc($cmd);
        $commands{$cmd} = $cmdfunc;
    }
    $self->{extcommands} = \%commands;

    return $self;
}

sub reload($self) {
    # Nothing to do.. in here, we only use the template and database module
    return;
}

sub register($self) {

    # Register ourselfs in the RBSCommands module with additional commands
    my $comh = $self->{server}->{modules}->{$self->{commands}};

    foreach my $cmd (sort keys %{$self->{extcommands}}) {
        $comh->register_extcommand($cmd, $self);
    }
    return;
}

sub execute($self, $command, $arguments) {

    if(defined($self->{extcommands}->{$command})) {
        my $cmdfunc = $self->{extcommands}->{$command};
        return $self->$cmdfunc($arguments);
    }
    return;
}

sub do_svc_reset_all_services($self, $command, $arguments) {

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    $reph->debuglog("Sending pagecamel_services::restart::service for all services");

    my $appworkername = lc $self->{APPNAME};
    $appworkername =~ s/\ /_/g;

    my @workers;
    my $selsth = $dbh->prepare_cached("SELECT * FROM system_settings
                                        WHERE modulename = 'pagecamel_services'
                                        AND settingname LIKE '%_enable'
                                        ORDER BY settingname")
            or croak($dbh->errstr);

    if(!$selsth->execute()) {
        $dbh->rollback;
        return (0, "OTHER");
    } else {
        while((my $line = $selsth->fetchrow_hashref)) {
            my $workername = $line->{settingname};
            $workername =~ s/\_enable$//;

            # Don't reset ourselfs in the first iteration of clacks messages
            next if($workername eq $appworkername);

            # Ignore the display server
            next if($workername eq 'display');

            push @workers, $workername;
        }
        $selsth->finish;
    }

    # Special case: We need to delete the command outselfs, since in the next step we will also kill our own process.
    # We don't want to hand in a loop with this one
    my $delsth = $dbh->prepare_cached("DELETE FROM commandqueue WHERE command = 'SVC_RESET_ALL_SERVICES'")
            or croak($dbh->errstr);
    if(!$delsth->execute) {
        $dbh->rollback;
        return (0, "OTHER");
    }
    $dbh->commit;

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};

    my $clacks = $self->newClacksFromConfig($clconf);
    foreach my $worker (@workers) {
        $clacks->set('pagecamel_services::restart::service', $worker);
    }
    # Send out restart request for our own service as the LAST command
    $clacks->set('pagecamel_services::restart::service', $appworkername);

    # Make sure everything is sent. We can do a long loong here, since we get restarted anyway...
    for(1..40) {
        $clacks->doNetwork();
        sleep(0.05);
    }
    print "Forcing exit of process...\n";
    exit(0);
}

BEGIN {
    # Auto-magically generate a number of similar functions without actually
    # writing them down one-by-one. This makes consistent changes much easier, but
    # you need perl wizardry level +10 to understand how it works...
    #
    # Added wizardry points are gained by this module beeing a parent class to
    # all other web modules, so this auto-generated functions are subclassed into
    # every child.
    #
    # This database admin commands block the worker and run with an unkown
    # runlength, so we choose to temporarly disable lifetick handling
    my %simpleFuncs = (
            vacuum_analyze            =>    "VACUUM ANALYZE",
            vacuum_full                =>  "VACUUM FULL ANALYZE",
            reindex_table            =>    "REINDEX TABLE __ARGUMENT__",
            analyze_table            =>    "ANALYZE __ARGUMENT__",
            vacuum_analyze_table    =>    "VACUUM ANALYZE __ARGUMENT__",
            );

    no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)

    # -- Deep magic begins here...
    for my $a (keys %simpleFuncs){

        *{__PACKAGE__ . "::do_$a"} =
            sub {

                my ($self, $arguments) = @_;

                my $done = 0;

                my $dbh = $self->{server}->{modules}->{$self->{db}};
                my $reph = $self->{server}->{modules}->{$self->{reporting}};
                my $memh = $self->{server}->{modules}->{$self->{memcache}};

                my $logtype = "OTHER"; # make logging visible only to admin user

                # If SQL function needs an argument, we'll get it from our input array
                my $dbhfunc = $simpleFuncs{$a};
                $dbhfunc =~ s/__ARGUMENT__/$arguments->[0]/g;

                # Debuglog what we are doing
                $reph->debuglog(" ** $dbhfunc");

                # Function does NOT allow transactions - so turn it off after
                # a rollback() call (just to be certain)
                $dbh->rollback;
                $dbh->AutoCommit(1);
                $memh->disable_lifetick;
                $done = $dbh->do($dbhfunc);
                $memh->refresh_lifetick;
                $dbh->AutoCommit(0);

                if(!$done && $done ne "0E0") {
                    $dbh->rollback;
                    return (0, $logtype);
                }
                return (1, $logtype);


            };
    }
    # ... and ends here
}

sub do_reindex_all_tables($self, $arguments) {
    my $done = 0;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $logtype = "OTHER"; # make logging visible only to admin user

    # Vacuum analyze - does NOT allow transaction
    my $error = 0;
    my $seltabsth = $dbh->prepare_cached("SELECT schemaname || '.' || tablename " .
                                    "FROM pg_tables " .
                                    "WHERE tableowner = current_user " .
                                    "ORDER BY tablename")
                or croak($dbh->errstr);

    my @tabnames;
    if($seltabsth->execute()) {
        while((my @row = $seltabsth->fetchrow_array)) {
            push @tabnames, $row[0];
        }
        $seltabsth->finish;
    } else {
        $error = 1;
    }
    $dbh->rollback; # no writes so far, *and* we need to turn of
                    # transactions for reindexing

    if(!$error) {
        $dbh->AutoCommit(1);
        foreach my $tabname (@tabnames) {
            $reph->debuglog(" ** REINDEX $tabname");
            if(!$dbh->do("REINDEX TABLE $tabname")) {
                $error = 1;
                $reph->dblog("COMMAND", "REINDEX TABLE $tabname failed");
            }
        }
        $dbh->AutoCommit(0);
    }

    if(!$error) {
        $done = 1;
    }

    if(!$done) {
        $dbh->rollback;
        return (0, $logtype);
    }
    return (1, $logtype);
}

sub do_nop_ok {
    return (1, "OTHER");
}

sub do_nop_fail {
    return (0, "OTHER");
}

1;
__END__

=head1 NAME

PageCamel::Worker::AdminCommands -

=head1 SYNOPSIS

  use PageCamel::Worker::AdminCommands;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 execute



=head2 do_reindex_all_tables



=head2 do_nop_ok



=head2 do_nop_fail



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
