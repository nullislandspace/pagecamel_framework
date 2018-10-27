package PageCamel::Worker::Logging::Plugins::USV;
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

use WWW::Mechanize::GZip;
use HTML::TableExtract;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    if(!defined($self->{sendclacks})) {
        $self->{sendclacks} = 0;
    }

    return $self;
}

sub crossregister {
    my $self = shift;

    $self->register_plugin('work', 'USV', 'USV');

    return;
}

sub work {
    my ($self, $device, $dbh, $reph, $memh) = @_;

    if($self->{sendclacks}) {
        my $type = ref $memh;

        if($type !~ /ClacksCache$/ && $type !~ /ClacksCachePg$/) {
            croak("memcache type is $type but needs to be of type ClacksCache or ClackCachePg in module " . $self->{modname});
        }
    }

    my $workCount = 0;

    $reph->debuglog("Logging USV for " . $device->{hostname} . " at " . $device->{ip_addr});
    # Refresh Lifetick every now and then
    $memh->refresh_lifetick;

    my $mech = WWW::Mechanize::GZip->new();
    $mech->credentials($device->{device_username}, $device->{device_password});

    my $url = 'http://' . $device->{ip_addr} . '/status.htm?UpsIndex=0';
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
        my %data = $self->parseContent($content);
        $data{hostname} = $device->{hostname};
        $data{device_type} = 'USV';

        if($self->{sendclacks}) {
            my $totaloutput = $data{out_power1} + $data{out_power2} + $data{out_power3};
            my $clackskey = 'USV::' . $device->{hostname} . '::Output';
            $memh->clacks_set($clackskey, $totaloutput);
        }

        my ($keys, $vals) = ("", "");
        foreach my $key (sort keys %data) {
            $keys .= ",$key";
            if($key eq "hostname" || $key eq "bat_status" || $key eq "device_type") {
                $vals .= "," . $dbh->quote($data{$key});
            } else {
                $vals .= "," . $data{$key};
            }
        }
        $keys =~ s/^\,//o;
        $vals =~ s/^\,//o;
        my $instmt = "INSERT INTO logging_log_usv ($keys) VALUES ($vals)";
        my $insth = $dbh->prepare($instmt) or croak($dbh->errstr);
        $insth->execute or croak($dbh->errstr);
        $insth->finish;
        $dbh->commit;
        $workCount++;
    } else {
        $reph->debuglog("Access failed to " . $device->{hostname} . "!");
        my $errorstmt = "INSERT INTO logging_log_usv (hostname, device_type, device_ok)
                        VALUES (" . $dbh->quote($device->{hostname}) . ", 'USV', 'f')";
        my $errorsth = $dbh->prepare($errorstmt) or croak($dbh->errstr);
        $errorsth->execute or croak($dbh->errstr);
        $errorsth->finish;
        $dbh->commit;
    }

    $dbh->rollback;


    return $workCount;
}

sub tableToText {
    my ($self, $content) = @_;

    my $te = HTML::TableExtract->new;
    $te->parse($content);

    my @rows;
    foreach my $ts ($te->tables) {
        #print "Table (", join(',', $ts->coords), "):\n";
        foreach my $row ($ts->rows) {
            push @rows, join(',', @{$row});
        }
    }

    return @rows;
}

sub parseContent {
    my ($self, $content) = @_;

    my @rows = $self->tableToText($content);

    my %values;

    my @ignore = ("Battery Group", "BatteryRipple, not available", "Input Group",
                  "Output Group", "Bypass Group");

    while((scalar @rows)) {
        my $line = shift @rows;

        if(contains($line, \@ignore)) {
            next;
        } elsif($line =~ /BatteryStatus,(.*)/o) {
            $values{bat_status} = $1;
        } elsif($line =~ /SecondsOnBattery,(.*)\ sec/o) {
            $values{bat_used} = $1;
        } elsif($line =~ /EstimatedMinuteRemain,(.*)\ min/o) {
            $values{bat_timeremain} = $1;
        } elsif($line =~ /EstimatedChargeRemain,(.*)\%/o) {
            $values{bat_chargeremain} = $1;
        } elsif($line =~ /BatteryVoltage,(.*)\ Volt/o) {
            $values{bat_voltage} = $1;
        } elsif($line =~ /BatteryCurrent,(.*)\ AMP/o) {
            $values{bat_current} = $1;
        } elsif($line =~ /BatteryTemperature,(.*)\ Celsius/o) {
            $values{bat_temp} = $1;
        } elsif($line eq 'Phase,Frequency,Voltage,Current,TruePower') {
            for(1..3) {
                my ($key, undef, $voltage) = split /\,/, shift @rows;
                $key = "in_voltage$key";
                $voltage =~ s/\ V//go;
                $values{$key} = $voltage;
            }
        } elsif($line eq 'Phase,Voltage,Current,Power,Load,Power Factor,Peak Current,Share Current') {
            for(1..3) {
                my ($key, $voltage, $current, $power, $load) = split /\,/, shift @rows;

                $voltage =~ s/\ V//go;
                $values{"out_voltage$key"} = $voltage;
                $current =~ s/\ A//go;
                $values{"out_current$key"} = $current;
                $power =~ s/\ Watt.*//go;
                $values{"out_power$key"} = $power;
                $load =~ s/\%//go;
                $values{"out_load$key"} = $load;
            }
        }
    }

    return %values;
}

1;
__END__

=head1 NAME

PageCamel::Worker::Logging::Plugins::USV - Get states/voltages/etc from GE Digital Energy UPS

=head1 SYNOPSIS

  use PageCamel::Worker::Logging::Plugins::USV;

=head1 DESCRIPTION

Access the webserver of a GE Digital Energy uninterruptible power suply (only tested with the SG series)
and log the values. This is a logging plugin.

=head2 new

Create a new instance

=head2 crossregister

Register the work callback

=head2 work

Log the data

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
