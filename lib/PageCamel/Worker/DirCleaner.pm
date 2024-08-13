package PageCamel::Worker::DirCleaner;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.5;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::Padding qw(doFPad);
use XML::Simple;
use Date::Simple qw[date today];
use File::stat;

use Readonly;


Readonly my $YEARBASEOFFSET => 1900;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my %dirstatus;
    foreach my $dir (@{$self->{directory}}) {
        my %status = (
            maxage    => $dir->{maxage},
            status    => "UNKNOWN",
            dblog     => 0,
        );
        if(defined($dir->{dblog}) && $dir->{dblog}) {
            $status{dblog} = 1;
        }

        $dirstatus{$dir->{path}} = \%status;
    }
    $memh->set("dircleanstatus", \%dirstatus);
    $self->{dirstatus} = \%dirstatus;

    $self->{lastRun} = "";

    return $self;
}

sub register($self) {
    $self->register_worker("work");
    return;
}


sub work($self) {

    my $workCount = 0;

    my $now = getCurrentHour();
    if($self->{lastRun} eq $now) {
        return $workCount;
    }
    $self->{lastRun} = $now;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    foreach my $dir (sort keys %{$self->{dirstatus}}) {
        $workCount += $self->clean($dir);
    }

    $memh->set("dircleanstatus", \%{$self->{dirstatus}});

    return $workCount;
}

sub clean($self, $dir) {

    my @todelete;
    my $deletes = 0;
    my $ok = 1;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    $reph->debuglog("Scanning $dir for cleaning");

    my $dfh;
    if(!opendir($dfh, $dir)) {
        if($self->{dirstatus}->{$dir}->{status} !~ /^ERROR$/o) {
            $self->{dirstatus}->{$dir}->{status} = "ERROR";
            $reph->dblog("DIR_CLEANER", "Can't open '$dir'");
            $dbh->commit;
        }
        $reph->debuglog("Can't open $dir");
        $ok = 0;
        goto finish;

    }

    my $fcount = 0;
    my $maxage = $self->{dirstatus}->{$dir}->{maxage} * 3600 * 24; # Convert days to seconds
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
        if($fcount == $self->{limit}) {
            $reph->debuglog("Limiting cleaning of $dir to $fcount files");
            last;
        }
    }
    closedir($dfh);

    if($fcount) {
        $reph->debuglog("Cleaning $fcount file(s) in $dir");
        foreach my $fname (@todelete) {
            if(unlink $fname) {
                $deletes++;
            } else {
                $ok = 0;
                $reph->debuglog("Failed to delete $fname");
            }
        }
        $reph->debuglog("Deleted $deletes file(s).");
    }

finish:
    if($ok) {
        $self->{dirstatus}->{$dir}->{status} = "OK";
    } else {
        if($self->{dirstatus}->{$dir}->{status} !~ /^(?:WARNING|ERROR)$/o) {
            $self->{dirstatus}->{$dir}->{status} = "WARNING";
            $reph->dblog("DIR_CLEANER", "Failed to delete file(s) in '$dir'");
            $dbh->commit;
        }
    }

    if($self->{dirstatus}->{$dir}->{dblog}) {
        $reph->debuglog("Logging dirclean status to pgbackup_log");
        my $inssth = $dbh->prepare("INSERT INTO pgbackup_log(backuptype, is_ok) VALUES ('DIRCLEANER', ?)")
                or croak($dbh->errstr);
        if(!$inssth->execute($ok)) {
            $reph->debuglog($dbh->errstr);
            $dbh->rollback;
        } else {
            $dbh->commit;
        }
    }

    return $deletes;
}

1;
__END__

=head1 NAME

PageCamel::Worker::DirCleaner - clean stale files in directories

=head1 SYNOPSIS

  use PageCamel::Worker::DirCleaner;

=head1 DESCRIPTION

Clean stale files in directories

=head2 new

New Instance

=head2 register

Register the work callback

=head2 work

Call the clean() function for every directory

=head2 clean

Clean a directory

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
