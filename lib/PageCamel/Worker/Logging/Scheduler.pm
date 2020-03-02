package PageCamel::Worker::Logging::Scheduler;
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

use base qw(PageCamel::Worker::BaseModule);

use PageCamel::Helpers::Strings qw(stripString);
use PageCamel::Helpers::DateStrings;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my %loggers;
    $self->{loggers} = \%loggers;
    $self->{lastrun} = '';

    return $self;
}

sub register {
    my $self = shift;

    $self->register_worker("work");
    return;
}

sub add_plugin {
    my ($self, $device, $subdevice, $module, $func) = @_;

    if(defined($self->{loggers}->{$device}->{$subdevice})) {
        croak("Logging plugin for $device / $subdevice already registered!");
    }
    $self->{loggers}->{$device}->{$subdevice}->{module} = $module;
    $self->{loggers}->{$device}->{$subdevice}->{func} = $func;

    return;
}


sub work {
    my ($self) = @_;

    my $workCount = 0;

    my $scanspeeddate = getScanspeedDate($self->{scanspeed});
    if($scanspeeddate eq $self->{lastrun}) {
        return $workCount;
    }

    $self->{lastrun} = $scanspeeddate;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    # Refresh Lifetick every now and then
    $memh->refresh_lifetick;



    my @todo;
    my $selstmt = "SELECT * FROM logging_devices
                    WHERE is_active = true
                    AND scanspeed = '" . $self->{scanspeed} . "'
                    ORDER BY device_type, device_subtype, hostname";
    my $selsth = $dbh->prepare_cached($selstmt)
            or croak($dbh->errstr);
    $selsth->execute or croak($dbh->errstr);

    my $compstmt = "SELECT " . $self->{ipcolumn} . " AS computeripcolumn " .
                    "FROM computers WHERE computer_name = ? ";
    my $compsth = $dbh->prepare_cached($compstmt)
            or croak($dbh->errstr);

    $memh->refresh_lifetick;
    while((my $device = $selsth->fetchrow_hashref)) {
        if(defined($device->{computerdb_hostname}) && $device->{computerdb_hostname} ne '') {
            $compsth->execute($device->{computerdb_hostname}) or croak($dbh->errstr);
            my ($realip) = $compsth->fetchrow_array;
            $compsth->finish;
            if(defined($realip) && $realip ne '') {
                $device->{ip_addr} = $realip;
            }
        }
        push @todo, $device;
    }
    $selsth->finish;
    $dbh->commit;

    foreach my $device (@todo) {
        my $type = $device->{device_type};
        my $subtype = $device->{device_subtype};
        if(!defined($self->{loggers}->{$type}->{$subtype})) {
            $reph->debuglog("    No plugin to handle a device of type $type / $subtype");
            next;
        }
        my $plugin = $self->{loggers}->{$type}->{$subtype};
        my $module = $plugin->{module};
        my $funcname = $plugin->{func} ;
        my $status = $module->$funcname($device, $dbh, $reph, $memh);

        $dbh->rollback(); # Just in case a plugin forgot

        $workCount += $status;
        $memh->refresh_lifetick;
    }

    return $workCount;
}



1;
__END__

=head1 NAME

PageCamel::Worker::Logging::Scheduler - run logging plugins

=head1 SYNOPSIS

  use PageCamel::Worker::Logging::Scheduler;

=head1 DESCRIPTION

This module is the main logging module. It runs all the callbacks in the plugins.

=head2 new

Create a new instance

=head2 register

Register the work plugin.

=head2 add_plugin

Add a new plugin.

=head2 work

Run registered plugins/workloads.

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
