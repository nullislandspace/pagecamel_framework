package PageCamel::Web::PageCamelStats;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.7;
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

    return $self;
}

sub crossregister {
    my ($self) = shift;

    # Reset all the counters to zero
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    foreach my $key (qw[websocket redirect unchanged delivered notfound servererror other]) {
        my $fullname = 'WebStats::status_' . $key . '_count';
        $memh->set($fullname, 0);
    }

    foreach my $key (qw[guest nonguest]) {
        my $fullname = 'WebStats::user_' . $key . '_count';
        $memh->set($fullname, 0);
    }

    foreach my $key (qw[GET HEAD POST PUT OPTIONS PROPFIND DELETE CONNECT OTHER]) {
        my $lckey = lc $key;
        my $fullname = 'WebStats::method_' . $lckey . '_count';
        $memh->set($fullname, 0);
    }

    return;
}

sub register {
    my $self = shift;

    $self->register_logstart("prefilter");
    $self->register_logend("postfilter");

    return;
}

sub prefilter {
    my ($self, $ua) = @_;

    my $webpath = $ua->{url} || '--unknown--';

    my $paramlist = "";
    foreach my $param (sort keys %{$ua->{postparams}}) {
        my $val = $ua->{postparams}->{$param};
        if($param =~ /password/) {
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

    my ($simpleUserAgent, $badBot) = simplifyUA($userAgent);

    my @headers;
    my @hnames = sort keys %{$ua->{headers}};
    foreach my $hname (@hnames) {
        my $hval = $ua->{headers}->{$hname};
        push @headers, $hname . ': ' . $hval;
    }
    my $headerlist = join("\n", @headers);

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
        badBot  => $badBot,

    );

    $self->{requestdata} = \%requestdata;

    return;
}

sub postfilter {
    my ($self, $ua, $header, $result) = @_;

    return if(!defined($self->{requestdata}));

    my %requestdata = %{$self->{requestdata}};

    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $auth = $self->{server}->{modules}->{$self->{login}};

    $requestdata{username} = "guest";
    if(defined($auth->{currentData}->{user}) && $auth->{currentData}->{user} ne '') {
        $requestdata{username} = $auth->{currentData}->{user};
    } else {
        $requestdata{username} = 'guest';
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

    my $statuskey = 'other';
    if($requestdata{returncode} eq '101') {
        $statuskey = 'websocket';
    } elsif($requestdata{returncode} eq '304') {
        $statuskey = 'unchanged';
    } elsif($requestdata{returncode} =~ /^3/) {
        $statuskey = 'redirect';
    } elsif($requestdata{returncode} =~ /^5/) {
        $statuskey = 'servererror';
    } elsif($requestdata{returncode} =~ /^4/) {
        $statuskey = 'notfound';
    } elsif($requestdata{returncode} =~ /^2/) {
        $statuskey = 'delivered';
    }
    $statuskey = 'WebStats::status_' . $statuskey . '_count';

    my $userkey = 'guest';
    if($requestdata{username} ne 'guest') {
        $userkey = 'nonguest';
    }
    $userkey = 'WebStats::user_' . $userkey . '_count';

    my $methodkey = 'other';
    foreach my $key (qw[GET HEAD POST PUT OPTIONS PROPFIND DELETE CONNECT]) {
        if($key eq $requestdata{method}) {
            $methodkey = lc $key;
        }
    }
    $methodkey = 'WebStats::method_' . $methodkey . '_count';


    $memh->incr($statuskey);
    $memh->incr($userkey);
    $memh->incr($methodkey);

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

PageCamel::Web::PageCamelStats -

=head1 SYNOPSIS

  use PageCamel::Web::PageCamelStats;



=head1 DESCRIPTION



=head2 new



=head2 crossregister



=head2 register



=head2 prefilter



=head2 postfilter



=head2 get_defaultwebdata



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
