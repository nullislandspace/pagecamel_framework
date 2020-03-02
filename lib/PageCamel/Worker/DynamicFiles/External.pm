package PageCamel::Worker::DynamicFiles::External;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.0;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;
use CPAN::Mini::Inject;
use PageCamel::Helpers::FileSlurp qw[slurpBinFile];
use Digest::SHA1  qw(sha1_hex);
use PageCamel::Helpers::DataBlobs;
use File::stat;
use Time::localtime;

use Readonly;


Readonly my $UPDATESTEP => 3_000;


sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my %commands;

    foreach my $cmd (qw[DYNAMICEXTERNALFILES_UPDATE_DATABASE]) {
        my $cmdfunc = "do_" . lc($cmd);
        $commands{$cmd} = $cmdfunc;
    }
    $self->{extcommands} = \%commands;
    $self->{lastscandebug} = 0;

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


sub do_dynamicexternalfiles_update_database {
    my ($self, $arguments) = @_;

    my ($dbmodule, $localdir, $filesdontchange, $lazymetadata) = @{$arguments};

    if(!defined($filesdontchange)) {
        $filesdontchange = 0;
    }

    if(!defined($lazymetadata)) {
        $lazymetadata = 0;
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

    my $selsth = $dbh->prepare_cached("SELECT * FROM dynamicexternalfiles
                                      WHERE module = ?")
            or croak($dbh->errstr);
    my $delsth = $dbh->prepare_cached("DELETE FROM dynamicexternalfiles WHERE module = ? AND filename = ?")
            or croak($dbh->errstr);
    my $insth = $dbh->prepare_cached("INSERT INTO dynamicexternalfiles (module, filename, basepath, basefilename, realfilename, etag, datalength, lastmodified, is_lazymetadata)
                                        VALUES (?,?,?,?,?,?,?,?,?)")
            or croak($dbh->errstr);

    my $upsth = $dbh->prepare_cached("UPDATE dynamicexternalfiles SET etag = ?, datalength = ?, lastmodified = ?, is_lazymetadata = ?, realfilename = ?
                                        WHERE module = ? AND filename = ?")
            or croak($dbh->errstr);


    $reph->debuglog("DYNEXTFILES staring for module $dbmodule in dir $localdir");

    $reph->debuglog("DYNEXTFILES $dbmodule: Scanning database for filenames...");
    $memh->refresh_lifetick;
    my %blobs;
    $selsth->execute($dbmodule) or croak($dbh->errstr);
    while((my $blob = $selsth->fetchrow_hashref)) {
        $blobs{$blob->{filename}} = $blob;
    }
    $selsth->finish;

    $reph->debuglog("DYNEXTFILES $dbmodule: Scanning directory for filenames...");
    $reph->debuglog("DYNEXTFILES $dbmodule:     none");
    $memh->refresh_lifetick;
    my %files;
    my $findok = 0;
    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
        $self->{lastfinddebug} = 0;
        %files = $self->find_files($localdir, '/', $dbmodule, $filesdontchange, $lazymetadata);
        $findok = 1;
    };
    croak($EVAL_ERROR) if ($EVAL_ERROR);
    croak("failed to load list of files") unless($findok);
    $memh->refresh_lifetick;

    $reph->debuglog("DYNEXTFILES $dbmodule: Scanning for stale files...");
    $reph->debuglog("DYNEXTFILES $dbmodule:     none");
    $memh->refresh_lifetick;
    foreach my $fname (sort keys %blobs) {
        next if(defined($files{$fname}));
        if($workCount{deleted} % $UPDATESTEP == 0) {
            $reph->debuglog_overwrite("DYNEXTFILES $dbmodule: Deleting " . $workCount{deleted} . " $fname");
        }
        $delsth->execute($dbmodule, $fname)
                or croak($dbh->errstr);
        delete $blobs{$fname}; # remove them from memory
        $workCount{deleted}++;
        if($workCount{deleted} % $UPDATESTEP == 0) {
            $memh->refresh_lifetick;
            $dbh->commit;
        }
    }
    $memh->refresh_lifetick;
    $dbh->commit;

    $reph->debuglog("DYNEXTFILES $dbmodule: Scanning for new files...");
    $reph->debuglog("DYNEXTFILES $dbmodule:     none");
    $memh->refresh_lifetick;
    foreach my $fname (sort keys %files) {
        next if(defined($blobs{$fname}));
        if($workCount{imported} % $UPDATESTEP == 0) {
            $reph->debuglog_overwrite("DYNEXTFILES $dbmodule: Importing " . $workCount{imported} . " $fname");
        }

        $insth->execute($dbmodule, $fname, $files{$fname}->{virtdir}, $files{$fname}->{basename}, $files{$fname}->{fullname},
                        $files{$fname}->{etag}, $files{$fname}->{size}, $files{$fname}->{lastmodified}, $lazymetadata)
                or croak($dbh->errstr);
        $memh->refresh_lifetick;

        delete $files{$fname}; # Don't need to work on that anymore, so forget it
        $workCount{imported}++;
        if($workCount{imported} % $UPDATESTEP == 0) {
            $memh->refresh_lifetick;
            $dbh->commit;
        }
    }
    $memh->refresh_lifetick;
    $dbh->commit;

    $reph->debuglog("DYNEXTFILES $dbmodule: Scanning for changed files...");
    $reph->debuglog("DYNEXTFILES $dbmodule:     none");
    $memh->refresh_lifetick;
    if($filesdontchange) {
        $reph->debuglog_overwrite("DYNEXTFILES $dbmodule:     option 'filesdontchange' is set, skipping");
    } else {
        foreach my $fname (sort keys %files) {
            if($fname eq '/1/0/0.png') {
                print "bla\n";
            }
            next if($blobs{$fname}->{etag} eq $files{$fname}->{etag} && $blobs{$fname}->{realfilename} eq $files{$fname}->{fullname});
            if($workCount{updated} % $UPDATESTEP == 0) {
                $reph->debuglog_overwrite("DYNEXTFILES $dbmodule: Updating " . $workCount{updated} . " $fname");
            }
            
            # UPDATE dynamicexternalfiles SET etag = ?, datalength = ?, lastmodified = ?, is_lazymetadata = ?, realfilename = ?
            #                            WHERE module = ? AND filename = ?")
            $upsth->execute($files{$fname}->{etag}, $files{$fname}->{size}, $files{$fname}->{lastmodified},
                            $lazymetadata, $files{$fname}->{fullname}, $dbmodule, $fname)
                    or croak($dbh->errstr);

            delete $files{$fname}; # Don't need to work on that anymore, so forget it
            $workCount{updated}++;
            if($workCount{updated} % $UPDATESTEP == 0) {
                $memh->refresh_lifetick;
                $dbh->commit;
            }
        }
        $memh->refresh_lifetick;
        $dbh->commit;
    }


    $reph->debuglog("DYNEXTFILES $dbmodule: Committing...");
    $dbh->commit;
    foreach my $key (sort keys %workCount) {
        $reph->debuglog("DYNEXTFILES $dbmodule: $key " . $workCount{$key} . " files");
    }
    $reph->debuglog("DYNEXTFILES $dbmodule: DONE");

    return (1, $logtype);
}

sub find_files {
    my ($self, $realdir, $virtdir, $dbmodule, $filesdontchange, $lazymetadata) = @_;

    my %dirs;
    my %files;

    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    $memh->refresh_lifetick;

    if(1 || $self->{lastscandebug} < time) {
        $reph->debuglog_overwrite("DYNEXTFILES $dbmodule:     Scanning $virtdir");
        $self->{lastscandebug} = time;
    }
    my $fcount = 0;
    opendir(my $dfh, $realdir) or croak($ERRNO);
    while((my $fname = readdir($dfh))) {
        next if($fname eq '.' || $fname eq '..');

        $fcount++;
        if($fcount % $UPDATESTEP == 0) {
            $memh->refresh_lifetick;
        }

        my $fullname = $realdir . '/' . $fname;
        my $virtname = $virtdir . $fname ;

        if(-d $fullname) {
            $dirs{$fullname} = $virtname . '/';
            next;
        }

        next unless (-f $fullname);

        my $fstat = stat($fullname);

        next unless defined($fstat);

        my %filestats = (
            basename    => $fname,
            size        => -s $fullname,
            virtdir     => $virtdir,
            fullname    => $fullname,
            lastmodified => ctime($fstat->mtime),
        );

        # Correct etag handling requires that size and/or lastmodified timestamp changes when a file changes
        # This significantly speeds up the scanning process and shouldn't be a problem on any sane filesystem
        $filestats{etag} = sha1_hex($fullname . $filestats{size} . $filestats{lastmodified});

        $files{$virtname} = \%filestats;
    }
    closedir($dfh);

    foreach my $fullname (sort keys %dirs) {
        my %newfiles = $self->find_files($fullname, $dirs{$fullname}, $dbmodule, $filesdontchange, $lazymetadata);

       @files{keys %newfiles} = values %newfiles;
    }

    return %files;
}
1;
__END__

=head1 NAME

PageCamel::Worker::DynamicExternalFiles -

=head1 SYNOPSIS

  use PageCamel::Worker::DynamicExternalFiles;



=head1 DESCRIPTION



=head2 new



=head2 crossregister



=head2 execute



=head2 do_dynamicexternalfiles_update_database



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
