package PageCamel::Worker::Logging::Plugins::PageCamelStats;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::Logging::PluginBase);
use Net::Clacks::Client;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};

    $self->{clacks} = $self->newClacksFromConfig($clconf);

    return $self;
}

sub crossregister($self) {
    $self->register_plugin('work', 'WEBGUI', 'ACCESS');
    return;
}

sub work($self, $device, $dbh, $reph, $memh) {
    my $workCount;

    $workCount += $self->workWebgui($device, $dbh, $reph, $memh);
    $workCount += $self->workFirewall($device, $dbh, $reph, $memh);

    $self->{clacks}->ping();
    $self->{clacks}->doNetwork();

    return $workCount;
}

sub workWebgui($self, $device, $dbh, $reph, $memh) {
    my $workCount = 0;

    $reph->debuglog("Logging webclicks status for " . $device->{hostname});
    $memh->refresh_lifetick;

    my $ok = 1;

    my @keys = qw[
            status_websocket_count
            status_redirect_count
            status_unchanged_count
            status_delivered_count
            status_notfound_count
            status_servererror_count
            status_other_count
            user_guest_count
            user_nonguest_count
            method_get_count
            method_head_count
            method_post_count
            method_put_count
            method_options_count
            method_propfind_count
            method_delete_count
            method_connect_count
            method_other_count
            postfix_loginerror_count
            dovecot_loginerror_count
            ssh_loginerror_count
            dns_request_count
        ];

    my $cols = join(',', @keys);
    my @placeholders;
    my @values;
    my $callcount = 0;
    my $loginerrors = 0;
    foreach my $key (@keys) {
        push @placeholders, '?';
        my $val = $memh->get('WebStats::' . $key);
        if(!defined($val)) {
            $val = 0;
            $ok = 0;
        } else {
            $val = 0 + $val;
        }
        $memh->decr('WebStats::' . $key, $val);
        $self->{clacks}->set('CAVACDISPLAY::' . $key, $val);
        if($key eq 'user_guest_count' || $key eq 'user_nonguest_count') {
            $callcount += $val;
        }
        if($key eq 'postfix_loginerror_count' || $key eq 'dovecot_loginerror_count' || $key eq 'ssh_loginerror_count') {
            $loginerrors += $val;
        }
        push @values, $val;
    }

    $self->{clacks}->set('CAVACDISPLAY::Webcalls', $callcount);
    $self->{clacks}->set('CAVACDISPLAY::LoginErrors', $loginerrors);

    my $placeholder = join(',', @placeholders);

    my $insth = $dbh->prepare_cached("INSERT INTO logging_log_webgui (hostname, device_ok, device_type, $cols)
                                        VALUES(?, ?, 'WEBGUI', $placeholder)")
            or croak($dbh->errstr);
    if($insth->execute($device->{hostname}, $ok, @values)) {
        $dbh->commit;
        $workCount++;
    } else {
        $dbh->rollback;
        $reph->debuglog("   Failed to update webstats");
    }

    $dbh->rollback;
    return $workCount;
}

sub workFirewall($self, $device, $dbh, $reph, $memh) {
    $reph->debuglog("Updating CAVACDISPLAY for Firewall");
    $memh->refresh_lifetick;

    {
        my $ipselsth = $dbh->prepare_cached("SELECT count(*) AS blockcount
                                            FROM accesslog_blocklist")
                or croak($dbh->errstr);
        if(!$ipselsth->execute) {
            $dbh->rollback;
            $reph->debuglog("   Failed to get IP blocklist count");
        } else {
            my $line = $ipselsth->fetchrow_hashref;
            $ipselsth->finish;
            $self->{clacks}->set('CAVACDISPLAY::IPBlocks', $line->{blockcount});
        }
    }

    {
        my $cidrselsth = $dbh->prepare_cached("SELECT count(*) AS blockcount
                                            FROM firewall_block_cidr")
                or croak($dbh->errstr);
        if(!$cidrselsth->execute) {
            $dbh->rollback;
            $reph->debuglog("   Failed to get IP blocklist count");
        } else {
            my $line = $cidrselsth->fetchrow_hashref;
            $cidrselsth->finish;
            $self->{clacks}->set('CAVACDISPLAY::CIDRBlocks', $line->{blockcount});
        }
    }

    $dbh->rollback;

    return 2;
}

1;
__END__

=head1 NAME

PageCamel::Worker::Logging::Plugins::PageCamelStats - Log PageCamel internal statistics

=head1 SYNOPSIS

  use PageCamel::Worker::Logging::Plugins::PageCamelStats;

=head1 DESCRIPTION

This module logs PageCamel internal statistics (webcall/minute, ...) and also updates some external
displays via CLACKS.

This is a logging plugin.

=head2 new

Create new instance

=head2 crossregister

Register work callback

=head2 work

Logging callback

=head2 workWebgui

Log data from webgui

=head2 workFirewall

Log data from Firewall

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
