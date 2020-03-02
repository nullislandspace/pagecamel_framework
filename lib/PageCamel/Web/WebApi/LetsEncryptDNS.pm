# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license
package PageCamel::Web::WebApi::LetsEncryptDNS;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.0;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;
use XML::RPC;
use JSON::XS;
use Data::Dumper;

my %apifunctions = (
    add        => \&api_add,
    remove     => \&api_remove,
);

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub reload {
    my ($self) = shift;

    # Nothing to do.. in here, we only use the template and database module
    return;
}

sub register {
    my $self = shift;
    $self->register_webpath($self->{webpath}, "handle_rpc", 'POST');

    return;
}

sub crossregister {
    my $self = shift;

    if(defined($self->{auth_realm})) {
        $self->register_basic_auth($self->{webpath}, $self->{auth_realm});
    }

    return;
}

sub handle_rpc {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $host = $ua->{remote_addr} || '0.0.0.0';
    my $xmlrpc = XML::RPC->new();
    my $xml = $ua->{postdata};


    return (status  => 400) unless(defined($xml)); # BAAAAAD Request! Sit! Stay!!

    my $data;
    my $haserrors = 0;
    if(!eval {
        $data = $xmlrpc->receive($xml, sub {
                my ($methodname, @params) = @_;

                if(!defined($apifunctions{$methodname})) {
                    $haserrors = 1;
                    return;
                }

                return $apifunctions{$methodname}($self, $ua, @params);
        });
    }) {
        $haserrors = 1;
    }

    return (status  => 403) if($haserrors);
    return (status  =>  403) unless defined($data); # Forbidden because something in the request wasn't ok

    return (status  => 200,
        #"__do_not_log_to_accesslog" => 1,
            data    => $data,
            type    => 'text/xml',
    );
}

sub api_add {
    my($self, $ua, %options) =@_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $delsth = $dbh->prepare_cached("DELETE FROM nameserver_domain_entry WHERE domain_fqdn = ? and hostname = ?")
            or croak($dbh->errstr);
    my $inssth = $dbh->prepare_cached("INSERT INTO nameserver_domain_entry (domain_fqdn, hostname, record_type, textrecord, delete_after)
                                       VALUES (?, ?, 'TXT', ?, now() + interval '2 hours')")
            or croak($dbh->errstr);
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

        my $delsth = $dbh->prepare_cached("DELETE FROM nameserver_domain_entry WHERE domain_fqdn = ? and hostname = ?")
                or croak($dbh->errstr);
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
