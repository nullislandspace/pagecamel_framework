package PageCamel::Worker::Firewall::IPTables;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.4;
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

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);

    $self->{nextrun} = 0;

    $self->{iptablesupdate} = 1;

    return $self;
}


sub register {
    my $self = shift;
    $self->register_worker("work");
    return;
}

sub crossregister {
    my ($self) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    $dbh->{disconnectIsFatal} = 1; # Don't automatically reconnect but exit instead!
    $dbh->commit;

    $self->{clacks}->listen('iptables::needsupdate');
    $self->{clacks}->doNetwork();
    $self->{nextping} = 0;

    # DB triggers can't do clacks (not yet, anyway), so fall back to LISTEN/NOTIFY for handling IPTABLES updates
    $dbh->do("LISTEN updateiptables");
    $dbh->commit;

    return;

}


sub work {
    my ($self) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $workCount = 0;

    if($self->{iptablesupdate}) {
        $workCount++;
        $self->updateIPTables();
    }

    my $now = time;
    if($now > $self->{nextping}) {
        $self->{clacks}->ping();
        $self->{nextping} = $now + 30;
    }

    $self->{clacks}->doNetwork();

    while((my $message = $self->{clacks}->getNext())) {
        if($message->{type} eq 'disconnect') {
            $self->{clacks}->listen('iptables::needsupdate');
            $self->{clacks}->ping();
            $self->{clacks}->doNetwork();
            $self->{nextping} = $now + 30;
            next;
        }

        next unless(defined($message->{name}));

        if($message->{name} eq 'iptables::needsupdate' && $message->{type} eq 'notify') {
            # Just remember that we should update iptables the NEXT cycle
            # This simplifies handling multiple messages without continuously rewriting iptables
            $self->{iptablesupdate} = 1;
        }

    }

    # Check for any iptables refresh requests via PG notifies
    while((my $message = $dbh->pg_notifies)) {
        my ($name, $pid, $payload) = @{$message};
        if($name eq 'updateiptables') {
            $reph->debuglog("Recieved NOTIFY updateiptables");
            $self->{iptablesupdate} = 1;
        }
    }
    $dbh->commit;


    return $workCount;
}

