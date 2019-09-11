package PageCamel::Worker::Accesslog;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.2;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

# Do some updates and advanced parsing for accesslog. Run at once an hour. The
# Exception here is: If workCount > 0 then it will ru in the next loop too

use base qw(PageCamel::Worker::BaseModule);
use HTTP::BrowserDetect;
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::UserAgent qw[simplifyUA];


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

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $workCount = 0;

    my $now = getCurrentHour();
    if($self->{lastRun} eq $now) {
        return $workCount;
    }

    ######################################
    # Auto-Drop older autopartition tables
    ######################################

    # Get all table names
    my $tsth = $dbh->prepare("SELECT tablename FROM pg_tables
                WHERE schemaname = 'partitions'
                AND tablename LIKE 'accesslog_week_%'
                ORDER BY tablename DESC")
            or croak($dbh->errstr);
    $tsth->execute or croak($dbh->errstr);

    my @oldtables;
    while((my $line = $tsth->fetchrow_hashref)) {
        push @oldtables, 'partitions.' . $line->{tablename};
    }
    $tsth->finish;

    # Remove first 5 entries (which we want to keep), then reverse order
    for(1..5) {
        shift @oldtables;
    }
    @oldtables = reverse @oldtables;

    if(scalar @oldtables) {
        $reph->debuglog("Dropping old accesslog tables");
        $dbh->AutoCommit(1);
        $memh->disable_lifetick;

        foreach my $oldtable (@oldtables) {
            my $cmd = "DROP TABLE $oldtable";
            $reph->debuglog("  $cmd ...");
            my $done = $dbh->do("$cmd");
            if(!$done && $done ne '0E0') {
                $reph->debuglog_overwrite("  $cmd FAILED");
            } else {
                $reph->debuglog_overwrite("  $cmd OK");
                $workCount++;
            }
        }

        $memh->refresh_lifetick;
        $dbh->AutoCommit(0)
    }

    ######################################
    # Fix Useragent strings
    ######################################

    $reph->debuglog("Starting accesslog useragent_simplified update");
    my $selsth = $dbh->prepare_cached("SELECT logid, useragent
                                        FROM accesslog
                                        WHERE (useragent_simplified IS NULL
                                        OR useragent_simplified = 'UNKNOWN')
                                        LIMIT 20000")
            or croak($dbh->errstr);

    my $upsth = $dbh->prepare_cached("UPDATE accesslog
                                     SET useragent_simplified = ?
                                     WHERE logid = ?")
            or croak($dbh->errstr);

    $selsth->execute() or croak($dbh->errstr);
    while((my $line = $selsth->fetchrow_hashref)) {
        if(($workCount % 1000) == 0) {
            $memh->refresh_lifetick;
            if($workCount == 0) {
                $reph->debuglog("   Logid " . $line->{logid} . "  ($workCount)");
            } else {
                $reph->debuglog_overwrite("   Logid " . $line->{logid} . "  ($workCount)");
            }
        }
        $workCount++;

        my ($simpleUserAgent, $badBot) = simplifyUA($line->{useragent});
        if($simpleUserAgent eq 'REALLY_UNKNOWN') {
            $reph->debuglog("'Unknown UA: " . $line->{useragent});
        }

        if(!$upsth->execute($simpleUserAgent, $line->{logid})) {
            $selsth->finish;
            $dbh->rollback;
            $reph->debuglog("Failed to update " . $line->{logid});
            last;
        }
    }
    $selsth->finish;

    if($workCount == 0) {
        # Only "sleep" an hour if we didn't do any work
        $self->{lastRun} = $now;
        $reph->debuglog("No lines to update, suspending accesslog update for 1 hour");
    } else {
        $reph->debuglog("Updated $workCount lines, scheduling another pass for next cycle");
    }

    $dbh->commit;

    return $workCount;
}


1;
__END__

=head1 NAME

PageCamel::Worker::Accesslog -

=head1 SYNOPSIS

  use PageCamel::Worker::Accesslog;



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

Copyright (C) 2008-2016 by Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
