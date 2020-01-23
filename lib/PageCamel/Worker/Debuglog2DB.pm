package PageCamel::Worker::Debuglog2DB;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 2.5;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

use PageCamel::Helpers::DateStrings;
use base qw(PageCamel::Worker::Logging::PluginBase);
use Net::Clacks::Client;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);

    my %reverselookup;

    foreach my $worker (@{$self->{workers}->{item}}) {
        my $clacksname = $worker->{clacksname};
        $clacksname =~ s/\ /\_/g;
        print "Registering ", $worker->{logname}, " with clacks name ", $clacksname, "\n";
        $reverselookup{$clacksname} = $worker->{logname};
        $self->{clacks}->listen('Debuglog::' . $clacksname . '::new');
        $self->{clacks}->listen('Debuglog::' . $clacksname . '::overwrite');
    }
    $self->{clacks}->doNetwork();
    $self->{reverselookup} = \%reverselookup;

    return $self;
}

sub register {
    my $self = shift;

    $self->register_worker('logdata');
    $self->register_worker('rollingwindow');
    return;
}

sub logdata {
    my ($self) = @_;

    my $workCount = 0;
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    $self->{clacks}->ping();
    $self->{clacks}->doNetwork();

    my $insth = $dbh->prepare_cached("INSERT INTO debuglog (logtime, logtext, worker_name)
                                      VALUES (?, ?, ?)")
            or croak($dbh->errstr);

    while(1) {
        my $cmsg = $self->{clacks}->getNext();
        last unless defined($cmsg);
        next unless($cmsg->{type} eq 'set');
        my @nameparts = split/\:\:/, $cmsg->{name};
        my $workername = $self->{reverselookup}->{$nameparts[1]};
        my ($logdate, $logtime, $logtext) = split/\ /, $cmsg->{data}, 3;
        my $timestamp = $logdate . ' ' . $logtime;
        if(!$insth->execute($timestamp, $logtext, $workername)) {
            $dbh->rollback;
            croak($dbh->errstr);
        }
        $workCount++;
    }
    $dbh->commit;

    return $workCount;
}

sub rollingwindow {
    my ($self) = @_;

    my $workCount = 0;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    if(!defined($self->{rolllastrun})) {
        $self->{rolllastrun} = 0;
    }

    my $now = getCurrentHour();
    if(!$self->{isDebugging} && $self->{rolllastrun} eq $now) {
        return $workCount;
    }
    $self->{rolllastrun} = $now;

    ######################################
    # Auto-Drop older autopartition tables
    ######################################

    # Get all table names
    my $tsth = $dbh->prepare("SELECT tablename FROM pg_tables
                WHERE schemaname = 'partitions'
                AND tablename LIKE 'debuglog_%'
                ORDER BY tablename DESC")
            or croak($dbh->errstr);
    $tsth->execute or croak($dbh->errstr);

    my @oldtables;
    while((my $line = $tsth->fetchrow_hashref)) {
        push @oldtables, 'partitions.' . $line->{tablename};
    }
    $tsth->finish;
    $dbh->rollback;

    # Remove first 15 entries (which we want to keep), then reverse order
    for(1..15) {
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

    return $workCount;
}


1;
__END__
