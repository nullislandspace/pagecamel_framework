package PageCamel::Worker::BackupCommand;
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
use Encode qw(is_utf8 encode_utf8 decode_utf8);
use Data::Dumper;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;
use XML::Simple;
use Sys::Hostname;


sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my %commands;

    foreach my $cmd (qw[BACKUP]) {
        my $cmdfunc = "do_" . lc($cmd);
        $commands{$cmd} = $cmdfunc;
    }
    $self->{extcommands} = \%commands;

    return $self;
}

sub reload {
    my ($self) = shift;
    # Nothing to do.. in here, we are pretty much self contained
    return;
}

sub register {
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

sub do_backup {
    my ($self, $arguments) = @_;
    my $done = 1;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $logtype = "OTHER"; # make logging visible only to admin user

    my $fname = $self->{basedir} . '/' . hostname() . '_' . $self->{database} . '_' . getFileDate() . '.backup';
    $reph->debuglog("Starting database backup to $fname");
    $reph->dblog("COMMAND", "Database backup to $fname");

    my $extraopts = "";
    if(defined($self->{host})) {
        $extraopts .= ' --host ' . $self->{host};
    }
    if(defined($self->{port})) {
        $extraopts .= ' --port ' . $self->{port};
    }

    my $fullcommand = $self->{pgdump} .
                " $extraopts " .
                ' --username ' . $self->{username} .
                ' --format custom ' .
                ' --blobs ' .
#                ' --oids ' .
#                ' --verbose ' .
                ' --file ' . $fname .
                ' ' . $self->{database};
    if(defined($self->{sudouser}) && $self->{sudouser} ne '') {
        $fullcommand = "sudo -u " . $self->{sudouser} . " $fullcommand";
    }
    $reph->debuglog("Backup command $fullcommand");
    $dbh->commit;

    # This may take quite long, so disable the lifetick
    $memh->disable_lifetick;

    # Backticks seem just right in this case, ignore perl::Critic
    my @lines = `$fullcommand`;

    # Reenable lifetick
    $memh->refresh_lifetick;

    foreach my $line (@lines) {
        if($line =~ /error/i) {
            $done = 0;
        }
        $reph->debuglog($line);
    }

    if(!$done) {
        $dbh->rollback;
        return (0, $logtype);
    }
    return (1, $logtype);
}


1;
__END__

=head1 NAME

PageCamel::Worker::BackupCommand - Run the postgresql backup command

=head1 SYNOPSIS

  use PageCamel::Worker::BackupCommand;

=head1 DESCRIPTION

Run the postgresql backup command (this is a CommandQueue.pm plugin)

=head2 new

New Instance

=head2 reload

Currently does nothing

=head2 register

Register the "execute" callback

=head2 execute

Run the correct sub-function

=head2 do_backup

Does a backup

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
