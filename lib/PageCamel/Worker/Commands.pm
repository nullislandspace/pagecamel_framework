package PageCamel::Worker::Commands;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.7;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---
use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;



sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my %extcommand;
    $self->{extcommand} = \%extcommand;
    $self->{commandlist} = '';

    $self->{firstrun} = 1;

    return $self;
}

sub reload {
    my ($self) = shift;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    # Reset queued commands that have been interrupted due to crash or debugging
    # Only reset our own entries, though
    my $workername = $self->{APPNAME};
    my $upsth = $dbh->prepare("UPDATE commandqueue SET current_worker = NULL
                              WHERE current_worker = ?")
            or croak($dbh->errstr);
    $upsth->execute($workername) or croak($dbh->errstr);
    $dbh->commit;

    return;
}

sub register {
    my $self = shift;
    $self->register_worker("work");
    return;
}

sub register_extcommand {
    my ($self, $command, $modul) = @_;

    $self->{extcommand}->{$command} = $modul;

    my @cmdlist;
    foreach my $cmd (sort keys %{$self->{extcommand}}) {
        push @cmdlist, "'" . $cmd . "'";
    }
    push @cmdlist, "'NOP_OK'";
    push @cmdlist, "'NOP_FAIL'";

    $self->{commandlist} = join(",", @cmdlist);
    return;
}

sub work {
    my ($self) = @_;

    my $workCount = 0;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    # Check if there are actually any registered ext_commands. If not, just write a debug message
    # and finish cycle
    if($self->{commandlist} eq '') {
        if($self->{firstrun}) {
            $reph->debuglog("No commands registered, disabling commandqueue handling");
            $self->{firstrun} = 0;
        }
        return 0;
    }

    my $did_some_work;
    do {
        $did_some_work = 0;

        # We LOCK the command we're working on and update it with the name of
        # our worker
        my $sth = $dbh->prepare_cached("SELECT id, command, arguments " .
                                    "FROM commandqueue " .
                                    "WHERE starttime <= now() " .
                                    "AND command IN (" . $self->{commandlist} . ") " .
                                    "AND current_worker IS NULL " .
                                    "ORDER BY starttime, id " .
                                    "LIMIT 1 ".
                                    "FOR UPDATE NOWAIT")
                        or croak($dbh->errstr);

        my $upsth = $dbh->prepare_cached("UPDATE commandqueue
                                         SET current_worker = ?
                                         WHERE ID = ?")
                        or croak($dbh->errstr);

        my $delsth = $dbh->prepare_cached("DELETE FROM commandqueue " .
                                   "WHERE id = ?")
                        or croak($dbh->errstr);

        my @commands;
        $sth->execute or croak($dbh->errstr);
        while((my $command = $sth->fetchrow_hashref)) {
            push @commands, $command;
            $did_some_work = 1; # Got at least one command - loop again after we're done with this one
        }
        $sth->finish;
        $dbh->rollback; # some commands require that there is no active transaction on this database handle

        foreach my $command (@commands) {
            # For every command, refresh lifetick
            $memh->refresh_lifetick;

            # Lock this command -> make it ours
            my $workername = $self->{APPNAME};
            if($upsth->execute($workername, $command->{id})) {
                $dbh->commit;
            } else {
                $dbh->rollback;
                last;
            }

            my $logtype = "COMMAND"; # default: visible to non-admin user

            my $printarglist = "(no args)";
            if(!defined($command->{arguments})) {
                my @temp;
                $command->{arguments} = \@temp;
            }
            if(@{$command->{arguments}}) {
                $printarglist = "(" . join(",", @{$command->{arguments}}) . ")";
            }

            $reph->debuglog("RBSCommands " . $command->{command} . " $printarglist");

            if($self->{log_all}) {
                $reph->dblog("OTHER", "DEBUG Command " . $command->{command} . " $printarglist started");
            }
            $dbh->commit;

            my $done = 0;


            if(defined($self->{extcommand}->{$command->{command}})) {
                my $tmplogtype;
                eval {
                    ($done, $tmplogtype) = $self->{extcommand}->{$command->{command}}->execute($command->{command}, $command->{arguments});
                    1;
                } or do {
                    $dbh->rollback;
                    $done = 0;
                    $reph->dblog($logtype, "Command has eval error $EVAL_ERROR: " . $command->{command} . " $printarglist failed");
                };
                if(defined($tmplogtype) && $tmplogtype ne '') {
                    $logtype = $tmplogtype; # Optional second argument "logtype"
                }
            } else {
                # Just to make sure everyone understands: This part of the IF clause should
                # never be called because we already prefilter the command queue so we
                # only work on registered commands (so multiple workers can work on
                # _different_ parts of the command system).

                # Ok, so.... "Someone has set up us the bomb!"
                $logtype = "OTHER"; # "We get signal!"
                $reph->dblog($logtype, "Command " . $command->{command} . " not implemented"); # "Main screen turn on!"
            }

            $memh->refresh_lifetick;
            $delsth->execute($command->{id});

            if(!$done) {
                $reph->dblog($logtype, "Command " . $command->{command} . " $printarglist failed");
            } elsif($self->{log_all}) {
                $reph->dblog("OTHER", "DEBUG Command " . $command->{command} . " $printarglist done");
            }
            $dbh->commit;
            $workCount++;
        }
    } while($did_some_work);

    return $workCount;
}
1;
__END__

=head1 NAME

PageCamel::Worker::Commands - run commands in CommandQueue

=head1 SYNOPSIS

  use PageCamel::Worker::Commands;


=head1 DESCRIPTION

Runs commands in commandqueue.

=head2 new

New instance

=head2 reload

On startup, re-schedule all unfinished jobs

=head2 register

register the work-callback

=head2 register_extcommand

Here commandqueue plugins register the commands they can handle

=head2 work

Run commands in the plugins from scheduled commands

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
