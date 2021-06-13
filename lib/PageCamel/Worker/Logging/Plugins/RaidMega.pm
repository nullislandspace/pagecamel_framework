package PageCamel::Worker::Logging::Plugins::RaidMega;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.6;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::Logging::PluginBase);

use PageCamel::Helpers::FileSlurp qw(slurpTextFile);

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub crossregister {
    my $self = shift;

    $self->register_plugin('work', 'RAIDSTATUS', 'MegaRaid');
    return;
}

sub work {
    my ($self, $device, $dbh, $reph, $memh) = @_;

    my $workCount = 0;

    $reph->debuglog("Logging MegaRaid status for " . $device->{hostname});
    # Refresh Lifetick every now and then
    $memh->refresh_lifetick;

    my $cmd = $self->{megacli} . ' -LDInfo -LAll -aAll';
    my @states = (0,0,0,0);
    my @lines = `$cmd`;

    my $thisarray = -1;
    foreach my $line (@lines) {
        chomp $line;
        if($thisarray == -1) {
            if($line =~ /^Virtual\ Drive\:\ (\d)/) {
                $thisarray = $1;
            }
            next;
        }
        if($line =~ /^State\ \ .*\:\ (.*)/) {
            my $tstate = $1;
            if($tstate =~ /Optimal/) {
                $states[$thisarray] = 1;
            } else {
                $states[$thisarray] = 0;
            }
            $thisarray = -1;
        }
    }

    my $insth = $dbh->prepare_cached("INSERT INTO logging_log_raidstatus (hostname, device_ok, device_type, u0_ok, u1_ok, u2_ok, u3_ok)
                                        VALUES(?, true, 'RAIDSTATUS', ?,?,?,?)")
            or croak($dbh->errstr);
    if($insth->execute($device->{hostname}, @states)) {
        $dbh->commit;
        $workCount++;
    } else {
        $dbh->rollback;
        $reph->debuglog("   Failed to update raidstatus");
    }

    $dbh->rollback;
    return $workCount;
}

1;
__END__

=head1 NAME

PageCamel::Worker::Logging::Plugins::RaidMega - Log data from MegaRaid controllers

=head1 SYNOPSIS

  use PageCamel::Worker::Logging::Plugins::RaidMega;

=head1 DESCRIPTION

Log data from MegaRaid controllers. This is a logging plugin.

=head2 new

Create a new instance.

=head2 crossregister

Register the work callback.

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

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
