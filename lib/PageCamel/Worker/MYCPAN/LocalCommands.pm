package PageCamel::Worker::MYCPAN::LocalCommands;
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

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;
use CPAN::Mini::Inject;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my %commands;

    foreach my $cmd (qw[MYCPAN_UPDATE_FILES]) {
        my $cmdfunc = "do_" . lc($cmd);
        $commands{$cmd} = $cmdfunc;
    }
    $self->{extcommands} = \%commands;

    return $self;
}

sub crossregister {
    my $self = shift;

    # Register ourselfs in the RBSCommands module with additional commands
    my $comh = $self->{server}->{modules}->{$self->{commands}};

    foreach my $cmd (sort keys %{$self->{extcommands}}) {
        $comh->register_extcommand($cmd, $self);
    }
    return;
}

sub execute {
    my ($self, $command, $arguments) = @_;

    if(defined($self->{extcommands}->{$command})) {
        my $cmdfunc = $self->{extcommands}->{$command};
        return $self->$cmdfunc($arguments);
    }
    return;
}


sub do_mycpan_update_files {
    my ($self, $arguments) = @_;

    my $logtype = "OTHER"; # make logging visible only to admin user

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    $memh->disable_lifetick;
    my $mcpani = CPAN::Mini::Inject->new();
    $mcpani->parsecfg($self->{mcpani});
    $reph->debuglog("MYCPAN: Updating local mirror");
    $mcpani->update_mirror(force => 1);
    $reph->debuglog("MYCPAN: Injecting backpan files");
    $mcpani->inject;
    $memh->refresh_lifetick;

    $reph->debuglog("MYCPAN: Scheduling database update");
    my @dbargs = (
        $self->{dbmodule},
        $self->{localdir},
        0, # filedontchange flag off
        1, #lazyeval flag on
    );
    my $insth = $dbh->prepare("INSERT INTO commandqueue (command, arguments) VALUES ('DYNAMICEXTERNALFILES_UPDATE_DATABASE', ?)")
            or croak($dbh->errstr);
    if(!$insth->execute(\@dbargs)) {
        $dbh->rollback;
        $reph->debuglog("    FAILED!");
    } else {
        $dbh->commit;
    }

    return (1, $logtype);
}

1;
__END__

=head1 NAME

PageCamel::Worker::MYCPAN::LocalCommands - Update a local CPAN mirror

=head1 SYNOPSIS

  use PageCamel::Worker::MYCPAN::LocalCommands;

=head1 DESCRIPTION

Updates a local CPAN mirror, injects local distributions and updates the database. This is a commandqueue plugin.

=head2 new

Create a new instance.

=head2 crossregister

Register execute callback.

=head2 execute

Execute the correct command.

=head2 do_mycpan_update_files

Update the mirror.

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
