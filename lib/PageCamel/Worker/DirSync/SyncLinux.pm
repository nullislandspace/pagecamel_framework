package PageCamel::Worker::DirSync::SyncLinux;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::Padding qw[doFPad];

use File::stat;
use Date::Simple qw[date today];
use File::Copy;

use Readonly;


sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my %commands;

    my $cmdfunc = "do_dirsync";
    $commands{$self->{cmdname}} = $cmdfunc;

    $self->{extcommands} = \%commands;

    return $self;
}

sub reload($self) {
    # Nothing to do.. in here, we are pretty much self contained
    return;
}

sub register($self) {
    # Register ourselfs in the CommandQueue module with additional commands
    my $comh = $self->{server}->{modules}->{$self->{commands}};

    foreach my $cmd (sort keys %{$self->{extcommands}}) {
        $comh->register_extcommand($cmd, $self);
    }
    return;
}

sub execute($self, $command, $arguments) {
    if(defined($self->{extcommands}->{$command})) {
        my $cmdfunc = $self->{extcommands}->{$command};
        return $self->$cmdfunc($arguments);
    }
    return;
}

sub do_dirsync($self, $arguments) {
    my ($syncname, $source, $dest, $maxage) = @{$arguments};

    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $logtype = "OTHER"; # make logging visible only to admin user

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $upstatesth = $dbh->prepare("UPDATE dirsync
                                   SET last_sync = now(),
                                   last_state = ?,
                                   errortext = ?
                                   WHERE sync_name = ?")
            or croak($dbh->errstr);

    my $errortext = '';

    $reph->debuglog("Running dirsync for $syncname (max age $maxage)");

    if(!(-d $source)) {
        $errortext = "Source is not a valid directory";
        goto finished;
    }

    if(!(-d $dest)) {
        $errortext = "Destination is not a valid directory";
        goto finished;
    }

    $reph->debuglog("Reading file list from $source");

    opendir(my $sfh, $source) or croak("$ERRNO");
    my @files;
    while((my $tmpfile = readdir($sfh))) {
        next if $tmpfile =~ /^\./;

        my $srcname = $source . '/' . $tmpfile;
        my $dstname = $dest . '/' . $tmpfile;

        next if(!(-f $srcname));

        my $sstat = stat($srcname);

        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($sstat->mtime);
        $year += 1900;
        $mon += 1; $mon = doFPad($mon, 2);
        $mday = doFPad($mday, 2);
        my $date_string = "$year-$mon-$mday";
        my $age = today() - date($date_string);

        next if($maxage > 0 && $age > $maxage);

        if(!(-f $dstname)) {
            # Dest does not exist - copy
            push @files, $tmpfile;
            next;
        }

        my $dstat = stat($dstname);
        if($sstat->mtime > $dstat->mtime ||
                $sstat->size != $dstat->size) {
            # Existing files differ in size and or the modification time
            # of the source was updated (similar to how "make" works)
            push @files, $tmpfile;
            next;
        }
    }
    closedir($sfh);

    $memh->disable_lifetick;
    $reph->debuglog("Syncing filesfrom $source to $dest");
    foreach my $fname (sort @files) {
        $reph->debuglog("... $fname ...");
        my $srcname = $source . '/' . $fname;
        my $dstname = $dest . '/' . $fname;
        if(!copy($srcname, $dstname)) {
            $errortext = "Copy failed for $srcname to $dstname";
            last;
        }
    }

    if($errortext ne '') {
        goto finished;
    }

    if($maxage == 0) {
        $reph->debuglog("Skipped cleaning - maxage is zero at $dest");
    } else {
        $reph->debuglog("Cleaning up old files at $dest");
        opendir(my $dfh, $dest) or croak("$ERRNO");
        while((my $tmpfile = readdir($dfh))) {
            next if $tmpfile =~ /^\./;
            my $dstname = $dest . '/' . $tmpfile;

            next if(!(-f $dstname));

            my $dstat = stat($dstname);

            my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($dstat->mtime);
            $year += 1900;
            $mon += 1; $mon = doFPad($mon, 2);
            $mday = doFPad($mday, 2);
            my $date_string = "$year-$mon-$mday";
            my $age = today() - date($date_string);

            next if($age <= $maxage);
            $reph->debuglog("... $tmpfile ...");
            if(!unlink($dstname)) {
                $errortext = "Cant unlink $dstname";
                last;
            }
        }
        closedir($dfh);
    }

finished:

    my $inssth = $dbh->prepare("INSERT INTO pgbackup_log (backuptype, is_ok) VALUES ('DIRSYNC', ?)")
            or croak($dbh->errstr);
    my $ok = 1;
    if($errortext ne '') {
        $ok = 0;
    }

    if(!$inssth->execute($ok)) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
    } else {
        $dbh->commit;
    }

    $memh->refresh_lifetick;
    my $state = "OK";
    if($errortext ne '') {
        $state = "ERROR";
        $reph->debuglog($errortext);
        $reph->debuglog("DIRSYNC sync_name '" . $syncname . "' failed!");
    } else {
        $reph->debuglog("DIRSYNC sync_name '" . $syncname . "' done.");
    }

    if(!$upstatesth->execute($state, $errortext, $syncname)) {
        $dbh->rollback;
        $reph->debuglog("DIRSYNC sync_name '" . $syncname . "' status update failed!");
    } else {
        $dbh->commit;
    }

    if($errortext ne '') {
        return (0, $logtype);
    } else {
        return (1, $logtype);
    }
}

1;
__END__

=head1 NAME

PageCamel::Worker::DirSync::SyncLinux - syncronize directories

=head1 SYNOPSIS

  use PageCamel::Worker::DirSync::SyncLinux;

=head1 DESCRIPTION

One-way syncronization of directories (on Linux). This is a CommandQueue.pm plugin

=head2 new

New instance

=head2 reload

Currently does nothing

=head2 register

Register the execute callback

=head2 execute

Run the correct sub-function

=head2 do_dirsync

Sync a directory

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
