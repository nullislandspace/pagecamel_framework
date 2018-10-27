package PageCamel::Worker::Firewall::IPTables;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 1;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

# Do some updates and advanced parsing for accesslog. Run at once an hour. The
# Exception here is: If workCount > 0 then it will ru in the next loop too

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DBSerialize;
use MIME::Base64;
use Net::Clacks::Client;
use Data::Dumper;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = Net::Clacks::Client->new($clconf->get('host'), $clconf->get('port'), $clconf->get('user'), $clconf->get('password'), $self->{PSAPPNAME} . ':' . $self->{modname});

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

sub updateIPTables {
    my ($self) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    $reph->debuglog("Updating IPTABLES");

    my @four;
    my @six;

    my $dnssel = $dbh->prepare_cached("SELECT DISTINCT external_sender FROM nameserver_blocklist_ip")
            or croak($dbh->errstr);

    my $webipsel = $dbh->prepare_cached("SELECT DISTINCT ip_address FROM accesslog_blocklist")
            or croak($dbh->errstr);

    my $webcidrsel = $dbh->prepare_cached("SELECT DISTINCT blocked_network FROM firewall_block_cidr")
            or croak($dbh->errstr);

    my $sshsel = $dbh->prepare_cached("SELECT DISTINCT ip_addr FROM ssh_blocklist")
            or croak($dbh->errstr);

    my $dovecotsel = $dbh->prepare_cached("SELECT DISTINCT ip_addr FROM dovecot_blocklist")
            or croak($dbh->errstr);

    my $postfixsel = $dbh->prepare_cached("SELECT DISTINCT ip_addr FROM postfix_blocklist")
            or croak($dbh->errstr);

    my $permablocksel = $dbh->prepare_cached("SELECT DISTINCT ip_addr FROM firewall_permablock")
            or croak($dbh->errstr);

    if(!$dnssel->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return;
    }
    my @dnsips;
    while((my $line = $dnssel->fetchrow_hashref)) {
        push @dnsips, $line->{external_sender};
    }
    $dnssel->finish;

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

    push @four, "#    PermaBlock";
    push @six, "#    PermaBlock";
    foreach my $ip (@permablockips) {
        if($ip =~ /\./) {
            push @four, "-A INPUT -s $ip -j REJECT";
        } else {
            push @six, "-A INPUT -s $ip -j REJECT";
        }
    }

    push @four, "#    DNS";
    push @six, "#    DNS";
    foreach my $ip (@dnsips) {
        if($ip =~ /\./) {
            push @four, "-A INPUT -s $ip -p udp --dport 53 -j REJECT";
            push @four, "-A INPUT -s $ip -p tcp --dport 53 -j REJECT";
        } else {
            push @six, "-A INPUT -s $ip -p udp --dport 53 -j REJECT";
            push @six, "-A INPUT -s $ip -p tcp --dport 53 -j REJECT";
        }
    }

    push @four, "#    SSH";
    push @six, "#    SSH";
    foreach my $ip (@sships) {
        if($ip =~ /\./) {
            push @four, "-A INPUT -s $ip -p tcp --dport 22 -j REJECT";
        } else {
            push @six, "-A INPUT -s $ip -p tcp --dport 22 -j REJECT";
        }
    }

    push @four, "#    IMAP/Dovecot";
    push @six, "#    IMAP/Dovecot";
    foreach my $ip (@dovecotips) {
        if($ip =~ /\./) {
            push @four, "-A INPUT -s $ip -p tcp --dport 143 -j REJECT";
            push @four, "-A INPUT -s $ip -p tcp --dport 993 -j REJECT";
        } else {
            push @six, "-A INPUT -s $ip -p tcp --dport 143 -j REJECT";
            push @six, "-A INPUT -s $ip -p tcp --dport 993 -j REJECT";
        }
    }

    push @four, "#    IMAP/Postfix";
    push @six, "#    IMAP/Postfix";
    foreach my $ip (@postfixips) {
        if($ip =~ /\./) {
            push @four, "-A INPUT -s $ip -p tcp --dport 25 -j REJECT";
            push @four, "-A INPUT -s $ip -p tcp --dport 587 -j REJECT";
        } else {
            push @six, "-A INPUT -s $ip -p tcp --dport 25 -j REJECT";
            push @six, "-A INPUT -s $ip -p tcp --dport 587 -j REJECT";
        }
    }

    push @four, "#    Web/IP";
    push @six, "#    Web/IP";
    foreach my $ip (@webips) {
        if($ip =~ /\./) {
            push @four, "-A INPUT -s $ip -p tcp --dport 80 -j REJECT";
            push @four, "-A INPUT -s $ip -p tcp --dport 443 -j REJECT";
        } else {
            push @six, "-A INPUT -s $ip -p tcp --dport 80 -j REJECT";
            push @six, "-A INPUT -s $ip -p tcp --dport 443 -j REJECT";
        }
    }

    push @four, "#    Web/CIDR";
    push @six, "#    Web/CIDR";
    foreach my $cidr (@webcidrs) {
        if($cidr =~ /\./) {
            push @four, "-A INPUT -s $cidr -p tcp --dport 80 -j REJECT";
            push @four, "-A INPUT -s $cidr -p tcp --dport 443 -j REJECT";
        } else {
            push @six, "-A INPUT -s $cidr -p tcp --dport 80 -j REJECT";
            push @six, "-A INPUT -s $cidr -p tcp --dport 443 -j REJECT";
        }
    }

    # Update ip4 rules file
    {
        open(my $ifh, '<', '/etc/ip4tables.rules.template') or return;
        open(my $ofh, '>', '/etc/ip4tables.rules') or return;
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
            } else {
                print $ofh $line;
            }
        }
        close $ifh;
        close $ofh;
    }
    
    # Update ip6 rules file
    {
        open(my $ifh, '<', '/etc/ip6tables.rules.template') or return;
        open(my $ofh, '>', '/etc/ip6tables.rules') or return;
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

Copyright (C) 2008-2016 by Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