sub updateIPTables { ## no critic (Subroutines::ProhibitExcessComplexity)
    my ($self) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    $reph->debuglog("Updating IPTABLES");

    my @four;
    my @six;
    my @honeypotfour;
    my @honeypotsix;

    if(defined($self->{dyndnsstreaming})) {
        my $dyndnsstreamingip = '';
        my $dyndnssth = $dbh->prepare_cached("SELECT net_public1_ipv4 FROM COMPUTERS WHERE computer_name = ?")
            or croak($dbh->errstr);
        if(!$dyndnssth->execute($self->{dyndnsstreaming})) {
            $dbh->rollback;
        } else {
            my $line = $dyndnssth->fetchrow_hashref;
            if(defined($line->{net_public1_ipv4})) {
                $dyndnsstreamingip = $line->{net_public1_ipv4};
            }
            $dyndnssth->finish;
            $dbh->commit;
        }

        if($dyndnsstreamingip ne '') {
            push @four, '### Allow livestreaming from selected DynDNS address ###';
            push @four, "-A INPUT -p tcp -s $dyndnsstreamingip/32 --dport 8899 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT";
            push @four, "-A INPUT -p udp -s $dyndnsstreamingip/32 --dport 8899 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT";
            push @four, '### Allow livestreaming from selected DynDNS address ###';
        }
    }

    my $dnsipsel = $dbh->prepare_cached("SELECT DISTINCT external_sender FROM nameserver_blocklist_ip")
            or croak($dbh->errstr);

    my $dnshostsel = $dbh->prepare_cached("SELECT DISTINCT domain_fqdn FROM nameserver_blocklist_hostname")
            or croak($dbh->errstr);

    my $webipsel = $dbh->prepare_cached("SELECT DISTINCT ip_address FROM accesslog_blocklist")
            or croak($dbh->errstr);

    my $webcidrsel = $dbh->prepare_cached("SELECT DISTINCT blocked_network FROM firewall_block_cidr")
            or croak($dbh->errstr);

    my $sshsel = $dbh->prepare_cached("SELECT DISTINCT ip_addr FROM ssh_blocklist")
            or croak($dbh->errstr);

    my $honeypotsel = $dbh->prepare_cached("SELECT DISTINCT ip_addr FROM honeypot_blocklist")
            or croak($dbh->errstr);

    my $dovecotsel = $dbh->prepare_cached("SELECT DISTINCT ip_addr FROM dovecot_blocklist")
            or croak($dbh->errstr);

    my $postfixsel = $dbh->prepare_cached("SELECT DISTINCT ip_addr FROM postfix_blocklist")
            or croak($dbh->errstr);

    my $permablocksel = $dbh->prepare_cached("SELECT DISTINCT ip_addr FROM firewall_permablock")
            or croak($dbh->errstr);

    if(!$dnsipsel->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return;
    }
    my @dnsips;
    while((my $line = $dnsipsel->fetchrow_hashref)) {
        push @dnsips, $line->{external_sender};
    }
    $dnsipsel->finish;

    if(!$dnshostsel->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return;
    }
    my @dnshosts;
    while((my $line = $dnshostsel->fetchrow_hashref)) {
        # Also make sure we validate that hostname is valid according to RFC
        my $isvalid = 1;
        my $requestname = $line->{domain_fqdn};
        if($requestname =~ /[^A-Za-z0-9\.]+/) {
            $isvalid = 0;
        }
        if(length($requestname) > 253) {
            $isvalid = 0;
        }
        if($requestname =~ /\.\./) {
            $isvalid = 0;
        }

        next unless($isvalid);

        my $hname = '';
        my @hparts = split(/\./, $requestname);

        foreach my $hpart (@hparts) {
            # Hyphen only in the middle
            if($hpart =~ /^\-/ || $hpart =~ /\-$/) {
                $isvalid = 0;
            }
            if(length($hpart > 63)) {
                $isvalid = 0;
            }
            next unless($isvalid);
            $hname .= '|' . unpack("(H2)*", chr(length($hpart))) . '|' . $hpart;
        }
        next unless($isvalid);
        push @dnshosts, $hname;
    }
    $dnshostsel->finish;

    if(!$sshsel->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return;
    }
    my @sships;
    while((my $line = $sshsel->fetchrow_hashref)) {
        push @sships, $line->{ip_addr};
    }
    $sshsel->finish;

    if(!$honeypotsel->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return;
    }
    my @honeypotips;
    while((my $line = $honeypotsel->fetchrow_hashref)) {
        push @honeypotips, $line->{ip_addr};
    }
    $honeypotsel->finish;

    if(!$dovecotsel->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return;
    }
    my @dovecotips;
    while((my $line = $dovecotsel->fetchrow_hashref)) {
        push @dovecotips, $line->{ip_addr};
    }
    $dovecotsel->finish;


    if(!$postfixsel->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return;
    }
    my @postfixips;
    while((my $line = $postfixsel->fetchrow_hashref)) {
        push @postfixips, $line->{ip_addr};
    }
    $postfixsel->finish;

    if(!$webipsel->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return;
    }
    my @webips;
    while((my $line = $webipsel->fetchrow_hashref)) {
        push @webips, $line->{ip_address};
    }
    $webipsel->finish;

    if(!$webcidrsel->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return;
    }
    my @webcidrs;
    while((my $line = $webcidrsel->fetchrow_hashref)) {
        push @webcidrs, $line->{blocked_network};
    }
    $webcidrsel->finish;

    if(!$permablocksel->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return;
    }
    my @permablockips;
    while((my $line = $permablocksel->fetchrow_hashref)) {
        push @permablockips, $line->{ip_addr};
    }
    $permablocksel->finish;

    
    $dbh->commit;

    push @honeypotfour, "#    Block access to honeypot";
    push @honeypotsix, "#    Block access to honeypot";
    foreach my $ip (@honeypotips) {
        if($ip =~ /\./) {
            push @honeypotfour, "-A INPUT -s $ip -p tcp --dport 22 -j DROP";
        } else {
            push @honeypotsix, "-A INPUT -s $ip -p tcp --dport 22 -j DROP";
        }
    }

    push @four, "#    PermaBlock";
    push @six, "#    PermaBlock";
    foreach my $ip (@permablockips) {
        if($ip =~ /\./) {
            push @four, "-A INPUT -s $ip -j DROP";
        } else {
            push @six, "-A INPUT -s $ip -j DROP";
        }
    }
    
    # IPv4 only for DNS Hostnames for the moment.
    push @four, "#    DNS Hostname";
    foreach my $host (@dnshosts) {
        next if(!defined($host) || $host eq '');
        push @four, '-A INPUT -p udp --dport 53 -m string --hex-string "' . $host . '" --algo bm -j DROP';
    }

    push @four, "#    DNS IP";
    push @six, "#    DNS IP";
    foreach my $ip (@dnsips) {
        if($ip =~ /\./) {
            push @four, "-A INPUT -s $ip -p udp --dport 53 -j DROP";
            push @four, "-A INPUT -s $ip -p tcp --dport 53 -j DROP";
        } else {
            push @six, "-A INPUT -s $ip -p udp --dport 53 -j DROP";
            push @six, "-A INPUT -s $ip -p tcp --dport 53 -j DROP";
        }
    }

    push @four, "#    SSH";
    push @six, "#    SSH";
    foreach my $ip (@sships) {
        if($ip =~ /\./) {
            push @four, "-A INPUT -s $ip -p tcp --dport 22 -j DROP";
        } else {
            push @six, "-A INPUT -s $ip -p tcp --dport 22 -j DROP";
        }
    }

    push @four, "#    IMAP/Dovecot";
    push @six, "#    IMAP/Dovecot";
    foreach my $ip (@dovecotips) {
        if($ip =~ /\./) {
            push @four, "-A INPUT -s $ip -p tcp --dport 143 -j DROP";
            push @four, "-A INPUT -s $ip -p tcp --dport 993 -j DROP";
        } else {
            push @six, "-A INPUT -s $ip -p tcp --dport 143 -j DROP";
            push @six, "-A INPUT -s $ip -p tcp --dport 993 -j DROP";
        }
    }

    push @four, "#    IMAP/Postfix";
    push @six, "#    IMAP/Postfix";
    foreach my $ip (@postfixips) {
        if($ip =~ /\./) {
            push @four, "-A INPUT -s $ip -p tcp --dport 25 -j DROP";
            push @four, "-A INPUT -s $ip -p tcp --dport 587 -j DROP";
        } else {
            push @six, "-A INPUT -s $ip -p tcp --dport 25 -j DROP";
            push @six, "-A INPUT -s $ip -p tcp --dport 587 -j DROP";
        }
    }

    push @four, "#    Web/IP";
    push @six, "#    Web/IP";
    foreach my $ip (@webips) {
        if($ip =~ /\./) {
            push @four, "-A INPUT -s $ip -p tcp --dport 80 -j DROP";
            push @four, "-A INPUT -s $ip -p tcp --dport 443 -j DROP";
        } else {
            push @six, "-A INPUT -s $ip -p tcp --dport 80 -j DROP";
            push @six, "-A INPUT -s $ip -p tcp --dport 443 -j DROP";
        }
    }

    push @four, "#    Web/CIDR";
    push @six, "#    Web/CIDR";
    foreach my $cidr (@webcidrs) {
        if($cidr =~ /\./) {
            push @four, "-A INPUT -s $cidr -p tcp --dport 80 -j DROP";
            push @four, "-A INPUT -s $cidr -p tcp --dport 443 -j DROP";
        } else {
            push @six, "-A INPUT -s $cidr -p tcp --dport 80 -j DROP";
            push @six, "-A INPUT -s $cidr -p tcp --dport 443 -j DROP";
        }
    }

    # Update ip4 rules file
    {
        open(my $ifh, '<', '/etc/ip4tables.rules.template') or return; ## no critic (InputOutput::RequireBriefOpen)
        open(my $ofh, '>', '/etc/ip4tables.rules') or return; ## no critic (InputOutput::RequireBriefOpen)
        print $ofh "# AUTO-GENERATED BY PAGECAMEL - DO NOT EDIT\n";
        print $ofh "# EDIT /etc/ip4tables.rules.template instead and either send\n";
        print $ofh "# a) a clacks NOTIFY iptables::needsupdate\n";
        print $ofh "#    or\n";
        print $ofh "# b) a PostgreSQL NOTIFY updateiptables\n";
        print $ofh "\n";
        while((my $line = <$ifh>)) {
            if($line =~ /XXXPAGECAMELGENERATEDRULESXXX/) {
                print $ofh "# **** Start pagecamel-generated rules ****\n";
                foreach my $rule (@four) {
                    print $ofh $rule, "\n";
                }
                print $ofh "# **** End pagecamel-generated rules ****\n";
                next;
            } elsif($line =~ /XXXPAGECAMELBLOCKHONEYPOTXXX/) {
                print $ofh "# **** Start pagecamel-generated rules ****\n";
                foreach my $rule (@honeypotfour) {
                    print $ofh $rule, "\n";
                }
                print $ofh "# **** End pagecamel-generated rules ****\n";
                next;
            } else {
                print $ofh $line;
            }
        }
        close $ifh;
        close $ofh;
    }
    
    # Update ip6 rules file
    {
        open(my $ifh, '<', '/etc/ip6tables.rules.template') or return; ## no critic (InputOutput::RequireBriefOpen)
        open(my $ofh, '>', '/etc/ip6tables.rules') or return; ## no critic (InputOutput::RequireBriefOpen)
        print $ofh "# AUTO-GENERATED BY PAGECAMEL - DO NOT EDIT\n";
        print $ofh "# EDIT /etc/ip6tables.rules.template instead and either send\n";
        print $ofh "# a) a clacks NOTIFY iptables::needsupdate\n";
        print $ofh "#    or\n";
        print $ofh "# b) a PostgreSQL NOTIFY updateiptables\n";
        print $ofh "\n";
        while((my $line = <$ifh>)) {
            if($line =~ /XXXPAGECAMELGENERATEDRULESXXX/) {
                print $ofh "# **** Start pagecamel-generated rules ****\n";
                foreach my $rule (@six) {
                    print $ofh $rule, "\n";
                }
                print $ofh "# **** End pagecamel-generated rules ****\n";
                next;
            } elsif($line =~ /XXXPAGECAMELBLOCKHONEYPOTXXX/) {
                print $ofh "# **** Start pagecamel-generated rules ****\n";
                foreach my $rule (@honeypotsix) {
                    print $ofh $rule, "\n";
                }
                print $ofh "# **** End pagecamel-generated rules ****\n";
                next;
            } else {
                print $ofh $line;
            }
        }
        close $ifh;
        close $ofh;
    }

    $reph->debuglog("Loading ip4 rules into kernel");
    `iptables-restore < /etc/ip4tables.rules`;
    $reph->debuglog("Loading ip6 rules into kernel");
    `ip6tables-restore < /etc/ip6tables.rules`;
    $reph->debuglog("Firewall updated");


    $self->{iptablesupdate} = 0;
    return;
}


1;
__END__

=head1 NAME

PageCamel::Worker::SerialCommands -

=head1 SYNOPSIS

  use PageCamel::Worker::SerialCommands;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 crossregister



=head2 work



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
