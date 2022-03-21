package PageCamel::Worker::Firewall::GeoIPLog;
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

# Do some updates and advanced parsing for accesslog. Run at once an hour. The
# Exception here is: If workCount > 0 then it will ru in the next loop too

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DBSerialize;
use MIME::Base64;
use Net::Clacks::Client;

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

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);
    $self->{clacks}->doNetwork();
    $self->{nextping} = 0;

    return;
}

sub crossregister {
    my ($self) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    $self->{clacks}->listen('Firewall::Syslog');
    $self->{clacks}->doNetwork();

    $dbh->{disconnectIsFatal} = 1; # Don't automatically reconnect but exit instead!

    $self->{logsth} = $dbh->prepare_cached("INSERT INTO pagecamel.firewall_country_shitlist_log(ip_addr, destination_port, country_code, country_name)
                                            VALUES (?, ?, ?, ?)")
            or croak($dbh->errstr);

    $self->{countrysth} = $dbh->prepare_cached("SELECT country_code, country_name FROM pagecamel.geoip WHERE ? << netblock LIMIT 1")
            or croak($dbh->errstr);

    $dbh->commit;

    return;

}


sub work {
    my ($self) = @_;

    my $workCount = 0;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

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
            next unless($logtext =~ /^kernel\:.*GEOIP-Dropped\:\ /); # Only work on GEOIP-Dropped messages

            $logtext =~ s/.*GEOIP-Dropped\:\ //;
            my @parts = split/\ /, $logtext;
            my %parsed;
            foreach my $part (@parts) {
                my ($key, $val) = split/\=/, $part;
                if(!defined($key) || !defined($val)) {
                    next;
                }
                $parsed{$key} = $val;
            }
            my $ok = 1;
            foreach my $required (qw[SRC DPT]) {
                if(!defined($parsed{$required})) {
                    $reph->debuglog("GEOIP Parsing failed: ", $logtext);
                    $ok = 0;
                    last;
                }
            }
            next unless($ok);

            if(!$self->{countrysth}->execute($parsed{SRC})) {
                $reph->debuglog($dbh->errstr);
                $dbh->rollback;
                next;
            }
            my $countryline = $self->{countrysth}->fetchrow_hashref;
            $self->{countrysth}->finish;

            foreach my $required (qw[country_code country_name]) {
                if(!defined($countryline->{$required})) {
                    $countryline->{$required} = '?';
                }
            }

            if(!$self->{logsth}->execute($parsed{SRC}, $parsed{DPT}, $countryline->{country_code}, $countryline->{country_name})) {
                $reph->debuglog($dbh->errstr);
                $dbh->rollback;
                next;
            }
            
            $dbh->commit;

            my $debugtext = "IP " . $parsed{SRC} . " PORT ". $parsed{DPT} . " " . $countryline->{country_code} . " " . $countryline->{country_name};
            $reph->debuglog('GeoIP BLOCKED ' . $debugtext);

        }
    }

   
    # Do the updates not dependant on recieving stuff over the
    # network only every 10 seconds to reduce processor and database load
    if($now > $self->{nextrun}) {
        $self->{nextrun} = time + 10;
    } else {
        return $workCount;
    }

    $dbh->commit;
    $workCount++;

    return $workCount;
}

1;
__END__
