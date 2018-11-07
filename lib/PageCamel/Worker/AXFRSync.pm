package PageCamel::Worker::AXFRSync;
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

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::DBSerialize;
use PageCamel::Helpers::Padding qw(doFPad);
use Net::DNS::Resolver;

use Readonly;

Readonly my $HOURMEMKEY => "AXFRSync::lastHour";

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub reload {
    my ($self) = shift;
    # Nothing to do.. in here, we are pretty much self contained
    return;
}

sub register {
    my $self = shift;

    $self->register_worker("work_hour");

    return;
}


sub work_hour {
    my ($self) = @_;

    my $workCount = 0;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};


    my $now = getCurrentHour();
    my $lastRun = $memh->get($HOURMEMKEY);
    if(!defined($lastRun)) {
        $lastRun = "";
    } else {
        $lastRun = dbderef($lastRun);
    }

    if(!$self->{isDebugging} && $lastRun eq $now) {
        return $workCount;
    }

    $memh->set($HOURMEMKEY, $now);

    #if(!$self->{isDebugging} && $now !~ /(?:06|14|22)$/) {
    #    return $workCount;
    #}

    $reph->debuglog("=== Running AXFR Update ===");

    my $selsth = $dbh->prepare_cached("SELECT * FROM nameserver_domain
                                        WHERE is_axfr_slave = true
                                        ORDER BY domain_fqdn")
            or croak($dbh->errstr);
    if(!$selsth->execute) {
        $dbh->rollback;
        $reph->debuglog("SELECT failed: " . $dbh->errstr);
        return $workCount;
    }
    my @domains;
    while((my $domain = $selsth->fetchrow_hashref)) {
        push @domains, $domain;
        $workCount++;
    }
    $selsth->finish;

    my $seltimessth = $dbh->prepare_cached("SELECT * FROM enum_nameserver_refreshtime")
            or croak($dbh->errstr);

    my %times;
    if(!$seltimessth->execute) {
        $dbh->rollback;
        $reph->debuglog("Failed to select available TTL times");
        return $workCount;
    }
    while((my $ttl = $seltimessth->fetchrow_hashref)) {
        $times{$ttl->{enumvalue}} = $ttl->{description};
    }
    $seltimessth->finish;

    $dbh->commit;

    foreach my $domain (@domains) {
        $workCount += $self->syncDomain($domain, \%times);
    }

    $reph->debuglog("=== AXFR Update finished ===");

    return $workCount;
}

sub syncDomain {
    my ($self, $domain, $times) = @_;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $workCount = 0;

    $reph->debuglog("Syncing domain " . $domain->{domain_fqdn} . " from " . $domain->{axfr_master});

    my $delsth = $dbh->prepare_cached("DELETE FROM nameserver_domain_entry WHERE domain_fqdn = ?")
            or croak($dbh->errstr);

    my $insth = $dbh->prepare_cached("INSERT INTO nameserver_domain_entry (domain_fqdn, record_type, hostname, textrecord, mxpriority, ttl_time)
                                      VALUES (?, ?, ?, ?, ?, ?)")
            or croak($dbh->errstr);

    my $soaupdatesth = $dbh->prepare_cached("UPDATE nameserver_domain
                                               SET primary_nameserver = ?,
                                               soa_admin = ?,
                                               refresh_time = ?,
                                               retry_time = ?,
                                               expire_time = ?,
                                               ttl_time = ?,
                                               soa_serial = ?
                                             WHERE domain_fqdn = ?")
            or croak($dbh->errstr);


    my $resolver = new Net::DNS::Resolver(
        nameservers => [ $domain->{axfr_master} ],
        recurse     => 0,
        debug       => 0
    );
    $resolver->tcp_timeout( 10 );

    my $ok = 0;
    my @zone;
    eval {
        @zone = $resolver->axfr($domain->{domain_fqdn});
        $ok = 1;
    };

    if(!$ok || !@zone) {
        $reph->debuglog("Failed to AXFR domain " . $domain->{domain_fqdn} . ": $@");
        $dbh->rollback;
        return $workCount;
    }

    if(!$delsth->execute($domain->{domain_fqdn})) {
        $dbh->rollback;
        $reph->debuglog("Failed to delete old entries: " . $dbh->errstr);
        return $workCount;
    }
    $workCount++;

    foreach my $rr (@zone) {
        $workCount++;
        my $type = $rr->type;
        if($type eq 'SOA') {
            # Make the dummy SOA record
            my $hname = $rr->owner;
            $hname =~ s/$domain->{domain_fqdn}//;
            my $ttl = $self->maptime($rr->ttl, $times);
            my $mxpriority = 10;
            my $txtrecord = "";
            if(!$insth->execute($domain->{domain_fqdn}, $type, $hname, $txtrecord, $mxpriority, $ttl)) {
                $dbh->rollback;
                $reph->debuglog("Failed to insert record: " . $dbh->errstr);
                return $workCount;
            }
            
            # Update domain entry
            my $nameserver = $rr->mname;
            my $soaadmin = $rr->rname;
            my $refresh = $self->maptime($rr->refresh, $times);
            my $retry = $self->maptime($rr->retry, $times);
            my $expire = $self->maptime($rr->expire, $times);
            my $minimum = $self->maptime($rr->minimum, $times);
            my $serial = $rr->serial;
            if(!$soaupdatesth->execute($nameserver, $soaadmin, $refresh, $retry, $expire, $minimum, $serial, $domain->{domain_fqdn})) {
                $dbh->rollback;
                $reph->debuglog("Failed to update domain record: " . $dbh->errstr);
                return $workCount;
            }

        } else {
            my $hname = $rr->owner;
            $hname =~ s/$domain->{domain_fqdn}//;
            $hname =~ s/\.$//;
            #my $class = $rr->class;
            my $ttl = $self->maptime($rr->ttl, $times);
            my $txtrecord = $rr->rdstring;
            $txtrecord =~ s/\"//g;
            $txtrecord =~ s/\.$//g;
            my $mxpriority = 10;
            if($type eq 'MX') {
                ($mxpriority, $txtrecord) = split(/\ /, $txtrecord, 2);
            }
            if(!$insth->execute($domain->{domain_fqdn}, $type, $hname, $txtrecord, $mxpriority, $ttl)) {
                $dbh->rollback;
                $reph->debuglog("Failed to insert record: " . $dbh->errstr);
                return $workCount;
            }

        }
    }

    $dbh->commit;

    return $workCount;
}

sub maptime {
    my ($self, $value, $times) = @_;

    if(defined($times->{$value})) {
        return $value;
    }

    # Need to find closest match
    my $first = 1;
    my $newval = 0;
    my $diff = 0;
    foreach my $key (keys %{$times}) {
        if($first) {
            $newval = $key;
            $diff = abs($newval - $value);
            $first = 0;
        } else {
            my $newdiff = abs($key - $value);
            if($newdiff < $diff) {
                $diff = $newdiff;
                $newval = $key;
            }
        }
    }

    return $newval;
}


1;
__END__

=head1 NAME

PageCamel::Worker::AXFRSync - Automatically scheduler commands

=head1 SYNOPSIS

  use PageCamel::Worker::AXFRSync;

=head1 DESCRIPTION

Schedule various commands in commandqueue

=head2 new

Create new instance

=head2 reload

Currently does nothing

=head2 register

Register callbacks

=head2 work_shift

Schedule specific work every 8 hours (at 06:00, 14:00, 22:00)

=head2 work_hour

Schedule work at the start of every hour

=head2 work_day

Schedule work at the start of every day

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

Copyright (C) 2008-2016 by Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
