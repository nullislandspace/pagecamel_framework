package PageCamel::Worker::Logging::Plugins::TempSensor_HWG_STE;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.8;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::Logging::PluginBase);

use Net::SNMP;
use Net::Ping;
use WWW::Mechanize::GZip;
use XML::Simple;

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

    $self->register_plugin('work', 'TEMPSENSOR', 'HWG-STE snmp');
    $self->register_plugin('work', 'TEMPSENSOR', 'HWG-STE http');
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
1.3.6.1.4.1.21796.4.1.3.1.7.n;type;1 = Temp, 4 = Humidity
1.3.6.1.4.1.21796.4.1.3.1.4.n;sensor_value;Sensor Value as string
1.3.6.1.4.1.21796.4.1.3.1.3.n;sensor_state;0=Invalid, 1=Normal, 2=OutOfRangeLo, 3=OutOfRangeHi, 4=AlarmLo, 5=AlarmHi
MINIMIB

    my @MIBS = split/\n/,$MIB;

    return @MIBS;
}

sub work {
    my ($self, $device, $dbh, $reph, $memh) = @_;

    my $workCount = 0;

    $reph->debuglog("Logging TempSensor HWG-STE for " . $device->{hostname} . " at " . $device->{ip_addr});
    # Refresh Lifetick every now and then
    $memh->refresh_lifetick;

    my ($ok, %vals);
    if($device->{device_subtype} eq 'HWG-STE snmp') {
        my $port = 161;
        if($device->{tcp_port} != 0) {
            $port = $device->{tcp_port};
        }
        ($ok, %vals) = $self->getSNMPValues($reph, $device->{ip_addr}, $port);
    } else {
        my $port = 80;
        if($device->{tcp_port} != 0) {
            $port = $device->{tcp_port};
        }
        ($ok, %vals) = $self->getXMLValues($reph, $device->{ip_addr}, $port);
    }
    if($ok) {

        my @dcols = qw[hostname device_type];
        my @dvals = ("'$device->{hostname}'", "'TEMPSENSOR'");

        foreach my $key (keys %vals) {
            #my $colname = $self->{mibdef}->{$key};
            my $colname = $key;
            my $val = $vals{$key};

            if($colname =~ /(?:is|has|active|ok)/) {
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

        my $instmt = "INSERT INTO logging_log_tempsensor ($columns) VALUES ($values)";
        my $insth = $dbh->prepare($instmt) or croak($dbh->errstr);
        $insth->execute or croak($dbh->errstr);
        $insth->finish;
        $dbh->commit;
        $workCount++;
    } else {
        $reph->debuglog("Access failed to " . $device->{hostname} . "!");
        my $errorstmt = "INSERT INTO logging_log_tempsensor (hostname, device_type, device_ok)
                        VALUES (" . $dbh->quote($device->{hostname}) . ", 'TEMPSENSOR', 'f')";
        my $errorsth = $dbh->prepare($errorstmt) or croak($dbh->errstr);
        $errorsth->execute or croak($dbh->errstr);
        $errorsth->finish;
        $dbh->commit;
    }

    $dbh->rollback;
    return $workCount;
}

# ************************************************************************************
# ************************************************************************************

sub getSNMPValues {
    my ($self, $reph, $ip, $port) = @_;

    $reph->debuglog("  Connecting to $ip:$port");

    my ($session,$error) = Net::SNMP->session(Hostname => $ip,
                                       Community => 'public',
                                       Port => $port);

    return 0 unless($session);

    my %vals = (
        device_ok           => 0,
        temperature         => 0.0,
        temperature_state   => 0,
        humidity            => 0.0,
        humidity_state      => 0,
    );

    # First, try to ping sensor
    my $pinger = Net::Ping->new();
    if(!$pinger->ping($ip, 4)) { # 2 second timeout
        $reph->debuglog("  Failed to ping **" . $ip . "**");
        return 0, %vals;
    }


    my $havedata = 0;
    my $previous_alarm;

    if(!eval {
        local $SIG{ALRM} = sub { croak "Timed out!\n"};
        my $timeout = $self->{timeout};

        $previous_alarm = alarm($timeout);

        # loop through all sensors
        for(my $i = 1; $i <= 2; $i++) {
            my %tempvals;

            foreach my $id (keys %{$self->{mibdef}}) {
                my $fullid = $id;
                $fullid =~ s/n/$i/gio;
                my $result = $session->get_request($fullid);
                if(defined($result) && defined($result->{$fullid}) && $result->{$fullid} ne '') {
                    $tempvals{$self->{mibdef}->{$id}} = $result->{$fullid};
                    $havedata = 1;
                }
            }

            if($havedata) {
                $vals{device_ok} = 1;
                my $prefix;

                if($tempvals{type} == 1) {
                    $prefix = "temperature";
                } elsif($tempvals{type} == 4) {
                    $prefix = "humidity";
                } else {
                    next;
                }

                $vals{$prefix} = 0.0 + $tempvals{sensor_value};
                $vals{$prefix . "_state"} = 0.0 + $tempvals{sensor_state};

                if($vals{$prefix . "_state"} == 0) {
                    $vals{$prefix} = 0.0; # Broken sensor defaults to 0.0 instead of -999.9!
                }
            }
        }

        alarm($previous_alarm);
        1;
    }) {
        $havedata = 0;
    }

    if($EVAL_ERROR =~ /timed out/i) {
        $reph->debuglog("  Timeout reached!");
        $havedata = 0;
    }
    $session->close;
    return $havedata, %vals;

}


# ************************************************************************************
# ************************************************************************************

sub getXMLValues {
    my ($self, $reph, $ip, $port) = @_;

    $reph->debuglog("  XML-Connecting to $ip:$port");


    my %vals = (
        device_ok           => 0,
        temperature         => 0.0,
        temperature_state   => 0,
        humidity            => 0.0,
        humidity_state      => 0,
    );

    my $mech = WWW::Mechanize::GZip->new();
    #$mech->credentials($device->{device_username}, $device->{device_password});

    my $url = 'http://' . $ip . ':' . $port . '/values.xml';
    my $success = 0;
    my $result;
    if(!(eval {
        $result = $mech->get($url);
        $success = 1;
        1;
    })) {
        $success = 0;
    }
    if($success && defined($result) && $result->is_success) {
        my $content = $result->content;

        my $states = XMLin($content);

        foreach my $sensor (@{$states->{SenSet}->{Entry}}) {
            my $prefix = 'humidity';
            if($sensor->{Units} eq 'C') {
                $prefix = 'temperature';
            }
            $vals{$prefix} = $sensor->{Value};
            $vals{$prefix . "_state"} = $sensor->{State};

            if($vals{$prefix . "_state"} == 0) {
                $vals{$prefix} = 0.0; # Broken sensor defaults to 0.0 instead of -999.9!
            }
        }
        $vals{device_ok} = 1;

    } else {
        $reph->debuglog("  Failed");
        return 0, %vals;
    }


    return 1, %vals;

}

1;
__END__

=head1 NAME

PageCamel::Worker::Logging::Plugins::TempSensor_HWG_STE - log data from HWG-STR sensors

=head1 SYNOPSIS

  use PageCamel::Worker::Logging::Plugins::TempSensor_HWG_STE;


=head1 DESCRIPTION

Log data from HWG-STE temperatur/humidity sensors. This is a logging plugin.

=head2 new

Create new instance

=head2 crossregister

Register the work callback

=head2 loadMiniMIB

Load "mini" MIB file

=head2 loadMIB

The "mini" MIB file

=head2 work

Log data

=head2 getSNMPValues

Get values via SNMP

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
