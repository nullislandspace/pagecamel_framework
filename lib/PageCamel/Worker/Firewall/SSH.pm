package PageCamel::Worker::Firewall::SSH;
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

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{nextrun} = 0;

    return $self;
}


sub register($self) {
    $self->register_worker("work");

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);
    $self->{clacks}->doNetwork();
    $self->{nextping} = 0;

    return;
}

sub crossregister($self) {
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    $self->{clacks}->listen('Firewall::Syslog');
    $self->{clacks}->doNetwork();

    $dbh->{disconnectIsFatal} = 1; # Don't automatically reconnect but exit instead!

    $self->{ipfloodinssth} = $dbh->prepare_cached("INSERT INTO ssh_failedlogins (ip_addr) VALUES(?)")
            or croak($dbh->errstr);

    $self->{auditloginssth} = $dbh->prepare_cached("INSERT INTO ssh_auditlog (logtext) VALUES(?)")
            or croak($dbh->errstr);

    $self->{ipblockdelsth} = $dbh->prepare_cached("DELETE FROM ssh_blocklist
                                           WHERE blockeduntil < now()")
            or croak($dbh->errstr);

    $self->{ipflooddelsth} = $dbh->prepare_cached("DELETE FROM ssh_failedlogins
                                           WHERE recievetime < now() - interval '" . $self->{limit}->{ratelimitinterval} . "'")
            or croak($dbh->errstr);

    $self->{ipblockinssth} = $dbh->prepare_cached("INSERT INTO ssh_blocklist (ip_addr, blockedsince, blockeduntil)
                                                SELECT ip_addr, now(), now() + interval '" . $self->{limit}->{banlimittime} ."'
                                                FROM ssh_failedlogins flo
                                                WHERE NOT EXISTS (
                                                    SELECT 1 FROM ssh_blocklist blo
                                                    WHERE blo.ip_addr = flo.ip_addr
                                                )
                                                GROUP BY flo.ip_addr
                                                HAVING count(*) > " . $self->{limit}->{ratelimitcount})
            or croak($dbh->errstr);

    $dbh->commit;

    return;

}


sub work($self) {
    my $workCount = 0;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $now = time;
    if($now > $self->{nextping}) {
        $self->{clacks}->ping();
        $self->{nextping} = $now + 30;
        $workCount++;
    }

    $self->{clacks}->doNetwork();

    my $first = 1;
    while((my $message = $self->{clacks}->getNext())) {
        $workCount++;
        if($message->{type} eq 'disconnect') {
            $self->debuglog("Restarting clacks connection of Syslog forwarder");
            $self->{clacks}->listen('Firewall::Syslog');
            $self->{clacks}->ping();
            $self->{clacks}->doNetwork();
            $self->{nextping} = $now + 30;
            next;
        } elsif($message->{type} eq 'set') {
            #my $key = $message->{name};
            my $logtext = $message->{data};
            next unless($logtext =~ /^sshd\[/); # Only work on SSH messages
            $reph->debuglog('SSH ' . $logtext);

            if($logtext =~ /Failed\ password.*from\ (.+?)\ port\ (.*?)/i) {
                my ($ip, $port) = ($1, $2);
                $port =~ s/\ ssh.*$//;
                if(!$self->{ipfloodinssth}->execute($ip)) {
                    $reph->debuglog($dbh->errstr);
                    $dbh->rollback;
                } else {
                    $dbh->commit;
                }
                $memh->incr('WebStats::ssh_loginerror_count');
                $reph->debuglog("*** Failed login ***");
            } elsif($logtext =~ /Invalid user.*\ from\ (.*)/i) {
                my ($ip) = ($1);
                $ip =~ s/\ port.*//g;
                if(!$self->{ipfloodinssth}->execute($ip)) {
                    $reph->debuglog($dbh->errstr);
                    $dbh->rollback;
                } else {
                    $dbh->commit;
                }
                $reph->debuglog("*** Invalid User ***");
            } elsif($logtext =~ /Connection\ closed\ by\ (.*)\ port\ .*\[preauth\]/i && $logtext !~ /invalid user/) {
                my ($ip) = ($1);
                $ip =~ s/.*\ //g; # Remove the "authenticating user USERNAME" that *sometimes* shows up
                if(!$self->{ipfloodinssth}->execute($ip)) {
                    $reph->debuglog($dbh->errstr);
                    $dbh->rollback;
                } else {
                    $dbh->commit;
                }
                $reph->debuglog("*** Invalid User ***");
            } elsif($logtext =~ /Did\ not\ receive\ identification\ string\ from\ (.+?)\ port/i) {
                # Most likely an unwanted portscan. Log it as unsucessful login attempt
                my ($ip) = ($1);
                if(!$self->{ipfloodinssth}->execute($ip)) {
                    $reph->debuglog($dbh->errstr);
                    $dbh->rollback;
                } else {
                    $dbh->commit;
                }
                $reph->debuglog("*** Portscan detected ***");
            } elsif($logtext =~ /\ ([^\s]+?)\ port\ .*Change\ of\ username\ or\ service\ not\ allowed/i) {
                # Tries an exploit by changing username or service
                my ($ip) = ($1);
                if(!$self->{ipfloodinssth}->execute($ip)) {
                    $reph->debuglog($dbh->errstr);
                    $dbh->rollback;
                } else {
                    $dbh->commit;
                }
                $reph->debuglog("*** Username change in the middle of login ***");
            }
 
            if($logtext =~ /ssh/i &&$logtext =~ /(Accepted.*)/i) {
                if(!$self->{auditloginssth}->execute($1)) {
                    $reph->debuglog($dbh->errstr);
                    $dbh->rollback;
                } else {
                    $dbh->commit;
                }
                $memh->incr('WebStats::ssh_loginerror_count');
            }
        }
    }

   
    # Do the updates not dependant on recieving stuff over the
    # network only every 10 seconds to reduce processor and database load
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

    return $workCount;
}

1;
__END__
