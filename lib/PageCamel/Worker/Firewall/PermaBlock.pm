package PageCamel::Worker::Firewall::PermaBlock;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

# Do some updates and advanced parsing for accesslog. Run at once an hour. The
# Exception here is: If workCount > 0 then it will ru in the next loop too

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DBSerialize;
use MIME::Base64;
use Net::Clacks::Client;
use IO::Socket::IP;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{nextrun} = 0;

    return $self;
}


sub register($self) {
    $self->register_worker("work");

    return;
}

sub crossregister($self) {
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    $self->{blockdelsth} = $dbh->prepare_cached("DELETE FROM firewall_permablock
                                           WHERE blockeduntil < now()")
            or croak($dbh->errstr);

    $self->{flooddelsth} = $dbh->prepare_cached("DELETE FROM firewall_permablock_candidates
                                           WHERE logtime < now() - interval '" . $self->{limit}->{ratelimitinterval} . "'")
            or croak($dbh->errstr);

    $self->{blockselsth} = $dbh->prepare_cached("SELECT c.ip_addr FROM firewall_permablock_candidates c
                                                    WHERE NOT EXISTS (
                                                        SELECT 1 FROM firewall_permablock b
                                                        WHERE b.ip_addr = c.ip_addr
                                                    )
                                                    GROUP BY c.ip_addr
                                                    HAVING count(*) > " . $self->{limit}->{ratelimitcount})
            or croak($dbh->errstr);

    $self->{sourceselsth} = $dbh->prepare_cached("SELECT source FROM firewall_permablock_candidates
                                                    WHERE ip_addr = ?
                                                    GROUP BY source
                                                    ORDER BY source")
            or croak($dbh->errstr);
        
    $self->{blockinssth} = $dbh->prepare_cached("INSERT INTO firewall_permablock (ip_addr, source, blockeduntil)
                                                    VALUES(?, ?, now() + interval '" . $self->{limit}->{banlimittime} ."')")
            or croak($dbh->errstr);

    $dbh->commit;

    return;

}


sub work($self) {
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $workCount = 0;
    my $now = time;
    if($now > $self->{nextrun}) {
        $self->{nextrun} = time + 10;
    } else {
        return $workCount;
    }


    if(!$self->{blockdelsth}->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return $workCount;
    }

    my @ips;
    if(!$self->{blockselsth}->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return $workCount;
    }
    while((my $line = $self->{blockselsth}->fetchrow_hashref)) {
        push @ips, $line->{ip_addr};
    }
    $self->{blockselsth}->finish;
    $dbh->commit;

    foreach my $ip (@ips) {
        $reph->debuglog("Permablocking $ip");
        my @sources;
        if(!$self->{sourceselsth}->execute($ip)) {
            $reph->debuglog($dbh->errstr);
            $dbh->rollback;
            return $workCount;
        }
        while((my $line = $self->{sourceselsth}->fetchrow_hashref)) {
            push @sources, $line->{source};
        }
        $self->{sourceselsth}->finish;
        my $sourcetext = join(',', @sources);
        $reph->debuglog("    Sources: $sourcetext");
        if(!$self->{blockinssth}->execute($ip, $sourcetext)) {
            $reph->debuglog($dbh->errstr);
            $dbh->rollback;
        } else {
            $dbh->commit;
            $workCount++;
        }
    }

    return $workCount;
}

1;
__END__
