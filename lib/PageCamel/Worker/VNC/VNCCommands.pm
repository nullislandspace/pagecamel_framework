package PageCamel::Worker::VNC::VNCCommands;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.4;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;
use Net::VNC;

use Readonly;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my %commands;

    foreach my $cmd (qw[VNC_UPDATE_RESOLUTION]) {
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

sub do_vnc_update_resolution {
    my ($self, $arguments) = @_;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $logtype = "OTHER"; # make logging visible only to admin user

    my $selsth = $dbh->prepare_cached("SELECT * FROM computers
                                        WHERE computer_name = ?
                                        LIMIT 1")
        or croak($dbh->errstr);
    my $computername = $arguments->[0];
    if(!$selsth->execute($computername)) {
        $dbh->rollback;
        return(0, $logtype);
    }

    my $computer = $selsth->fetchrow_hashref;
    $selsth->finish;

    if(!defined($computer)) {
        $reph->debuglog("Computer $computername not found in database");
        return(0, $logtype);
    }

    my ($width, $height);
    my $ok = eval {
        local $SIG{ALRM} = sub { croak "alarm\n" };
        alarm($self->{timeout});
        my $vnc = Net::VNC->new({hostname => $computer->{net_prod_ip}, password => $computer->{vnc_password}});
        $vnc->depth(24);
        $vnc->login;
        $width = $vnc->width || 0;
        $height = $vnc->height || 0;
        alarm(0);
        1;
    } || 0;

    if(!$ok) {
        $dbh->rollback;
        $reph->debuglog("Can't get VNC screen size from $computername");
        return(0, $logtype);
    }

    if($width < 640 || $width > 4000) {
        $dbh->debuglog("Doubtfull reported screen width $width for $computername");
        #return(0, $logtype);
    }

    if($height < 480 || $height > 3000) {
        $dbh->debuglog("Doubtfull reported screen height $height for $computername");
        #return(0, $logtype);
    }

    if($width == $computer->{vnc_width} && $height == $computer->{vnc_height}) {
        $reph->debuglog("VNC screen size for $computername unchanged");
        return(1, $logtype);
    }

    my $upsth = $dbh->prepare_cached("UPDATE computers
                                        SET vnc_width = ?,
                                        vnc_height = ?
                                        WHERE computer_name = ?")
        or croak($dbh->errstr);

    if(!$upsth->execute($width, $height, $computername)) {
        $reph->debuglog("Failed to update $computername in database");
        $dbh->rollback;
        return(0, $logtype);
    }

    $reph->debuglog("VNC screensize for $computername changed from " . $computer->{vnc_width} . " x " . $computer->{vnc_height} . " to $width x $height");

    $dbh->commit;
    return (1, $logtype);
}

1;
__END__

=head1 NAME

PageCamel::Worker::VNC::VNCCommands - run commands related to VNC remote access

=head1 SYNOPSIS

  use PageCamel::Worker::VNC::VNCCommands;

=head1 DESCRIPTION

This implements various command related to the PageCamel noVNC webinterface. This is a commandqueue plugin

=head2 new

Create a new instance

=head2 reload

Currently does nothing.

=head2 register

Register the execute callback.

=head2 execute

Run the correct sub-function

=head2 do_vnc_update_resolution

Update the database with the target hosts screen resolution.

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
