package PageCamel::Web::CommandQueue;
#---AUTOPRAGMASTART---
use 5.030;
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
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::CommandHelper;
use PageCamel::Helpers::Strings qw[windowsStringsQuote];

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub reload {
    my ($self) = shift;
    # Nothing to do.. in here, we only use the template and database module
    return;
}

sub register {
    my $self = shift;
    if(defined($self->{admin})) {
        $self->register_webpath($self->{admin}->{webpath}, "get_admin");
    }
    return;
}

sub get_admin {
    my ($self, $ua) = @_;

    my $webpath = $ua->{url};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $th = $self->{server}->{modules}->{templates};

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{admin}->{pagetitle},
        webpath            =>  $self->{admin}->{webpath},
        showads => $self->{showads},
    );

    my %allcommands = (
        VACUUM_ANALYZE        => 'simple',
        VACUUM_FULL            => 'simple',
        ANALYZE_TABLE        => 'table',
        VACUUM_ANALYZE_TABLE=> 'table',
        REINDEX_ALL_TABLES    => 'simple',
        REINDEX_TABLE        => 'table',
        BACKUP                => 'simple',
        CALCULATE_STATS        => 'simple',
        NOP_OK                => 'simple',
        NOP_FAIL            => 'simple',
        BACKUP              => 'simple',
        SCHEDULE_DIRSYNC    => 'dirsync',
        SVC_RESET_ALL_SERVICES => 'simple',
    );
    my @commandorder = qw[
                        ANALYZE_TABLE VACUUM_ANALYZE_TABLE VACUUM_ANALYZE VACUUM_FULL
                        REINDEX_TABLE REINDEX_ALL_TABLES
                        BACKUP
                        NOP_OK NOP_FAIL
                        SVC_RESET_ALL_SERVICES
                        ];

    my $rbstablessth = $dbh->prepare_cached("SELECT schemaname || '.' || tablename " .
                                            "FROM pg_tables " .
                                            "WHERE tableowner = current_user " .
                                            "ORDER BY schemaname, tablename")
                    or croak($dbh->errstr);
    my @rbstables;
    $rbstablessth->execute or croak($dbh->errstr);
    while((my @tabline = $rbstablessth->fetchrow_array)) {
        push @rbstables, @tabline;
    }
    $rbstablessth->finish;
    $webdata{Tables} = \@rbstables;

    my $rbssimpletablessth = $dbh->prepare_cached("SELECT tablename " .
                                            "FROM pg_tables " .
                                            "WHERE tableowner = current_user " .
                                            "ORDER BY tablename")
                    or croak($dbh->errstr);
    my @rbssimpletables;
    $rbssimpletablessth->execute or croak($dbh->errstr);
    while((my @tabline = $rbssimpletablessth->fetchrow_array)) {
        push @rbssimpletables, @tabline;
    }
    $rbssimpletablessth->finish;


    my @syncs;
    if(contains('dirsync', \@rbssimpletables) && contains('enum_dirsyncserver', \@rbssimpletables)) {
        # Not all projects have these
        my $syncsth = $dbh->prepare_cached("SELECT ds.*, date_trunc('second', last_sync) as last_sync_trunc,
                                                ss.description AS sync_server_longname
                                                FROM dirsync ds, enum_dirsyncserver ss
                                                WHERE ds.sync_server = ss.enumvalue
                                                ORDER BY sync_name")
                        or croak($dbh->errstr);

        $syncsth->execute or croak($dbh->errstr);
        while((my $sync = $syncsth->fetchrow_hashref)) {
            push @syncs, $sync;
        }
        $syncsth->finish;
    }
    $webdata{Syncs} = \@syncs;

    my @computers;
    if(contains('computers', \@rbssimpletables)) {
        # Not all projects have these
        my $computersth = $dbh->prepare_cached("SELECT *
                                                FROM computers
                                                ORDER BY computer_name")
                        or croak($dbh->errstr);

        $computersth->execute or croak($dbh->errstr);
        while((my $computer = $computersth->fetchrow_hashref)) {
            push @computers, $computer;
        }
        $computersth->finish;
    }
    $webdata{Computers} = \@computers;

    my $submitform = $ua->{postparams}->{'submitform'} || '';
    if($submitform eq "1") {
        my $command = $ua->{postparams}->{'command'} || '';
        if($command ne "") {
            my $mode = $ua->{postparams}->{'mode'} || 'view';

            if($mode eq "schedulecommand") {
                my $isodate = $ua->{postparams}->{'starttime'} || '';
                if($isodate eq '-- ::') {
                    # Compensate for datetimepicker mask when field is empty
                    $isodate = '';
                }
                if($isodate eq "") {
                    $isodate = getISODate();
                } else {
                    # try to parse date as a "natural" date, e.g. like "tommorow morning" or "next sunday afternoon"
                    $isodate = parseNaturalDate($isodate);
                }
                my $sth = $dbh->prepare_cached("INSERT INTO commandqueue " .
                                         "(command, starttime, arguments) " .
                                         "VALUES (?, ?, ?)")
                                or croak($dbh->errstr);

                my @arglist = ();

                if($allcommands{$command} eq "table") {
                    push @arglist, ($ua->{postparams}->{'tablename'} || '');
                } elsif($allcommands{$command} eq "computer") {
                    push @arglist, ($ua->{postparams}->{'computername'} || '');
                } elsif($allcommands{$command} eq "dirsync") {
                    push @arglist, ($ua->{postparams}->{'sync_name'} || '');

                    # In this case, use the $isodate as parameter for
                    # the dirsync-internal scheduler, not for the SCHEDULE_DIRSYNC
                    # command
                    push @arglist, $isodate;
                    $isodate = getISODate();

                }

                if(!$sth->execute($command, $isodate, \@arglist)) {
                    my $errstr = $dbh->errstr;
                    $sth->finish;
                    $dbh->rollback;
                    $webdata{statustext} = "Failed to schedule command $command";
                    $webdata{statuscolor} = "errortext";
                } else {
                    $sth->finish;
                    $dbh->commit;
                    $webdata{statustext} = "Command $command scheduled";
                    $webdata{statuscolor} = "oktext";
                }

            } elsif($mode eq "deletecommand") {
                # $command is the command id (ID in database) in this case
                my $sth = $dbh->prepare_cached("DELETE FROM commandqueue WHERE id = ?")
                        or croak($dbh->errstr);
                if(!$sth->execute($command)) {
                    my $errstr = $dbh->errstr;
                    $sth->finish;
                    $dbh->rollback;
                    $webdata{statustext} = "Failed to delete command";
                    $webdata{statuscolor} = "errortext";
                } else {
                    $dbh->commit;
                    $webdata{statustext} = "Command deleted";
                    $webdata{statuscolor} = "oktext";
                }
            }
        }
    }

    $webdata{commands} = getCommandQueue($dbh, $memh);

    my @admincommands;
    foreach my $admincommand (@commandorder) {
        my %cmd = (
            name    => $admincommand,
            type    => $allcommands{$admincommand},
        );
        push @admincommands, \%cmd;
    }
    $webdata{admincommands} = \@admincommands;

    my $template = $th->get("commandqueue_admin", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

1;
__END__

=head1 NAME

PageCamel::Web::CommandQueue -

=head1 SYNOPSIS

  use PageCamel::Web::CommandQueue;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 get_admin



=head2 get_user



=head2 get_webapi



=head2 get_nextcommand



=head2 get_markdone



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
