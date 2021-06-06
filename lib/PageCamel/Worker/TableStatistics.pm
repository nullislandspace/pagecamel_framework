package PageCamel::Worker::TableStatistics;
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

    $self->{lastRun} = "";

    return $self;
}


sub register {
    my $self = shift;
    $self->register_worker("work");
    return;
}


sub work {
    my ($self) = @_;

    # Only work loop again until we reach the 30 seconds mark so we don't block the system for too long
    #
    # Also, we choose not to use cached prepared statements in here.

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $workCount = 0;

    my $newtabsth = $dbh->prepare("INSERT INTO table_statistics (tablename) (
                                    SELECT pt.schemaname || '.' || pt.tablename as fulltablename FROM pg_tables pt
                                        WHERE pt.tableowner = '" . $self->{dbuser} . "'
                                        AND NOT EXISTS
                                            (SELECT 1 FROM table_statistics ts
                                             WHERE ts.tablename = pt.schemaname || '.' || pt.tablename)
                                    )") or croak($dbh->errstr);
    my $oldtabsth = $dbh->prepare("DELETE FROM table_statistics tsd
                                    WHERE tsd.tablename IN
                                        (SELECT tss.tablename FROM table_statistics tss
                                        WHERE NOT EXISTS (
                                            SELECT 1 FROM pg_tables pt
                                            WHERE pt.tableowner = '" . $self->{dbuser} . "'
                                            AND pt.schemaname || '.' || pt.tablename = tss.tablename)
                                    )") or croak($dbh->errstr);

    my $nextsth = $dbh->prepare("SELECT tablename FROM table_statistics
                                    WHERE last_update < now() - interval '6 hours'
                                    ORDER BY last_update, tablename
                                    LIMIT 1") or croak($dbh->errstr);

    if(!$newtabsth->execute || !$oldtabsth->execute) {
        $dbh->rollback();
        croak($dbh->errstr);
    }
    $dbh->commit;

    my $endtime = time + 30;

    while(time < $endtime) {
        $nextsth->execute or croak($dbh->errstr);
        my ($tname) = $nextsth->fetchrow_array;
        $nextsth->finish;
        if(!defined($tname) || $tname eq '') {
            $dbh->rollback;
            return $workCount;
        }

        $reph->debuglog("Updating table stats for $tname");
        my $countsth = $dbh->prepare("SELECT count(*) FROM $tname") or croak($dbh->errstr);
        $countsth->execute or croak($dbh->errstr);
        my ($cnt) = $countsth->fetchrow_array;
        $countsth->finish;

        my $upsth = $dbh->prepare("UPDATE table_statistics
                                    SET row_count = ?, last_update = now()
                                    WHERE tablename = ?")
                or croak($dbh->errstr);
        $upsth->execute($cnt, $tname) or croak($dbh->errstr);
        $dbh->commit;
        $workCount++;
    }

    return $workCount;
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
