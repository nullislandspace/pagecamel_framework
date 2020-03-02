package PageCamel::Helpers::DataBlobs;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 2.5;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

use Digest::SHA1  qw(sha1_hex);

use Readonly;
Readonly::Scalar my $BLOBMODE => 0x00020000; ## no critic (ValuesAndExpressions::RequireNumberSeparators)


sub new {
    my ($class, $dbh, $datablobid, $metaonly) = @_;
    my $self = bless {}, $class;

    $self->{dbh} = $dbh;
    if(!defined($metaonly) && !defined($datablobid)) {
        # Allow "metadata only" only when an existing blob is opened
        $metaonly = 0;
    }
    $self->{metaonly} = $metaonly;

    if(defined($datablobid)) {
        $self->{datablob_id} = $datablobid;
    } else {
        my $blobid = $dbh->pg_lo_creat($BLOBMODE);
        if(!defined($blobid)) {
            croak($dbh->errstr);
        }
        $self->{blob_id} = $blobid;
        $self->{datalength} = 0;

        my $isth = $dbh->prepare_cached("INSERT INTO datablobs
                                       (blob_id, datalength)
                                       VALUES (?, ?)
                                       RETURNING datablob_id")
                or croak($dbh->errstr);
        $isth->execute($self->{blob_id}, $self->{datalength})
                or croak($dbh->errstr);
        $self->{datablob_id} = $isth->fetch()->[0];
        $isth->finish;
    }

    return $self;
}

sub blobOpen {
    my ($self) = @_;

    if(defined($self->{blobfd}) && !$self->blobClose()) {
        return 0;
    }

    my $selsth = $self->{dbh}->prepare("SELECT * FROM datablobs
                               WHERE datablob_id = ?")
                or croak($self->{dbh}->errstr);
    my $ok = 0;
    $selsth->execute($self->{datablob_id}) or croak($self->{dbh}->errstr);
    while((my $selline = $selsth->fetchrow_hashref)) {
        $ok = 1;
        foreach my $key (keys %{$selline}) {
            $self->{$key} = $selline->{$key};
        }
    }
    $selsth->finish;

    if(!$ok) {
        croak("Internal error - can't find blob");
    }

    if($self->{metaonly}) {
        # Simulate a file descriptor
        $self->{blobfd} = 1;
        return $self;
    }

    my $blobfd = $self->{dbh}->pg_lo_open($self->{blob_id}, $BLOBMODE);
    if(!defined($blobfd)) {
        croak("Internal error: Can't open BLOB file descriptor " . $self->{dbh}->errstr);
    }

    $self->{blobfd} = $blobfd;
    $self->{haswritten} = 0;
    $self->{mustupdateetag} = 0;

    return $self;
}

sub blobClose {
    my ($self) = @_;

    if($self->{metaonly}) {
        delete $self->{blobfd};
        return 1;
    }

    if(!defined($self->{blobfd})) {
        return 0;
    }

    if($self->{haswritten}) {
        $self->blobUpdateETag();
        my $upsth = $self->{dbh}->prepare_cached("UPDATE datablobs
                                                SET lastupdate = now(),
                                                datalength = ?,
                                                etag = ?
                                                WHERE datablob_id = ?")
                or croak($self->{dbh}->errstr);
        $upsth->execute($self->{datalength}, $self->{etag}, $self->{datablob_id})
                or croak($self->{dbh}->errstr);
    }

    $self->{dbh}->pg_lo_close($self->{blobfd});
    delete $self->{blobfd};

    return 1;

}

sub DESTROY {
    my ($self) = @_;

    $self->blobClose();
    return;
}

sub blobID {
    my ($self) = @_;

    return $self->{datablob_id};
}

sub blobWrite {
    my ($self, $data, $offset) = @_;

    if($self->{metaonly}) {
        croak("Can't write to metaonly blob fh!")
    }

    if(!defined($self->{blobfd})) {
        $self->blobOpen();
    }

    if(!defined($data)) {
        croak("Require data buffer argument!");
    }

    if(!ref($data)) {
        croak("Data buffer is not a reference!")
    }

    if(!defined($offset)) {
        $offset = 0;
    }

    if($offset > $self->{datalength}) {
        return 0;
    }

    my $realoffs = $self->{dbh}->pg_lo_lseek($self->{blobfd}, $offset, 0);
    if(!defined($offset) || $offset != $realoffs) {
        return 0;
    }

    my $len = length(${$data});
    my $writelen = $self->{dbh}->pg_lo_write($self->{blobfd}, ${$data}, $len);
    if(!defined($writelen) || $len != $writelen) {
        return 0;
    }

    my $newlength = $offset + $len;
    if($newlength > $self->{datalength}) {
        $self->{datalength} = $newlength;
    }

    $self->{haswritten} = 1;
    $self->{mustupdateetag} = 1;

    return 1;
}

sub blobRead {
    my ($self, $data, $offset, $len) = @_;

    if($self->{metaonly}) {
        croak("Can't read from metaonly blob fh!")
    }

    if(!defined($self->{blobfd})) {
        $self->blobOpen();
    }

    if(!defined($data)) {
        croak("Require data buffer argument!");
    }

    if(!ref($data)) {
        croak("Data buffer is not a reference!")
    }

    if(!defined($offset)) {
        $offset = 0;
    }

    if($offset > $self->{datalength}) {
        return 0;
    }

    if(!defined($len)) {
        $len = $self->{datalength} - $offset;
    }

    if(($offset + $len) > $self->{datalength}) {
        return 0;
    }

    my $realoffs = $self->{dbh}->pg_lo_lseek($self->{blobfd}, $offset, 0);
    if(!defined($offset) || $offset != $realoffs) {
        return 0;
    }

    my $readlen = $self->{dbh}->pg_lo_read($self->{blobfd}, $data, $len);
    if(!defined($readlen) || $len != $readlen) {
        return 0;
    }

    return 1;
}

sub blobDelete {
    my ($self) = @_;

    if(defined($self->{blobfd})) {
        $self->blobClose;
    }

    my $delsth =  $self->{dbh}->prepare_cached("DELETE FROM datablobs
                                                WHERE datablob_id = ?")
                or croak($self->{dbh}->errstr);
    $delsth->execute($self->{datablob_id}) or croak($self->{dbh}->errstr);

    return 1;
}

# Does not work at the moment.
#sub blobTruncate {
#    my ($self) = @_;
#
#    if($self->{metaonly}) {
#        croak("Can't truncate metaonly blob fh!")
#    }
#
#    if(!defined($self->{blobfd})) {
#        $self->blobOpen();
#    }
#
#    # Seek to the begining
#    my $realoffs = $self->{dbh}->pg_lo_lseek($self->{blobfd}, 0, 0);
#    if($realoffs) {
#        # Can't seek
#        return 0;
#    }
#    my $haserror = $self->{dbh}->pg_lo_truncate($self->{blobfd}, 0);
#    if($haserror) {
#        return 0;
#    }
#    $self->{datalength} = 0;
#    $self->{haswritten} = 1;
#    $self->{mustupdateetag} = 1;
#
#    return 1;
#}

sub blobUpdateETag {
    my ($self, $force) = @_;

    if($self->{metaonly}) {
        return;
    }

    if(!defined($force)) {
        $force = 0;
    }

    if(!defined($self->{blobfd})) {
        $self->blobOpen();
    }

    if(!$self->{mustupdateetag}) {
        # Already at latest version
        return 1;
    }

    if(!$self->{haswritten} && !$force) {
        # nothing changed
        return 1;
    }

    if($self->{datalength} == 0) {
        $self->{etag} = '00EMPTY00EMPTY00';
    } else {
        my $data;
        $self->blobRead(\$data);
        $self->{etag} = sha1_hex($data);
    }
    $self->{mustupdateetag} = 0;

    return 1;
}

sub getLastUpdate {
    my ($self) = @_;

    if(!defined($self->{blobfd})) {
        $self->blobOpen();
    }

    return $self->{lastupdate};
}

sub getETag {
    my ($self) = @_;

    if(!defined($self->{blobfd})) {
        $self->blobOpen();
    }

    $self->blobUpdateETag();

    return $self->{etag};
}

sub getLength {
    my ($self) = @_;

    if(!defined($self->{blobfd})) {
        $self->blobOpen();
    }

    return $self->{datalength};
}

1;
__END__

=head1 NAME

PageCamel::Helpers::DataBlobs - handle PostgreSQL data blobs

=head1 SYNOPSIS

  use PageCamel::Helpers::DataBlobs;

=head1 DESCRIPTION

PostgreSQL data blobs are a very useful feature, but a bit strange to handle. This module provides a saner, more PageCamel-like interface
to blobs, by handling the blobs itself as well as a normal table to store all the required metadata.

=head2 new

Create a new (or access an existing) data blob.

=head2 blobOpen

Open the postgresql blob.

=head2 blobClose

Close the postgresql blob.

=head2 DESTROY

Make sure we close the blob proberly on exit.

=head2 blobID

Get the blobs unique ID.

=head2 blobWrite

Write data to the blob.

=head2 blobRead

Read data from the blob.

=head2 blobDelete

Delete the blob.

=head2 blobTruncate

Truncate the data blob. This is currently disabled due to problems with DBD::Pg

=head2 blobUpdateETag

Internal function to update the calculated ETag

=head2 getLastUpdate

Returns the timestamp of the last update.

=head2 getETag

Returns the ETag.

=head2 getLength

Returns the length (size) of the data blob.

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

Copyright (C) 2008-2019 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
