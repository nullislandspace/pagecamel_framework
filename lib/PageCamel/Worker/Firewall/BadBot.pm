package PageCamel::Worker::Firewall::BadBot;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.6;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);


sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{nextrun} = 0;

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
    my $now = time;
    if($now > $self->{nextrun}) {
        $self->{nextrun} = time + 10;
    } else {
        return $workCount;
    }

    my $delblocksth = $dbh->prepare_cached("DELETE FROM accesslog_blocklist
                                           WHERE is_automatic = true
                                           AND is_badbot = true
                                           AND blocktime < now() - interval '" . $self->{blocktime} . "'
                                           RETURNING *")
            or croak($dbh->errstr);

    if($delblocksth->execute()) {
        while((my $line = $delblocksth->fetchrow_hashref)) {
            $reph->debuglog("Unblocking IP " . $line->{ip_address} . " (was badbot)")
        }
        $delblocksth->finish;
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

PageCamel::Worker::Firewall::BadBot - clear firewall entries for bad bots after a while

=head1 SYNOPSIS

  use PageCamel::Worker::Firewall::BadBot;



=head1 DESCRIPTION

Clear firewall entries for bad bots after a while.

=head2 new

Create new instance.

=head2 register

Register work callback

=head2 work

Do the clearing.

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
