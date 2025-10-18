package PageCamel::Worker::BackupCommand;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.7;
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
use Sys::Hostname;

use Date::Simple qw[date today];
use File::stat;
use File::Copy;


sub new($proto, %config) {
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

sub reload($self) {
    # Nothing to do.. in here, we are pretty much self contained
    return;
}

sub register($self) {
    # Register ourselfs in the pagecamel commands module with additional commands
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

sub do_backup($self, $arguments) {
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};


    my $logtype = "OTHER"; # make logging visible only to admin user

    if(!defined($arguments) || !defined($arguments->[0])) {
        croak("Incorrect call, missing arguments");
    }

    my $selsth = $dbh->prepare("SELECT * FROM backup_schedule WHERE backup_name = ?")
            or croak($dbh->errstr);
    if(!$selsth->execute($arguments->[0])) {
        croak($dbh->errstr);
    }

    my $backupdata = $selsth->fetchrow_hashref;
    $selsth->finish;

    if(!defined($backupdata) || !defined($backupdata->{backup_name})) {
        $reph->debuglog("Failed to retrieve config for backup schedule " . $arguments->[0]);
        $dbh->rollback;
        return (0, $logtype);
    }
    $dbh->commit;

    # Support dynamic config via baseconfig
    foreach my $field (qw[backup_directory external_backup_directory]) {
        my $val = $backupdata->{$field};

        foreach my $varname (keys %ENV) {
            next unless $varname =~ /^PC\_/;

            my $newval = $ENV{$varname};

            #print "$varname = $newval\n";
            $val =~ s/$varname/$newval/g;
        }


        $backupdata->{$field} = $val;
    }

    my $fname = $backupdata->{backup_directory} . '/' . hostname() . '_' . $self->{database} . '_' . getFileDate() . '.backup';
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
                ' --exclude-table=wikipedia.cavacopedia_articles ' .
                ' --file ' . $fname .
                ' ' . $self->{database};
    if(defined($self->{password}) && $self->{password} ne '') {
        $fullcommand = 'PGPASSWORD="' . $self->{password} . '" ' . $fullcommand;
    }

    if(defined($self->{sudouser}) && $self->{sudouser} ne '') {
        $fullcommand = "sudo -u " . $self->{sudouser} . " $fullcommand";
    }


    $reph->debuglog("Backup command $fullcommand");
    $dbh->commit;

    # This may take quite long, so disable the lifetick
    $memh->disable_lifetick;

    $fullcommand .= ' && echo PAGECAMEL_CALL_OK';
    my @lines = `$fullcommand`;

    my $ok = 0;

    foreach my $line (@lines) {
        if($line =~ /PAGECAMEL\_CALL\_OK/) {
            $ok = 1;
        }
    }

    if($ok) {
        $reph->debuglog("Backup OK");
    } else {
        $reph->debuglog("Backup FAILED");
    }

    my $inssth = $dbh->prepare("INSERT INTO pgbackup_log (backuptype, is_ok) VALUES ('BACKUP', ?)")
            or croak($dbh->errstr);

    if(!$inssth->execute($ok)) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
    } else {
        $dbh->commit;
    }

    # Reenable lifetick
    $memh->refresh_lifetick;

    if(!$self->_dircleaner($backupdata->{backup_directory}, $backupdata->{max_age_days})) {
        $ok = 0;
    }

    if($backupdata->{external_backup_directory} ne '') {
        if($ok) {
            if(!$self->_dircleaner($backupdata->{external_backup_directory}, $backupdata->{external_max_age_days})) {
                $ok = 0;
            }
        }

        if($ok) {
            if(!$self->_dirsync($backupdata->{backup_directory}, $backupdata->{external_backup_directory}, $backupdata->{external_max_age_days})) {
                $ok = 0;
            }
        }
    } else {
        if(!$self->_simulate_dirsync()) {
            $ok = 0;
        }
    }

    if(!$ok) {
        $dbh->rollback;
        return (0, $logtype);
    }
    return (1, $logtype);
}

