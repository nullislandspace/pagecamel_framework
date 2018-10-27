package PageCamel::Worker::Logging::Plugins::EMCTime;
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

use base qw(PageCamel::Worker::Logging::PluginBase);

use Net::SNMP;
use Net::Ping;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->loadMiniMIB();

    return $self;
}

sub crossregister {
    my $self = shift;

    $self->register_plugin('work', 'EMCTIME', 'EMCTIME');
    return;
}

sub loadMiniMIB {
    my ($self) = @_;

    my @MIBS = $self->loadMIB();

    my %mibdef;
    foreach my $mib (@MIBS) {
        chomp $mib;
        my @parts = split/;/, $mib;
        next if($parts[0] eq 'ID');
        $mibdef{$parts[0]} = $parts[1];
    }

    $self->{mibdef} = \%mibdef;
    return;
}

sub loadMIB {
    my ($self) = @_;

    my $MIB =<<"MINIMIB";
ID;ColName;Description
1.3.6.1.4.1.28507.3.1.6.0;temperature;Temperature in 1/10 degree Celsius
1.3.6.1.4.1.28507.3.1.5.0;dcf_ok;Is DCF77 active or do we use the quarz
MINIMIB

    my @MIBS = split/\n/,$MIB;

    return @MIBS;
}

sub work {
    my ($self, $device, $dbh, $reph, $memh) = @_;

    my $workCount = 0;

    $reph->debuglog("Logging EMCTime for " . $device->{hostname} . " at " . $device->{ip_addr});
    # Refresh Lifetick every now and then
    $memh->refresh_lifetick;

    my ($ok, %vals) = $self->getValues($device->{ip_addr}, $reph);
    if($ok) {

        my @dcols = qw[hostname device_type device_ok];
        my @dvals = ("'$device->{hostname}'", "'EMCTIME'", "'t'");

        foreach my $key (keys %vals) {
            my $colname = $self->{mibdef}->{$key};
            my $val = $vals{$key};

            if($colname eq "temperature") {
                $val = $val / 10;
            } elsif($colname =~ /(?:is|has|active|ok)/) {
                if($val == 1) {
                    $val = "'t'";
                } else {
                    $val = "'f'";
                }
            }
            push @dcols, $colname;
            push @dvals, $val;
        }

        my $columns = join(',', @dcols);
        my $values = join(',', @dvals);

        my $instmt = "INSERT INTO logging_log_emctime ($columns) VALUES ($values)";
        my $insth = $dbh->prepare($instmt) or croak($dbh->errstr);
        $insth->execute or croak($dbh->errstr);
        $insth->finish;
        $dbh->commit;
        $workCount++;
    } else {
        $reph->debuglog("Access failed to " . $device->{hostname} . "!");
        my $errorstmt = "INSERT INTO logging_log_emctime (hostname, device_type, device_ok)
                        VALUES (" . $dbh->quote($device->{hostname}) . ", 'EMCTIME', 'f')";
        my $errorsth = $dbh->prepare($errorstmt) or croak($dbh->errstr);
        $errorsth->execute or croak($dbh->errstr);
        $errorsth->finish;
        $dbh->commit;
    }
    return $workCount;
}

sub getValues {
    my ($self, $ip, $reph) = @_;

    $reph->debuglog("  Connecting to $ip");

    my ($session,$error) = Net::SNMP->session(Hostname => $ip,
                                       Community => 'public');

    if(!$session) {
        $reph->debuglog("Can't get session to $ip: $error");
    }
    return 0 unless($session);

    # First, try to ping sensor
    my $pinger = Net::Ping->new();
    if(!$pinger->ping($ip, 2)) { # 2 second timeout
        $reph->debuglog("  Failed to ping $ip");
        return 0;
    }


    my %vals;
    my $ok = 1;

    my $previous_alarm;

    if(!eval {
        local $SIG{ALRM} = sub { croak "Timed out!\n"};
        my $timeout = $self->{timeout};

        $previous_alarm = alarm($timeout);

        foreach my $id (keys %{$self->{mibdef}}) {
            my $result = $session->get_request($id);
            if(defined($result) && defined($result->{$id}) && $result->{$id} ne '') {
                $vals{$id} = $result->{$id};
            } else {
                my $xerror = $session->error();
                $reph->debuglog("   Error: $xerror");
                $ok = 0;
            }
        }
        alarm($previous_alarm);
        1;
    }) {
        $ok = 0;
    }

    if($EVAL_ERROR =~ /timed out/i) {
        $reph->debuglog("  Timeout reached!");
        $ok = 0;
    } elsif($EVAL_ERROR) {
        $reph->debuglog("  Unknown error: $EVAL_ERROR");
    }

    $session->close;

    return $ok, %vals;

}


1;
__END__

=head1 NAME

PageCamel::Worker::Logging::Plugins::EMCTime - Log data from "EMC Professional" DCF77 clock

=head1 SYNOPSIS

  use PageCamel::Worker::Logging::Plugins::EMCTime;

=head1 DESCRIPTION

Log states of "EMC Professional" DCF77 clock via SNMP. This is a
logging plugin.

=head2 new

Create a new instace

=head2 crossregister

Register work callback

=head2 loadMiniMIB

Load a "mini" MIB file

=head2 loadMIB

The "mini" MIB file

=head2 work

Log data every minute

=head2 getValues

Load current states via SNMP

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
