package PageCamel::Worker::PageViewStats;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

# Do some updates and advanced parsing for accesslog. Run at once an hour. The
# Exception here is: If workCount > 0 then it will ru in the next loop too

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;


sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{lastRun} = "";

    return $self;
}


sub register($self) {
    $self->register_worker("work");
    return;
}


sub work($self) {
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $workCount = 0;

    my $now = getCurrentHour();
    if($self->{lastRun} eq $now) {
        return $workCount;
    }
    $self->{lastRun} = $now;

    ######################################
    # Auto-Drop older autopartition tables
    ######################################

    # Get all table names
    my $tsth = $dbh->prepare("SELECT tablename FROM pg_tables
                WHERE schemaname = 'partitions'
                AND tablename LIKE 'pageviewstats_week_%'
                ORDER BY tablename DESC")
            or croak($dbh->errstr);
    $tsth->execute or croak($dbh->errstr);

    my @oldtables;
    while((my $line = $tsth->fetchrow_hashref)) {
        push @oldtables, 'partitions.' . $line->{tablename};
    }
    $tsth->finish;

    # Remove first 8 entries (which we want to keep), then reverse order
    for(1..8) {
        shift @oldtables;
    }
    @oldtables = reverse @oldtables;

    if(scalar @oldtables) {
        $reph->debuglog("Dropping old pageviewstats tables");
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

    return $workCount;
}


1;
