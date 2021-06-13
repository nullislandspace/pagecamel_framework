package PageCamel::Helpers::FTPSync;
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


use Net::FTP;
my $MAXFILES = 500;

sub new {
    my ($class, $url, $localdir, $mode, $filetype, $reph, $isDebug) = @_;

    if($mode ne "copy" && $mode ne "move") {
        return;
    }
    if(!defined($filetype)) {
        $filetype = "";
    }

    my ($user, $pass, $server, $dir);
    if($url =~ /ftp\:\/\/(.*)\:(.*)\@([^\/]*)(.*)/o) {
        ($user, $pass, $server, $dir) = ($1, $2, $3, $4);
    } else {
        return;
    }

    my %config = (
        localdir=> $localdir,
        mode    => $mode,
        type    => $filetype,
        server  => $server,
        user    => $user,
        pass    => $pass,
        remotedir => $dir,
        errorcount => 0,
    );

    if(defined($reph) && defined($isDebug) && $isDebug)  {
        $config{reph} = $reph;
        $config{debug} = 1;
    } else {
        $config{debug} = 0;
    }

    my $self = bless \%config, $class;

    $self->connectRemote() or return;

    return $self;
}

sub connectRemote {
    my ($self) = @_;

    my $ftp = Net::FTP->new($self->{server}, Debug => 0, Timeout => 10, Passive => 1)
        or return;
        #or croak "Cannot connect to $server: $EVAL_ERROR";

    $ftp->login($self->{user}, $self->{pass})
        or return;
        #or croak "Cannot login ", $ftp->message;

    $ftp->cwd($self->{remotedir})
        or return;
        #or croak "Cannot change working directory ", $ftp->message;

    $ftp->ascii()
        or return;
        #or croak "Cannot change to ASCII ", $ftp->message;

    #$ftp->pasv()
    #    or return;

    $self->{ftp} = $ftp;

    return 1;
}

sub toLocal {
    my ($self) = @_;

    $self->{reph}->debuglog("  Reading remote dir...") if($self->{debug});

    my @files = $self->{ftp}->ls;
    my $type = $self->{type};

    if(!@files) {
        return 1;
    }

    # Wait one second to give remote a change to finish writing files
    $self->{reph}->debuglog("  Sync-Wait") if($self->{debug});
    sleep 1;

    my $fcount = 0;
    foreach my $fname (sort @files) {
        next if($fname eq "." || $fname eq "..");
        next if($type ne "" && $fname !~ /\.$type$/);

        # Limit number of files to transfer
        $fcount++;
        last if($fcount > $MAXFILES);

        $self->{reph}->debuglog("  Transfering $fname") if($self->{debug});
        my $locname = $self->{localdir} . "/" . $fname;
        while(1) {
            my $lfname = $self->{ftp}->get($fname, $locname);
            if(!defined($lfname)) {
                $self->{errorcount}++;
                if($self->{errorcount} > 20) {
                    $self->{reph}->debuglog("FTP Error, giving up...") if($self->{debug});
                    return 0;
                }
                $self->{reph}->debuglog("FTP Error, trying to reconnect...") if($self->{debug});
                if(!$self->connectRemote()) {
                    $self->{reph}->debuglog("Reconnect failed!") if($self->{debug});
                    return 0;
                }
            } else {
                last;
            }
        }
        if($self->{mode} eq "move") {
            $self->{ftp}->delete($fname);
        }
    }
    return 1;
}

sub toRemote {
    my ($self) = @_;

    my $globname = $self->{localdir} . "/*";
    if($self->{type} ne "") {
        $globname .= "." . $self->{type};
    }

    $self->{reph}->debuglog("  Reading local dir") if($self->{debug});
    my @files = glob($globname);

    my $fcount = 0;
    foreach my $fname (sort @files) {
        next if($fname eq "." || $fname eq "..");
        next if(!-f $fname);
        my $remotename = $fname;
        $remotename =~ s/^.*\///go;

        # Limit number of files to transfer
        $fcount++;
        last if($fcount > $MAXFILES);

        $self->{reph}->debuglog("  Transfering $remotename") if($self->{debug});

        while(1) {
            my $lfname = $self->{ftp}->put($fname, $remotename);
            if(!defined($lfname)) {
                $self->{errorcount}++;
                if($self->{errorcount} > 20) {
                    $self->{reph}->debuglog("FTP Error, giving up...") if($self->{debug});
                    return 0;
                }
                $self->{reph}->debuglog("FTP Error, trying to reconnect...") if($self->{debug});
                if(!$self->connectRemote()) {
                    $self->{reph}->debuglog("Reconnect failed!") if($self->{debug});
                    return 0;
                }
            } else {
                last;
            }
        }

        if($self->{mode} eq "move") {
            unlink $fname;
        }
    }
    return 1;
}

sub quit {
    my ($self) = @_;

    if($self->{ftp}) {
        $self->{ftp}->quit;
        delete $self->{ftp};
    }

    return;
}

#sub DESTROY {
#    my ($self) = @_;
#
#    # Try to run quit(), might error out though.
#    eval {
#        $self->quit;
#    };
#
#    return;
#}


1;
__END__

=head1 NAME

PageCamel::Helpers::FTPSync - sync a local directory with a FTP directory

=head1 SYNOPSIS

  use PageCamel::Helpers::FTPSync;

=head1 DESCRIPTION

This module sync a local directory with a directory on an FTP server. If mode "move" is given,
copied files are removed from the source at the end of the operation.

=head2 new

Create a new instance.

=head2 connectRemote

Internal function to connect to the FTP server.

=head2 toLocal

Copy/move files from remote to local.

=head2 toRemote

Copy/move files from local to remote.

=head2 quit

Disconnect from remote server.

=head2 DESTROY

Make sure we are (cleanly) disconnected when destrying this instance.

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
