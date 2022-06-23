package PageCamel::Web::PageViewStats;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::FileSlurp qw(slurpBinFile);
use JSON::XS;

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
    $self->register_defaultwebdata("get_defaultwebdata");

    return;
}

sub get_defaultwebdata {
    my ($self, $webdata) = @_;

    $webdata->{EnablePageViewStats} = 1;
    return;
}


sub beaconhandler {
    my ($self, $ua) = @_;
    
    my $beacondata;
    my $decoded = 0;
    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
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
    my $geoip_city = '';
    my $geoip_lat = 0.0;
    my $geoip_lon = 0.0;
    my $geoip_radius = 0.0;

    if($self->{usegeoip}) {
        my $geosth = $dbh->prepare("SELECT country_code, city_name, latitude, longitude, radius FROM geoip WHERE ? << netblock LIMIT 1")
                or croak($dbh->errstr);
        if(!$geosth->execute($host)) {
            $dbh->rollback; # Not a big problem, GEOIP is just for information anyway
        } else {
            my $line = $geosth->fetchrow_hashref;
            if(defined($line->{country_code})) {
                $geoip_country = $line->{country_code};
                $geoip_city = $line->{city_name};
                $geoip_lat = $line->{latitude};
                $geoip_lon = $line->{longitude};
                $geoip_radius = $line->{radius};
            }
            $dbh->rollback;
        }
    }
    
    my $insth = $dbh->prepare_cached("INSERT INTO pageviewstats (uri, showcount, visibletime, hidecallback, remotehost, 
                                        geoip_countrycode, geoip_city, geoip_latitude, geoip_longitude, geoip_radius)
                                      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
            or croak($dbh->errstr);

    if($insth->execute($beacondata->{uri},
                     $beacondata->{count},
                     $beacondata->{duration},
                     $beacondata->{type},
                     $host,
                     $geoip_country,
                     $geoip_city,
                     $geoip_lat,
                     $geoip_lon,
                     $geoip_radius,
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
