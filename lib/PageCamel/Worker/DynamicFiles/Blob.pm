package PageCamel::Worker::DynamicFiles::Blob;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.8;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;
use CPAN::Mini::Inject;
use PageCamel::Helpers::FileSlurp qw[slurpBinFile];
use Digest::SHA1  qw(sha1_hex);
use PageCamel::Helpers::DataBlobs;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my %commands;

    foreach my $cmd (qw[DYNAMICFILES_UPDATE_DATABASE]) {
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


sub do_dynamicfiles_update_database {
    my ($self, $arguments) = @_;

    my ($dbmodule, $localdir, $filesdontchange) = @{$arguments};

    if(!defined($filesdontchange)) {
        $filesdontchange = 0;
    }

    my $logtype = "OTHER"; # make logging visible only to admin user

    my %workCount = (
        updated     => 0,
        deleted     => 0,
        imported    => 0,
    );

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $selsth = $dbh->prepare_cached("SELECT * FROM dynamicfiles, datablobs
                                      WHERE file_datablob_id = datablob_id
                                      AND module = ?")
            or croak($dbh->errstr);
    my $delsth = $dbh->prepare_cached("DELETE FROM dynamicfiles WHERE module = ? AND filename = ?")
            or croak($dbh->errstr);
    my $insth = $dbh->prepare_cached("INSERT INTO dynamicfiles (module, filename, basepath, basefilename, file_datablob_id)
                                        VALUES (?,?,?,?,?)")
            or croak($dbh->errstr);

    $reph->debuglog("DYNFILES staring for module $dbmodule in dir $localdir");

    $reph->debuglog("DYNFILES $dbmodule: Scanning database for filenames...");
    $memh->refresh_lifetick;
    my %blobs;
    $selsth->execute($dbmodule) or croak($dbh->errstr);
    while((my $blob = $selsth->fetchrow_hashref)) {
        $blobs{$blob->{filename}} = $blob;
    }
    $selsth->finish;

    $reph->debuglog("DYNFILES $dbmodule: Scanning directory for filenames...");
    $reph->debuglog("DYNFILES $dbmodule:     none");
    $memh->refresh_lifetick;
    my %files = $self->find_files($localdir, '/', $dbmodule, $filesdontchange);
    $memh->refresh_lifetick;

    $reph->debuglog("DYNFILES $dbmodule: Scanning for stale files...");
    $reph->debuglog("DYNFILES $dbmodule:     none");
    $memh->refresh_lifetick;
    foreach my $fname (sort keys %blobs) {
        next if(defined($files{$fname}));
        $reph->debuglog_overwrite("DYNFILES $dbmodule: Deleting $fname");
        $delsth->execute($dbmodule, $fname)
                or croak($dbh->errstr);
        delete $blobs{$fname}; # remove them from memory
        $workCount{deleted}++;
        $memh->refresh_lifetick;
        $dbh->commit;
    }

    $reph->debuglog("DYNFILES $dbmodule: Scanning for new files...");
    $reph->debuglog("DYNFILES $dbmodule:     none");
    $memh->refresh_lifetick;
    foreach my $fname (sort keys %files) {
        next if(defined($blobs{$fname}));
        $reph->debuglog_overwrite("DYNFILES $dbmodule: Importing $fname");

        my $blob = PageCamel::Helpers::DataBlobs->new($dbh);
        $blob->blobOpen();
        my $data = slurpBinFile($files{$fname}->{fullname});
        if(!$blob->blobWrite(\$data)) {
            $reph->debuglog("DYNFILES $dbmodule: Error importing $fname");
            $reph->debuglog("DYNFILES $dbmodule:     ignoring...");
            $dbh->rollback;
            next;
        }

        my $blobid = $blob->blobID();
        $blob->blobClose();

        $insth->execute($dbmodule, $fname, $files{$fname}->{virtdir}, $files{$fname}->{basename}, $blobid)
                or croak($dbh->errstr);
        $memh->refresh_lifetick;

        delete $files{$fname}; # Don't need to work on that anymore, so forget it
        $workCount{imported}++;
        $memh->refresh_lifetick;
        $dbh->commit;
    }

    $reph->debuglog("DYNFILES $dbmodule: Scanning for changed files...");
    $reph->debuglog("DYNFILES $dbmodule:     none");
    $memh->refresh_lifetick;
    if($filesdontchange) {
        $reph->debuglog_overwrite("DYNFILES $dbmodule:     option 'filesdontchange' is set, skipping");
    } else {
        foreach my $fname (sort keys %files) {
            next if($blobs{$fname}->{etag} eq $files{$fname}->{etag});
            $reph->debuglog_overwrite("DYNFILES $dbmodule: Updating $fname");

            # Truncating a blog with blobTruncate does not currently work (problem with DBD::Pg).
            # So, delete the blob and create a new one

            $delsth->execute($dbmodule, $fname)
                    or croak($dbh->errstr);

            my $blob = PageCamel::Helpers::DataBlobs->new($dbh);
            $blob->blobOpen();
            my $data = slurpBinFile($files{$fname}->{fullname});
            $blob->blobWrite(\$data);
            my $blobid = $blob->blobID();
            $blob->blobClose();

            $insth->execute($dbmodule, $fname, $files{$fname}->{virtdir}, $files{$fname}->{basename}, $blobid)
                    or croak($dbh->errstr);
            $memh->refresh_lifetick;

            delete $files{$fname}; # Don't need to work on that anymore, so forget it
            $workCount{updated}++;
            $dbh->commit;
        }
    }


    $reph->debuglog("DYNFILES $dbmodule: Committing...");
    $dbh->commit;
    foreach my $key (sort keys %workCount) {
        $reph->debuglog("DYNFILES $dbmodule: $key " . $workCount{$key} . " files");
    }
    $reph->debuglog("DYNFILES $dbmodule: DONE");

    return (1, $logtype);
}

sub find_files {
    my ($self, $realdir, $virtdir, $dbmodule, $filesdontchange) = @_;

    my %dirs;
    my %files;

    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    $memh->refresh_lifetick;

    $reph->debuglog_overwrite("DYNFILES $dbmodule:     Scanning $virtdir");
    opendir(my $dfh, $realdir) or croak($ERRNO);
    while((my $fname = readdir($dfh))) {
        next if($fname eq '.' || $fname eq '..');

        my $fullname = $realdir . '/' . $fname;
        my $virtname = $virtdir . $fname ;

        if(-d $fullname) {
            $dirs{$fullname} = $virtname . '/';
            next;
        }

        my %filestats = (
            basename    => $fname,
            size        => -s $fullname,
            virtdir     => $virtdir,
            fullname    => $fullname,
        );

        if(!$filesdontchange) {
            $filestats{etag} = sha1_hex(slurpBinFile($fullname));
        }

        $files{$virtname} = \%filestats;
        $memh->refresh_lifetick;
    }
    closedir($dfh);

    foreach my $fullname (sort keys %dirs) {
        my %newfiles = $self->find_files($fullname, $dirs{$fullname}, $dbmodule, $filesdontchange);

       @files{keys %newfiles} = values %newfiles;
    }

    return %files;
}


1;
__END__

=head1 NAME

PageCamel::Worker::DynamicFiles - Auto-import files into the database

=head1 SYNOPSIS

  use PageCamel::Worker::DynamicFiles;

=head1 DESCRIPTION

Auto-imports (insert, update, delete) files into the PageCamel database.

=head2 new

Create a new instance.

=head2 crossregister

Register the execute callback.

=head2 execute

Run the correct sub-function.

=head2 do_dynamicfiles_update_database

Update the files.

=head2 find_files

recursively iterate through a directory tree.

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
