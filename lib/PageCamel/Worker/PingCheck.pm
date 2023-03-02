package PageCamel::Worker::PingCheck;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.2;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;
use Net::Ping;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{lastRun} = '';

    return $self;
}


sub register($self) {
    $self->register_worker("work");
    return;
}


sub work($self) {

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $workCount = 0;

    my $now = getCurrentMinute();
    if($now eq $self->{lastRun}) {
        return $workCount;
    }
    $self->{lastRun} = $now;

    my $selsth = $dbh->prepare("SELECT * FROM pagecamel.pingcheck_devices ORDER BY device_name")
            or croak($dbh->errstr);

    my $logsth = $dbh->prepare("INSERT INTO pagecamel.pingcheck_log (device_name, is_reachable) VALUES (?, ?)")
            or croak($dbh->errstr);

    if(!$selsth->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return $workCount;
    }
    my @devices;
    while((my $line = $selsth->fetchrow_hashref)) {
        push @devices, $line;
    }
    $selsth->finish;
    $dbh->commit;

    my $pinger = Net::Ping->new();

    foreach my $device (@devices) {
        my $ok = 0;
        if($pinger->ping($device->{ip_address}, 5)) {
            $ok = 1;
            $reph->debuglog("Device ", $device->{device_name}, " at IP ", $device->{ip_address}, " is reachable.");
        } else {
            $reph->debuglog("Device ", $device->{device_name}, " at IP ", $device->{ip_address}, " is NOT reachable.");
        }

        if(!$logsth->execute($device->{device_name}, $ok)) {
            $reph->debuglog($dbh->errstr);
            $dbh->rollback;
        } else {
            $dbh->commit;
        }
        $workCount++;
    }

    return $workCount;
}


1;
__END__

=head1 NAME

PageCamel::Worker::TableStatistics -

=head1 SYNOPSIS

  use PageCamel::Worker::TableStatistics;



=head1 DESCRIPTION



=head2 new



=head2 register



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
