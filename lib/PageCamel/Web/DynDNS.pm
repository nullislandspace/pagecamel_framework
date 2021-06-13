# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license
package PageCamel::Web::DynDNS;
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
use PageCamel::Helpers::DateStrings;
use MIME::Base64;

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
    $self->register_webpath($self->{webpath}, "do_dyndns", 'GET', 'POST');

    return;
}

sub crossregister {
    my $self = shift;

    if(defined($self->{login})) {
        my $auth = $self->{server}->{modules}->{$self->{login}};
        $auth->register_publicurl($self->{webpath});
    }

    return;
}

sub genPasswordRequest {
    return (
        status  => 401,
        "WWW-Authenticate"  => 'Basic realm="Cavac DynDNS Service"',
    );
}

sub do_dyndns {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $host = $ua->{remote_addr} || '--unknown--';

    if($host eq '--unknown--') {
        return (status => 500,
                statustext => 'Couldn\'t get your IP',
                );
    }

    if($host =~ /\:/) {
        return (status => 500,
                statustext => 'I only see your IPv6 adress, but i only implement DynDNS for IPv4',
                );
    }

    if(!defined($ua->{headers}->{Authorization}) || $ua->{headers}->{Authorization} !~ /^Basic\ /) {
        return genPasswordRequest();
    }

    my $enc = $ua->{headers}->{Authorization};
    $enc =~ s/^Basic\ //;
    my $dec = decode_base64($enc);
    my ($dynuser, $dynpass);
    if(defined($dec) && $dec ne '' && $dec =~ /\:/) {
        ($dynuser, $dynpass) = split/\:/, $dec;
    }

    if(!defined($dynuser) || !defined($dynpass) || $dynuser eq '' || $dynpass eq '') {
        return genPasswordRequest();
    }

    my $ok = 0;
    my $ipv6 = 0;
    my $desthostname;
    {
        my $compsth = $dbh->prepare_cached("SELECT * FROM computers
                                           WHERE dyndns_user = ?
                                           AND dyndns_password = ?")
                or croak($dbh->errstr);
        $compsth->execute($dynuser, $dynpass) or croak($dbh->errstr);
        while((my $computer = $compsth->fetchrow_hashref)) {
            $ok++;
            $desthostname = $computer->{computer_name};
            #if($computer->{computer_name} eq 'fritz' && $computer->{account_domain} eq 'grumpfzotz.org') {
            #    $ipv6 = 1;
            #}
        }
    }

    if(!$ok) {
        return genPasswordRequest();
    }

    if($ipv6) {
        my @args = ($host);

        my $cmdsth = $dbh->prepare("INSERT INTO commandqueue (command, arguments) VALUES ('DYNDNS_UPDATE', ?)")
                or croak($dbh->errstr);
        $cmdsth->execute(\@args) or croak($dbh->errstr);
        $dbh->commit;
    }


    my $compsth = $dbh->prepare_cached("UPDATE computers SET net_public1_ipv4 = ?
                                        WHERE computer_name = ?")
            or croak($dbh->errstr);
    if(!$compsth->execute($host, $desthostname)) {
        $dbh->rollback;
        return (
            status  => 500,
            statustext => "Database error",
        );
    }

    my $ptrsth = $dbh->prepare_cached("UPDATE nameserver_reverselookup
                                        SET ip_address = ?
                                        WHERE computer_name = ?
                                        AND family(ip_address) = 4")
            or croak($dbh->errstr);
    if(!$ptrsth->execute($host, $desthostname)) {
        $dbh->rollback;
        return (
            status  => 500,
            statustext => "Database error",
        );
    }

    my $axfrslavesth = $dbh->prepare_cached("UPDATE nameserver_domain SET axfr_slave = ?
                                        WHERE axfr_slave like ? || ',%'")
            or croak($dbh->errstr);
    if(!$axfrslavesth->execute($desthostname . ',' . $host, $desthostname)) {
        $dbh->rollback;
        return (
            status  => 500,
            statustext => "Database error",
        );
    }

    $dbh->commit;

    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    $memh->clacks_notify('iptables::needsupdate');


    my $data = "DynDNS is now updated!\n";
    if($ipv6) {
        $data .= " Updating your IPv6 tunnel will take another minute.\n";
    }

    return (status  =>  200,
            type    => "text/plain",
            data    => $data,
    );


}


1;
