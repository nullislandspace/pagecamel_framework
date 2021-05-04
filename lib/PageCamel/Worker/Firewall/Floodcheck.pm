package PageCamel::Worker::Firewall::Floodcheck;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);


sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{nextrun} = 0;

    return $self;
}


sub register {
    my $self = shift;
    $self->register_worker("work");
    return;
}


sub work {
    my ($self) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $workCount = 0;
    my $now = time;
    if($now > $self->{nextrun}) {
        $self->{nextrun} = time + 10;
    } else {
        return $workCount;
    }

    my $delblocksth = $dbh->prepare_cached("DELETE FROM accesslog_blocklist
                                           WHERE is_automatic = true
                                           AND is_badbot = false
                                           AND blocktime < now() - interval '" . $self->{blocktime} . "'
                                           RETURNING *")
            or croak($dbh->errstr);

    my $delfloodsth = $dbh->prepare_cached("DELETE FROM accesslog_floodcheck
                                           WHERE logtime < now() - interval '" . $self->{floodtime} . "'")
            or croak($dbh->errstr);

    my $blocksth = $dbh->prepare_cached("INSERT INTO accesslog_blocklist (ip_address, is_automatic, is_badbot) (
                                            SELECT ip_address, true, false FROM accesslog_floodcheck af
                                            WHERE NOT EXISTS (
                                                SELECT 1 FROM accesslog_blocklist bl
                                                WHERE bl.ip_address = af.ip_address
                                            )
                                            GROUP BY ip_address
                                            HAVING count(*) > " . $self->{floodcount} . "
                                         ) RETURNING *")
            or croak($dbh->errstr);

    if($delblocksth->execute()) {
        while((my $line = $delblocksth->fetchrow_hashref)) {
            $reph->debuglog("Unblocking IP " . $line->{ip_address} . " (was floodcheck)")
        }
        $delblocksth->finish;
        $dbh->commit;
        $workCount++;
    } else {
        $dbh->rollback;
        $reph->debuglog("delblock failed!");
        return $workCount;
    }

    if(!$delfloodsth->execute()) {
        $dbh->rollback;
        $reph->debuglog("delflood failed!");
        return $workCount;
    } else {
        $workCount++;
        $dbh->commit;
    }

    if($blocksth->execute()) {
        while((my $line = $blocksth->fetchrow_hashref)) {
            $reph->debuglog("Blocking IP " . $line->{ip_address} . " (floodcheck)")
        }
        $blocksth->finish;
        $dbh->commit;
        $workCount++;
    } else {
        $dbh->rollback;
    }

    $dbh->commit;

    return $workCount;
}


1;
__END__

=head1 NAME

PageCamel::Worker::Firewall::Floodcheck - Firewall module for flood checks

=head1 SYNOPSIS

  use PageCamel::Worker::Firewall::Floodcheck;



=head1 DESCRIPTION

Make sure clients don't flood us with requests.

=head2 new

Create a new instance.

=head2 register

Register work callback

=head2 work

Create and delete entries in the blocklist, clear stale floodcheck entries

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
