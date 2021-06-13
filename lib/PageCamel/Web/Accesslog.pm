package PageCamel::Web::Accesslog;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.6;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::UserAgent qw[simplifyUA];

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    if(!defined($self->{usegeoip})) {
        $self->{usegeoip} = 0;
    }

    return $self;
}

sub register {
    my $self = shift;

    $self->register_logstart("logstart");
    $self->register_logend("logend");
    $self->register_defaultwebdata("get_defaultwebdata");

    return;
}

sub logstart {
    my ($self, $ua) = @_;

    my $webpath = $ua->{url} || '--unknown--';
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $paramlist = "";
    foreach my $param (sort keys %{$ua->{postparams}}) {
        my $val = $ua->{postparams}->{$param};
        if($param =~ /(?:password|pwnew|pwold)/) {
            $val = "****";
        }
        $paramlist .= "$param=$val;";
    }
    my $host = $ua->{remote_addr} || '--unknown--';
    my $method = $ua->{method} || '--unknown--';
    my $userAgent = $ua->{headers}->{'User-Agent'} || '--unknown--';
    my $referer = $ua->{headers}->{Referer} || '';
    my $protocol = 'http';
    if($self->{usessl}) {
        $protocol = 'https';
    }
    my $range = $ua->{headers}->{'HTTP_RANGE'} || '';
    my $httpversion = $ua->{httpversion} || '';

    my ($simpleUserAgent, $badBot) = simplifyUA($userAgent);

    my @headers;
    my @hnames = sort keys %{$ua->{headers}};
    foreach my $hname (@hnames) {
        my $hval = $ua->{headers}->{$hname};
        push @headers, $hname . ': ' . $hval;
    }
    my $headerlist = join("\n", @headers);

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

    my %requestdata = (
        url     => $webpath,
        method  => $method,
        parameters  => $paramlist,
        remotehost    => $host,
        useragent   => $userAgent,
        simpleagent => $simpleUserAgent,
        referer => $referer,
        protocol => $protocol,
        headers => $headerlist,
        range   => $range,
        httpversion => $httpversion,
        geoip_country => $geoip_country,
        geoip_city => $geoip_city,
        geoip_lat => $geoip_lat,
        geoip_lon => $geoip_lon,
        geoip_radius => $geoip_radius,
    );

    $self->{requestdata} = \%requestdata;

    return;
}

sub logend {
    my ($self, $ua, $header, $result) = @_;

    return if(!defined($self->{requestdata}));

    if(defined($result->{__do_not_log_to_accesslog}) && $result->{__do_not_log_to_accesslog} == 1) {
        delete $self->{requestdata};
        return;
    }

    my %requestdata = %{$self->{requestdata}};

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $auth = $self->{server}->{modules}->{$self->{login}};


    $requestdata{username} = "";
    if(defined($auth->{currentData}->{user})) {
        $requestdata{username} = $auth->{currentData}->{user};
    } else {
        $requestdata{username} = '';
    }

    $requestdata{returncode} = $result->{status};
    $requestdata{doctype} = $result->{type};
    if(!defined($requestdata{doctype}) || $requestdata{doctype} eq '') {
        $requestdata{doctype} = '--unknown--';
    }

    $requestdata{compression} = "none";
    if(defined($result->{"Content-Encoding"}) && $result->{"Content-Encoding"} ne "") {
        $requestdata{compression} = $result->{"Content-Encoding"};
    }

    if(defined($result->{"webapi_method"})) {
            $requestdata{method} = " [Function " . $result->{"webapi_method"} . "]";
    }
    
    if(defined($result->{pagecamel_debug_info})) {
        $requestdata{pagecamel_debug_info} = $result->{pagecamel_debug_info};
    }

    $requestdata{url_host} = $ua->{headers}->{Host};

    my $stmt = "INSERT INTO accesslog (url, url_host, processid, method, parameters, remotehost, username, returncode, doctype, useragent,
                                        compression, referer, useragent_simplified, protocol, headers, rangeheader, httpversion,
                                        geoip_countrycode, geoip_city, geoip_latitude, geoip_longitude, geoip_radius,
                                        pagecamel_debug_info)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)";
    my $logsth = $dbh->prepare_cached($stmt) or croak($dbh->errstr);

    if($logsth->execute($requestdata{url},
                  $requestdata{url_host},
                  $PID,
                  $requestdata{method},
                  $requestdata{parameters},
                  $requestdata{remotehost},
                  $requestdata{username},
                  $requestdata{returncode},
                  $requestdata{doctype},
                  $requestdata{useragent},
                  $requestdata{compression},
                  $requestdata{referer},
                  $requestdata{simpleagent},
                  $requestdata{protocol},
                  $requestdata{headers},
                  $requestdata{range},
                  $requestdata{httpversion},
                  $requestdata{geoip_country},
                  $requestdata{geoip_city},
                  $requestdata{geoip_lat},
                  $requestdata{geoip_lon},
                  $requestdata{geoip_radius},
                  $requestdata{pagecamel_debug_info},
                  )) {
        $dbh->commit;
    } else {
        $dbh->rollback;
    }


    delete $self->{requestdata};

    return;
}

sub get_defaultwebdata {
    my ($self, $webdata) = @_;

    $webdata->{__do_not_log_to_accesslog} = 0;
    return;
}

1;
__END__

=head1 NAME

PageCamel::Web::Accesslog - log all webcalls

=head1 SYNOPSIS

  use PageCamel::Web::Accesslog;

=head1 DESCRIPTION

Logs all webcalls in the "accesslog" table

=head2 new

Create a new instance.

=head2 register

Register the logstart and logend callbacks

=head2 logstart

"Remember" initial request informations.

=head2 logend

Write log entry.

=head2 get_defaultwebdata

Default "__do_not_log_to_accesslog" to false (= log always)

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
