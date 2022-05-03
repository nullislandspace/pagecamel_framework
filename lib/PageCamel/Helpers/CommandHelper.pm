package PageCamel::Helpers::CommandHelper;
#---AUTOPRAGMASTART---
use 5.032;
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

use PageCamel::Helpers::DateStrings;

use base qw(Exporter);
our @EXPORT = qw(getCommandQueue); ## no critic (Modules::ProhibitAutomaticExportation)


sub getCommandQueue {
    my ($dbh, $memh, $command) = @_;

    my @commands;

    my $where = "";
    if(defined($command) and $command ne "") {
        $where .= $command . " ";
    }
    if($where ne "") {
        $where = " WHERE $where ";
    }


    my $stmt = "SELECT id, queuetime AS time, command AS name, arguments, starttime, current_worker AS worker FROM commandqueue $where ORDER BY starttime, id, command, arguments[0]";

    my $sth = $dbh->prepare_cached($stmt) or croak($dbh->errstr);
    $sth->execute;
    while((my $line = $sth->fetchrow_hashref)) {

        if(defined($line->{arguments}->[0])) {
            $line->{args} = join("\n", @{$line->{arguments}});
        } else {
            $line->{args} = "";
        }

        if(defined($line->{worker})) {
            $line->{class} = "activecommand";
            $line->{worker} =~ s/\ Worker//go;
        } else {
            $line->{worker} = "";
        }

        push @commands, $line;
    }

    $sth->finish;
    $dbh->commit;
    return \@commands;
}

1;
__END__

=head1 NAME

PageCamel::Helpers::CommandHelper - internal helper for commandqueue

=head1 SYNOPSIS

  use PageCamel::Helpers::CommandHelper;

=head1 DESCRIPTION

This is an internal helper to read the the commandqueue for specific commands in the correct order

=head2 getCommandQueue

Get next items for a specific command.

=head1 IMPORTANT NOTE

This module is part of the PageCamel framework. Currently, only limited support
and documentation exists outside my DarkPAN repositories. This source is
currently only provided for your reference and usage in other projects (just
copy&paste what you need, see license terms below).

To see PageCamel in action and for news about the project,
visit my blog at L<https://cavac.at>.

=head1 AUTHOR

Rene Schickbauer, E<lt>cavac@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
