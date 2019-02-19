package PageCamel::Worker::Logging::Plugins::SmartStatus;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.1;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::Logging::PluginBase);

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

    $self->register_plugin('work', 'SMARTSTATUS', 'SMARTSTATUS');
    return;
}

sub loadColumns {
    my ($self, $dbh) = @_;

    my %cols;
    my $selsth = $dbh->prepare("SELECT column_name, data_type FROM information_schema.columns
                                WHERE table_name = 'logging_log_smartstatus'")
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

    $reph->debuglog("Logging S.M.A.R.T. status for " . $device->{description});
    # Refresh Lifetick every now and then
    $memh->refresh_lifetick;

    my $cmd = $self->{smartctl} . ' ' . $device->{parameters};
    my @lines = `$cmd`;

    my (@dbkeys, @vals, @spacers);
    foreach my $line (@lines) {
        chomp $line;
        $line = stripString($line);
        next if($line !~ /^\d/);


        my (undef, $keyname, undef, undef, undef, undef, undef, undef, undef, $val) = split(/\ /, $line);
        $val = int($val);

        $keyname = lc($keyname);
        $keyname =~ s/\-/_/g;

        next if(!defined($self->{dbcols}->{$keyname}));
        push @dbkeys, $keyname;
        push @vals, $val;
        push @spacers, '?';

    }

    if(!@dbkeys) {
        $reph->debuglog("    Unknown smartstatus, aborting!");
        return $workCount;
    }
    my $insth = $dbh->prepare_cached("INSERT INTO logging_log_smartstatus (hostname, device_ok, device_type, " . join(',', @dbkeys) . ")
                                        VALUES(?, true, 'SMARTSTATUS', " . join(',', @spacers) . ")")
            or croak($dbh->errstr);
    if($insth->execute($device->{hostname}, @vals)) {
        $dbh->commit;
        $workCount++;
    } else {
        $dbh->rollback;
        $reph->debuglog("   Failed to update smartstatus");
    }

    $dbh->rollback;
    return $workCount;
}

1;
__END__

=head1 NAME

PageCamel::Worker::Logging::Plugins::SmartStatus - Log the SMART status of a harddisk

=head1 SYNOPSIS

  use PageCamel::Worker::Logging::Plugins::SmartStatus;

=head1 DESCRIPTION

Log various informations from the SMART status of harddisks. This work for directly connected
disks as well as for disks behind a RAID controller (if we can get to the smart data via
a command line tools for the RAID controller).

This is a logging plugin

=head2 new

Create a new instance.

=head2 crossregister

register the work callback

=head2 loadColumns

Load available database columns.

=head2 work

Log the data.

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
