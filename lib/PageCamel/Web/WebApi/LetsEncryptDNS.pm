# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license
package PageCamel::Web::WebApi::LetsEncryptDNS;
#---AUTOPRAGMASTART---
use v5.38;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.3;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;
use XML::RPC;
use JSON::XS;

my %apifunctions = (
    add        => \&api_add,
    remove     => \&api_remove,
);

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub reload($self) {

    # Nothing to do.. in here, we only use the template and database module
    return;
}

sub register($self) {
    $self->register_webpath($self->{webpath}, "handle_rpc", 'POST');

    return;
}

sub crossregister($self) {

    if(defined($self->{auth_realm})) {
        $self->register_basic_auth($self->{webpath}, $self->{auth_realm});
    }

    return;
}

sub handle_rpc($self, $ua) {

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $host = $ua->{remote_addr} || '0.0.0.0';
    my $xmlrpc = XML::RPC->new();
    my $xml = $ua->{postdata};


    return (status  => 400) unless(defined($xml)); # BAAAAAD Request! Sit! Stay!!

    my $data;
    my $haserrors = 0;
    my $wrongmethod = 0;
    my $denied = 0;
    if(!eval {
        $data = $xmlrpc->receive($xml, sub {
                my ($methodname, @params) = @_;

                if(!defined($apifunctions{$methodname})) {
                    $wrongmethod = 1;
                    return;
                }

                my $retval = $apifunctions{$methodname}($self, $ua, @params);
                if(defined($retval->{status}) && $retval->{status} == -1) {
                    $denied = 1;
                }
                return $retval;

        });
    }) {
        $haserrors = 1;
    }

    return (status  => 500) if($haserrors);
    return (status => 422) if($wrongmethod); # "Unprocessable Entity"
    return (status => 402) if($denied); # "Payment required"
    return (status  =>  403) unless defined($data); # Forbidden because something else in the request wasn't ok

    return (status  => 200,
        #"__do_not_log_to_accesslog" => 1,
            data    => $data,
            type    => 'text/xml',
    );
}

sub api_add {
    my($self, $ua, %options) =@_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $checksth = $dbh->prepare_cached("SELECT * FROM nameserver_domain_entry 
                                            WHERE domain_fqdn = ?
                                            AND hostname = ?
                                            AND record_type = 'A'")
            or croak($dbh->errstr);

    my $delsth = $dbh->prepare_cached("DELETE FROM nameserver_domain_entry WHERE domain_fqdn = ? and hostname = ? AND record_type = 'TXT' AND is_letsencrypt = true")
            or croak($dbh->errstr);
    my $inssth = $dbh->prepare_cached("INSERT INTO nameserver_domain_entry (domain_fqdn, hostname, record_type, textrecord, delete_after, is_letsencrypt)
                                       VALUES (?, ?, 'TXT', ?, now() + interval '2 hours', true)")
            or croak($dbh->errstr);

    my $basehostname = '' . $options{extension};
    $basehostname =~ s/^\_acme\-challenge\.//;

    if(!$checksth->execute($options{basedomain}, $basehostname)) {
        print STDERR $dbh->errstr, "\n";
        $dbh->rollback;
        return {
                status   => -1,
        };
    }
    my $line = $checksth->fetchrow_hashref;
    $checksth->finish;

    if(!defined($line) || !defined($line->{hostname})) {
        print STDERR "No A entry for domain_fqdn ", $options{basedomain}, " and hostname ", $options{extension}, "\n";
        $dbh->rollback;
        return {
                status   => -1,
        };
    }

    if(!$delsth->execute($options{basedomain}, $options{extension}) ||
            !$inssth->execute($options{basedomain}, $options{extension}, $options{value})) {
        $dbh->rollback;
        return {
                status   => 0,
        };
    } else {
        $dbh->commit;
    }

    return {
            status   => 1,
    };
}

sub api_remove {
    my($self, $ua, %options) =@_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $checksth = $dbh->prepare_cached("SELECT * FROM nameserver_domain_entry 
                                            WHERE domain_fqdn = ?
                                            AND hostname = ?
                                            AND record_type = 'A'")
            or croak($dbh->errstr);
    my $delsth = $dbh->prepare_cached("DELETE FROM nameserver_domain_entry WHERE domain_fqdn = ? AND hostname = ? AND record_type = 'TXT' AND is_letsencrypt = true")
            or croak($dbh->errstr);

    my $basehostname = '' . $options{extension};
    $basehostname =~ s/^\_acme\-challenge\.//;

    if(!$checksth->execute($options{basedomain}, $basehostname)) {
        print STDERR $dbh->errstr, "\n";
        $dbh->rollback;
        return {
                status   => -1,
        };
    }
    my $line = $checksth->fetchrow_hashref;
    $checksth->finish;

    if(!defined($line) || !defined($line->{hostname})) {
        print STDERR "No A entry for domain_fqdn ", $options{basedomain}, " and hostname ", $options{extension}, "\n";
        $dbh->rollback;
        return {
                status   => -1,
        };
    }

    if(!$delsth->execute($options{basedomain}, $options{extension})) {
        $dbh->rollback;
        return {
                status   => 0,
        };
    } else {
        $dbh->commit;
    }

    return {
            status   => 1,
    };
}

1;
