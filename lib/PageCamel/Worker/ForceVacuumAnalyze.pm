package PageCamel::Worker::ForceVacuumAnalyze;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.5;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub register {
    my $self = shift;
    $self->register_worker("force_vacuum");
    $self->register_worker("force_analyze");
    return;
}


sub force_vacuum {
    my ($self) = @_;

    my $workCount = 0;
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $selsth = $dbh->prepare_cached("SELECT tname, real_last_vacuum::timestamp without time zone FROM (
                                            SELECT schemaname || '.' || relname as tname,
                                                date_trunc('second', greatest(coalesce(last_vacuum, '1900-01-01 00:00'), coalesce(last_autovacuum, '1900-01-01 00:00'))) AS real_last_vacuum
                                            FROM pg_stat_all_tables
                                            WHERE schemaname NOT IN ('pg_toast', 'pg_catalog')
                                        ) AS foo
                                        WHERE real_last_vacuum < (now() - interval '" . $self->{maxage_vacuum} . "')
                                        ORDER BY real_last_vacuum DESC
                                        LIMIT 2")
            or croak($dbh->errstr);
    $selsth->execute() or croak($dbh->errstr);

    my @tables;
    while((my $line = $selsth->fetchrow_hashref)) {
        push @tables, $line->{tname};
        $reph->debuglog("Table " . $line->{tname} . " has not been vaccumed since " . $line->{real_last_vacuum});
    }

    $selsth->finish;
    $dbh->rollback;

    if(scalar @tables) {
        $dbh->AutoCommit(1);
        $memh->disable_lifetick;
        foreach my $table (@tables) {
            $reph->debuglog("  VACUUM ANALYZE $table ...");
            my $done = $dbh->do("VACUUM ANALYZE $table");
            if(!$done && $done ne '0E0') {
                $reph->debuglog_overwrite("  VACUUM ANALYZE $table FAILED");
            } else {
                $reph->debuglog_overwrite("  VACUUM ANALYZE $table OK");
                $workCount++;
            }
        }
        $memh->refresh_lifetick;
        $dbh->AutoCommit(0);
    }


    return $workCount;
}

sub force_analyze {
    my ($self) = @_;

    my $workCount = 0;
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $selsth = $dbh->prepare_cached("SELECT tname, real_last_analyze::timestamp without time zone FROM (
                                            SELECT schemaname || '.' || relname as tname,
                                                date_trunc('second', greatest(coalesce(last_analyze, '1900-01-01 00:00'), coalesce(last_autoanalyze, '1900-01-01 00:00'))) AS real_last_analyze
                                            FROM pg_stat_all_tables
                                            WHERE schemaname NOT IN ('pg_toast', 'pg_catalog')
                                        ) AS foo
                                        WHERE real_last_analyze < (now() - interval '" . $self->{maxage_analyze} . "')
                                        ORDER BY real_last_analyze DESC
                                        LIMIT 2")
            or croak($dbh->errstr);
    $selsth->execute() or croak($dbh->errstr);

    my @tables;
    while((my $line = $selsth->fetchrow_hashref)) {
        push @tables, $line->{tname};
        $reph->debuglog("Table " . $line->{tname} . " has not been analyzed since " . $line->{real_last_analyze});
    }

    $selsth->finish;
    $dbh->rollback;

    if(scalar @tables) {
        $dbh->AutoCommit(1);
        $memh->disable_lifetick;
        foreach my $table (@tables) {
            $reph->debuglog("  ANALYZE $table ...");
            my $done = $dbh->do("ANALYZE $table");
            if(!$done && $done ne '0E0') {
                $reph->debuglog_overwrite("  ANALYZE $table FAILED");
            } else {
                $reph->debuglog_overwrite("  ANALYZE $table OK");
                $workCount++;
            }
        }
        $memh->refresh_lifetick;
        $dbh->AutoCommit(0);
    }


    return $workCount;
}


1;
__END__

=head1 NAME

PageCamel::Worker::ForceVacuumAnalyze -

=head1 SYNOPSIS

  use PageCamel::Worker::ForceVacuumAnalyze;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 force_vacuum



=head2 force_analyze



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