sub _dircleaner($self, $dir, $maxagedays) {
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    $reph->debuglog("Scanning $dir for cleaning");

    my @todelete;
    my $deletes = 0;
    my $ok = 1;

    my $dfh;
    if(!opendir($dfh, $dir)) {
        $reph->dblog("DIR_CLEANER", "Can't open '$dir'");
        $dbh->commit;
        $reph->debuglog("Can't open $dir");
        $ok = 0;
        goto finishcleaning;

    }

    my $fcount = 0;
    my $maxage = $maxagedays * 3600 * 24; # Convert days to seconds
    my $now = time();
    while((my $fname = readdir($dfh))) {
        next if($fname eq "." || $fname eq "..");

        # FIXME FOR SUBDIRS! REMOVE ALL EMPTY DIRS
        # Add code to configure from which depth on
        # empty dirs can be deleted
        #if(-d "$dir/$fname") {
        #    $self->clean("$dir/$fname");
        #    next;
        #}
        next if(!-f "$dir/$fname");
        my $fileage = stat("$dir/$fname")->mtime;
        my $age = $now - $fileage;
        next if($age <= $maxage);
        push @todelete, "$dir/$fname";
        $fcount++;
    }
    closedir($dfh);

    if($fcount) {
        $reph->debuglog("Cleaning $fcount file(s) in $dir");
        foreach my $fname (@todelete) {
            if(unlink $fname) {
                $deletes++;
                $reph->debuglog("   ...deleted $fname");
            } else {
                $ok = 0;
                $reph->debuglog("Failed to delete $fname");
            }
        }
        $reph->debuglog("Deleted $deletes file(s).");
    }

finishcleaning:
    $reph->debuglog("Logging dirclean status to pgbackup_log");
    my $inssth = $dbh->prepare("INSERT INTO pgbackup_log(backuptype, is_ok) VALUES ('DIRCLEANER', ?)")
            or croak($dbh->errstr);
    if(!$inssth->execute($ok)) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
    } else {
        $dbh->commit;
    }

    return $ok;
}

sub _dirsync($self, $source, $dest, $maxage) {
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $ok = 1;

    $reph->debuglog("Running dirsync for $source -> $dest (max age $maxage)");

    if(!(-d $source)) {
        $reph->debuglog("Source is not a valid directory");
        $ok = 0;
        goto finished;
    }

    if(!(-d $dest)) {
        $reph->debuglog("Destination is not a valid directory");
        $ok = 0;
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

        # Already copied
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
            # or the source was updated (similar to how "make" works)
            push @files, $tmpfile;
            next;
        }
    }
    closedir($sfh);

    $memh->disable_lifetick;
    $reph->debuglog("Syncing filesfrom $source to $dest");
    foreach my $fname (sort @files) {
        my $srcname = $source . '/' . $fname;
        my $dstname = $dest . '/' . $fname;
        $reph->debuglog("   sync $srcname -> $dstname");
        if(!copy($srcname, $dstname)) {
            $reph->debuglog("Copy failed for $srcname to $dstname");
            $ok = 0;
        }
    }

finished:

    my $inssth = $dbh->prepare("INSERT INTO pgbackup_log (backuptype, is_ok) VALUES ('DIRSYNC', ?)")
            or croak($dbh->errstr);

    if(!$inssth->execute($ok)) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
    } else {
        $dbh->commit;
    }

    $memh->refresh_lifetick;

    return $ok;
}

sub _simulate_dirsync($self) {
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    $reph->debuglog("USB Backup dir not configured, marking dirsync as complete");

    my $inssth = $dbh->prepare("INSERT INTO pgbackup_log (backuptype, is_ok) VALUES ('DIRSYNC', ?)")
            or croak($dbh->errstr);

    if(!$inssth->execute(1)) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return 0;
    }

    $dbh->commit;
    return 1;

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
