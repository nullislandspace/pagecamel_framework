package PageCamel::Web::PageViewStats;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::FileSlurp qw(slurpBinFile);
use JSON::XS;
use Data::Dumper;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub crossregister {
    my $self = shift;

    $self->register_webpath($self->{webpath}, 'beaconhandler', 'POST');
    $self->register_public_url($self->{webpath});

    return;
}

sub beaconhandler {
    my ($self, $ua) = @_;
    
    my $beacondata;
    my $decoded = 0;
    eval {
        $beacondata = decode_json($ua->{postdata});
        $decoded = 1;
    };
    
    if(!$decoded || !defined($beacondata)) {
        return (status => 400); # Bad request
    }
    foreach my $key (qw[uri duration count type]) {
        if(!defined($beacondata->{$key})) {
            return (status => 400); # Bad request
        }
    }
    
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    
    my $host = $ua->{remote_addr};
    my $geoip_country = '';

    if($self->{usegeoip}) {
        my $geosth = $dbh->prepare("SELECT country_code FROM geoip WHERE ? << netblock LIMIT 1")
                or croak($dbh->errstr);
        if(!$geosth->execute($host)) {
            $dbh->rollback; # Not a big problem, GEOIP is just for information anyway
        } else {
            my $line = $geosth->fetchrow_hashref;
            if(defined($line->{country_code})) {
                $geoip_country = $line->{country_code};
            } else {
                $geoip_country = '??';
            }
            $dbh->rollback;
        }
    }
    
    my $insth = $dbh->prepare_cached("INSERT INTO pageviewstats (uri, showcount, visibletime, hidecallback, remotehost, geoip_countrycode)
                                      VALUES (?, ?, ?, ?, ?, ?)")
            or croak($dbh->errstr);

    if($insth->execute($beacondata->{uri},
                     $beacondata->{count},
                     $beacondata->{duration},
                     $beacondata->{type},
                     $host,
                     $geoip_country,
                     )) {
        $dbh->commit;
        return(status => 204,
               "__do_not_log_to_accesslog" => 1, # Don't spam the accesslog
               ); # No content
    }

    $dbh->rollback;
    return(status => 500);
}

1;
__END__
