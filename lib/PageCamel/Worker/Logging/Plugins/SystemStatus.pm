package PageCamel::Worker::Logging::Plugins::SystemStatus;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.7;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::Logging::PluginBase);

#use Sys::Statistics::Linux::MemStats;
use Sys::Load qw(getload uptime);
use PageCamel::Helpers::Strings qw(stripString);

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{firstrun} = 1;

    return $self;
}

sub crossregister {
    my $self = shift;

    $self->register_plugin('work', 'SYSTEMSTATUS', 'SYSTEMSTATUS');
    return;
}

sub loadColumns {
    my ($self, $dbh) = @_;

    my %cols;
    my $selsth = $dbh->prepare("SELECT column_name, data_type FROM information_schema.columns
                                WHERE table_name = 'logging_log_systemstatus'")
            or croak($dbh->errstr);
    $selsth->execute or croak($dbh->errstr);
    while((my $line = $selsth->fetchrow_hashref)) {
        $cols{$line->{column_name}} = $line->{data_type};
    }
    $selsth->finish;
    $self->{dbcols} = \%cols;


    return;
}

sub work {
    my ($self, $device, $dbh, $reph, $memh) = @_;

    my $workCount = 0;

    if($self->{firstrun}) {
        $self->{firstrun} = 0;
        $self->loadColumns($dbh);
        $workCount++;
    }

    $reph->debuglog("Logging system status for " . $device->{hostname});
    # Refresh Lifetick every now and then
    $memh->refresh_lifetick;


    my (%sensors);

    $self->getCPUTemp(\%sensors);
    #$self->getMeminfo(\%sensors);
    $self->getSysload(\%sensors);
    $self->getIPMI(\%sensors);


    my (@dbkeys, @vals, @spacers);
    foreach my $key (keys %sensors) {
        push @dbkeys, $key;
        push @vals, $sensors{$key};
        push @spacers, '?';
    }

    my $insth = $dbh->prepare_cached("INSERT INTO logging_log_systemstatus (hostname, device_ok, device_type, " . join(',', @dbkeys) . ")
                                        VALUES(?, true, 'SYSTEMSTATUS', " . join(',', @spacers) . ")")
            or croak($dbh->errstr);
    if($insth->execute($device->{hostname}, @vals)) {
        $dbh->commit;
        $workCount++;
    } else {
        $dbh->rollback;
        $reph->debuglog("   Failed to update system status");
    }

    $dbh->rollback;
    return $workCount;
}

sub getCPUTemp {
    my($self, $sensors) = @_;

    my $cmd = $self->{sensors};
    my @lines = `$cmd`;

    foreach my $line (@lines) {
        chomp $line;
        next if($line !~ /^Core\ \d/);
        $line =~ s/\(.*//g;
        if($line =~ /Core.(\d+)\:.*([+-].*)\°/) {
            my ($core, $val) = ($1, $2);
            $val =~ s/\+//g;
            $val =~ s/[^0-9\.]//g;
            my $keyname = 'cpu_core' . $core . '_temp';
            next if(!defined($self->{dbcols}->{$keyname}));
            $sensors->{$keyname} = $val;
        }
    }
    return;
}

#sub getMeminfo {
#    my($self, $sensors) = @_;
#
#    my $lxs  = Sys::Statistics::Linux::MemStats->new;
#    my $stat = $lxs->get;
#
#    my %statkeys = (
#        swap_used_kb => "swapused",
#        swap_free_kb => "swapfree",
#        mem_used_kb => "memused",
#        mem_free_kb => "memfree",
#        mem_active_kb => "active",
#        mem_inactive_kb => "inactive",
#        mem_dirty_kb => "dirty",
#    );
#
#    foreach my $key (keys %statkeys) {
#        next if(!defined($self->{dbcols}->{$key}));
#        $sensors->{$key} = $stat->{$statkeys{$key}};
#    }
#
#    return;
#}


sub getSysload {
    my($self, $sensors) = @_;

    $sensors->{uptime_seconds} = int uptime();
    ($sensors->{sysload_1min}, $sensors->{sysload_5min}, $sensors->{sysload_15min}) = getload();

    return;
}

sub getIPMI {
    my($self, $sensors) = @_;

    my $cmd = $self->{ipmi};
    my @lines = `$cmd`;

    foreach my $line (@lines) {
        chomp $line;
        my ($keyname, $val) = split(/\|/, $line);
        $val = stripString($val);
        $keyname = lc(stripString($keyname));
        $keyname =~ s/\+//g;
        $keyname =~ s/\ /_/g;
        $keyname =~ s/\./_/g;
        if(!defined($self->{dbcols}->{$keyname}) && defined($self->{dbcols}->{$keyname . '_ok'})) {
            $keyname .= '_ok';
        }
        next if(!defined($self->{dbcols}->{$keyname}));
        if($self->{dbcols}->{$keyname} eq 'boolean') {
            if($val eq '0x0') {
                $val = 0;
            } else {
                $val = 1;
            }
        } elsif($self->{dbcols}->{$keyname} eq 'integer') {
            $val = int($val);
        }
        $sensors->{$keyname} = $val;
    }
    return;
}

1;
__END__

=head1 NAME

PageCamel::Worker::Logging::Plugins::SystemStatus - Log system/server status

=head1 SYNOPSIS

  use PageCamel::Worker::Logging::Plugins::SystemStatus;

=head1 DESCRIPTION

Log various states and sensor readings from server and operating system. This is a logging plugin.

This is somewhat adaptive, since it only tries to work on sensor values for which a database
column exists (same plugin can work on differenrt hardware, only the table columns need adjusting)

=head2 new

Create new intance

=head2 crossregister

Register work callback

=head2 loadColumns

Load list of available database columns

=head2 work

Logging callback

=head2 getCPUTemp

Read CPU temperatures

=head2 getMeminfo

Load the memory usage stats

=head2 getSysload

Get processor load

=head2 getIPMI

Get IMPI info

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
