package PageCamel::Worker::MYCPAN::AutoScheduler;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.0;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
use feature 'signatures';
no warnings qw(experimental::signatures);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::DBSerialize;
use PageCamel::Helpers::Padding qw(doFPad);

use Readonly;

Readonly my $DAYMEMKEY => "MYCPAN::AutoScheduler::lastDay";
Readonly my $HOURMEMKEY => "MYCPAN::AutoScheduler::lastHour";


sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    if(!defined($self->{startminute})) {
        $self->{startminute} = '0';
    }
    $self->{startminute} = doFPad($self->{startminute}, 2);

    return $self;
}

sub reload {
    my ($self) = shift;
    # Nothing to do.. in here, we are pretty much self contained
    return;
}

sub register {
    my $self = shift;
    $self->register_worker("work_hour");
    #$self->register_worker("work_day");
    return;
}


sub work_hour {
    my ($self) = @_;

    my $workCount = 0;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $now = getCurrentHour();
    my ($startdate, $starttime) = getDateAndTime;
    $starttime =~ s/\:.*//g;
    $startdate .= ' ' . $starttime . ':' . $self->{startminute};
    my $lastRun = $memh->get($HOURMEMKEY);
    if(!defined($lastRun)) {
        $lastRun = "";
    } else {
        $lastRun = dbderef($lastRun);
    }


    if($lastRun eq $now) {
        return $workCount;
    }

    $memh->set($HOURMEMKEY, $now);

    my $insth = $dbh->prepare("INSERT INTO commandqueue (command, starttime) VALUES ('MYCPAN_UPDATE_FILES', ?)")
            or croak($dbh->errstr);

    if(!$insth->execute($startdate)) {
       $reph->debuglog("Failed to schedule MYCPAN_UPDATE_FILES");
       $dbh->rollback;
   } else {
       $reph->debuglog("Scheduled MYCPAN_UPDATE_FILES");
       $workCount++;
       $dbh->commit;
   }


    return $workCount;
}

sub work_day {
    my ($self) = @_;

    my $workCount = 0;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $now = getCurrentDay();
    my $lastRun = $memh->get($DAYMEMKEY);
    if(!defined($lastRun)) {
        $lastRun = "";
    } else {
        $lastRun = dbderef($lastRun);
    }


    if($lastRun eq $now) {
        return $workCount;
    }

    $memh->set($DAYMEMKEY, $now);


    return $workCount;
}

1;
__END__

=head1 NAME

PageCamel::Worker::MYCPAN::AutoScheduler - Schedule a CPAN mirror update

=head1 SYNOPSIS

  use PageCamel::Worker::MYCPAN::AutoScheduler;

=head1 DESCRIPTION

Schedule a CPAN mirror update.

=head2 new

Create a new instance.

=head2 reload

Currently does nothing.

=head2 register

Register the callbacks

=head2 work_hour

Schedule a CPAN mirror update every hour.

=head2 work_day

Currently does nothing.

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
