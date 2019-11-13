package PageCamel::Worker::Firewall::DNS;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp;
our $VERSION = 2.4;
use autodie qw( close );
use Array::Contains;
use utf8;
#---AUTOPRAGMAEND---

# Do some updates and advanced parsing for accesslog. Run at once an hour. The
# Exception here is: If workCount > 0 then it will ru in the next loop too

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DBSerialize;
use MIME::Base64;
use Net::Clacks::Client;
use Data::Dumper;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{nextrun} = 0;

    return $self;
}


sub register {
    my $self = shift;
    $self->register_worker("work");
    return;
}

sub crossregister {
    my ($self) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    $dbh->{disconnectIsFatal} = 1; # Don't automatically reconnect but exit instead!


    $self->{ipblockdelsth} = $dbh->prepare_cached("DELETE FROM nameserver_blocklist_ip
                                           WHERE blockeduntil < now()")
            or croak($dbh->errstr);

    $self->{ipflooddelsth} = $dbh->prepare_cached("DELETE FROM nameserver_floodcontrol_ip
                                           WHERE recievetime < now() - interval '" . $self->{limit}->{ip}->{ratelimitinterval} . "'")
            or croak($dbh->errstr);

    $self->{ipblockinssth} = $dbh->prepare_cached("INSERT INTO nameserver_blocklist_ip (domain_fqdn, external_sender, blockedsince, blockeduntil)
                                                SELECT domain_fqdn, external_sender, now(), now() + interval '" . $self->{limit}->{ip}->{banlimittime} ."'
                                                FROM nameserver_floodcontrol_ip flo
                                                WHERE NOT EXISTS (
                                                    SELECT 1 FROM nameserver_blocklist_ip blo
                                                    WHERE blo.domain_fqdn = flo.domain_fqdn
                                                    AND blo.external_sender = flo.external_sender
                                                    )
                                                GROUP BY flo.domain_fqdn, flo.external_sender
                                                HAVING count(*) > " . $self->{limit}->{ip}->{ratelimitcount})
            or croak($dbh->errstr);

    $self->{hostblockdelsth} = $dbh->prepare_cached("DELETE FROM nameserver_blocklist_hostname
                                           WHERE blockeduntil < now()")
            or croak($dbh->errstr);

    $self->{hostflooddelsth} = $dbh->prepare_cached("DELETE FROM nameserver_floodcontrol_hostname
                                           WHERE recievetime < now() - interval '" . $self->{limit}->{hostname}->{ratelimitinterval} . "'")
            or croak($dbh->errstr);

    $self->{hostblockinssth} = $dbh->prepare_cached("INSERT INTO nameserver_blocklist_hostname (domain_fqdn, blockedsince, blockeduntil)
                                                SELECT domain_fqdn, now(), now() + interval '" . $self->{limit}->{hostname}->{banlimittime} ."'
                                                FROM nameserver_floodcontrol_hostname flo
                                                WHERE NOT EXISTS (
                                                    SELECT 1 FROM nameserver_blocklist_hostname blo
                                                    WHERE blo.domain_fqdn = flo.domain_fqdn
                                                    )
                                                AND NOT EXISTS (
                                                    SELECT 1 FROM nameserver_domain_entry nde
                                                    WHERE nde.host_fqdn = flo.domain_fqdn
                                                )
                                                GROUP BY flo.domain_fqdn
                                                HAVING count(*) > " . $self->{limit}->{hostname}->{ratelimitcount})
            or croak($dbh->errstr);

    $dbh->commit;

    return;

}


sub work {
    my ($self) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $workCount = 0;
    my $now = time;
    if($now > $self->{nextrun}) {
        $self->{nextrun} = time + 10;
    } else {
        return $workCount;
    }

    if(!$self->{ipblockdelsth}->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return $workCount;
    }
    if(!$self->{ipflooddelsth}->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return $workCount;
    }
    if(!$self->{ipblockinssth}->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return $workCount;
    }
    $dbh->commit;
    $workCount++;

    if(!$self->{hostblockdelsth}->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return $workCount;
    }
    if(!$self->{hostflooddelsth}->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return $workCount;
    }
    if(!$self->{hostblockinssth}->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return $workCount;
    }
    $dbh->commit;


    return $workCount;
}

1;
__END__
