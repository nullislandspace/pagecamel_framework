package PageCamel::Protocol::QUIC::ConnectionIDManager;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 5.0;
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use Time::HiRes qw(time);


# Recommended number of connection IDs per connection
use constant DEFAULT_CID_COUNT => 8;

sub new($class, %config) {
    my $self = bless {
        # Configuration
        cidLength        => $config{cid_length} // 8,
        maxCidsPerConn   => $config{max_cids_per_conn} // DEFAULT_CID_COUNT,
        retirePriorTo    => 0,

        # Connection ID tracking
        localCids        => {},   # sequence_number -> {cid, stateless_reset_token, retired}
        remoteCids       => {},   # sequence_number -> {cid, stateless_reset_token}
        cidToConnection  => {},   # cid -> connection object (global lookup)

        # State
        nextLocalSeq     => 0,
        nextRemoteSeq    => 0,
        activeCidCount   => 0,

        # Associated connection
        connection       => $config{connection},
    }, $class;

    return $self;
}

sub generateConnectionIds($self, $count = undef) {
    $count //= $self->{maxCidsPerConn};
    my @newCids;

    for my $i (1 .. $count) {
        last if($self->{activeCidCount} >= $self->{maxCidsPerConn});

        my $cid = $self->_generateRandomCid();
        my $resetToken = $self->_generateStatelessResetToken();
        my $seq = $self->{nextLocalSeq}++;

        $self->{localCids}->{$seq} = {
            cid                  => $cid,
            statelessResetToken  => $resetToken,
            retired              => 0,
            createdAt            => time(),
        };

        $self->{activeCidCount}++;

        push @newCids, {
            sequenceNumber       => $seq,
            connectionId         => $cid,
            statelessResetToken  => $resetToken,
        };
    }

    return @newCids;
}

sub registerConnectionId($self, $cid, $connection) {
    $self->{cidToConnection}->{$cid} = $connection;
    return 1;
}

sub unregisterConnectionId($self, $cid) {
    delete $self->{cidToConnection}->{$cid};
    return 1;
}

sub lookupConnection($self, $cid) {
    return $self->{cidToConnection}->{$cid};
}

sub addRemoteConnectionId($self, $seq, $cid, $resetToken = undef) {
    $self->{remoteCids}->{$seq} = {
        cid                  => $cid,
        statelessResetToken  => $resetToken,
        addedAt              => time(),
    };

    if($seq >= $self->{nextRemoteSeq}) {
        $self->{nextRemoteSeq} = $seq + 1;
    }

    return 1;
}

sub retireConnectionId($self, $seq) {
    my $cidInfo = $self->{localCids}->{$seq};
    return unless(defined($cidInfo));

    if(!$cidInfo->{retired}) {
        $cidInfo->{retired} = 1;
        $cidInfo->{retiredAt} = time();
        $self->{activeCidCount}--;

        # Unregister from global lookup
        $self->unregisterConnectionId($cidInfo->{cid});
    }

    return 1;
}

sub retireRemoteConnectionId($self, $seq) {
    delete $self->{remoteCids}->{$seq};
    return 1;
}

sub retirePriorTo($self, $seq) {
    # Retire all CIDs with sequence number less than $seq
    for my $existingSeq (keys %{$self->{localCids}}) {
        if($existingSeq < $seq) {
            $self->retireConnectionId($existingSeq);
        }
    }

    $self->{retirePriorTo} = $seq;
    return 1;
}

sub getActiveConnectionIds($self) {
    my @active;

    for my $seq (sort { $a <=> $b } keys %{$self->{localCids}}) {
        my $cidInfo = $self->{localCids}->{$seq};
        next if($cidInfo->{retired});

        push @active, {
            sequenceNumber      => $seq,
            connectionId        => $cidInfo->{cid},
            statelessResetToken => $cidInfo->{statelessResetToken},
        };
    }

    return @active;
}

sub getPrimaryConnectionId($self) {
    # Return the lowest sequence number active CID
    for my $seq (sort { $a <=> $b } keys %{$self->{localCids}}) {
        my $cidInfo = $self->{localCids}->{$seq};
        next if($cidInfo->{retired});
        return $cidInfo->{cid};
    }

    return;
}

sub getRemoteConnectionId($self) {
    # Return the lowest sequence number remote CID
    for my $seq (sort { $a <=> $b } keys %{$self->{remoteCids}}) {
        return $self->{remoteCids}->{$seq}->{cid};
    }

    return;
}

sub isValidStatelessReset($self, $token) {
    # Check if the token matches any of our remote CIDs
    for my $seq (keys %{$self->{remoteCids}}) {
        my $cidInfo = $self->{remoteCids}->{$seq};
        if(defined($cidInfo->{statelessResetToken}) &&
           $cidInfo->{statelessResetToken} eq $token) {
            return 1;
        }
    }

    return 0;
}

sub needsMoreConnectionIds($self) {
    return $self->{activeCidCount} < ($self->{maxCidsPerConn} / 2);
}

sub _generateRandomCid($self) {
    my $cid = '';
    for my $i (1 .. $self->{cidLength}) {
        $cid .= chr(int(rand(256)));
    }
    return $cid;
}

sub _generateStatelessResetToken($self) {
    # 128-bit (16-byte) stateless reset token
    my $token = '';
    for my $i (1 .. 16) {
        $token .= chr(int(rand(256)));
    }
    return $token;
}

sub stats($self) {
    return {
        activeCidCount   => $self->{activeCidCount},
        totalLocalCids   => scalar(keys %{$self->{localCids}}),
        totalRemoteCids  => scalar(keys %{$self->{remoteCids}}),
        nextLocalSeq     => $self->{nextLocalSeq},
        nextRemoteSeq    => $self->{nextRemoteSeq},
        retirePriorTo    => $self->{retirePriorTo},
    };
}

1;

__END__

=head1 NAME

PageCamel::Protocol::QUIC::ConnectionIDManager - QUIC connection ID management

=head1 SYNOPSIS

    use PageCamel::Protocol::QUIC::ConnectionIDManager;

    my $cidMgr = PageCamel::Protocol::QUIC::ConnectionIDManager->new(
        cid_length       => 8,
        max_cids_per_conn => 8,
    );

    # Generate new connection IDs
    my @newCids = $cidMgr->generateConnectionIds(4);

    # Register for lookup
    $cidMgr->registerConnectionId($cid, $connection);

    # Lookup connection by CID
    my $conn = $cidMgr->lookupConnection($cid);

    # Retire a connection ID
    $cidMgr->retireConnectionId($sequenceNumber);

=head1 DESCRIPTION

This module manages QUIC connection IDs for connection migration support.
QUIC connections can have multiple connection IDs, allowing the connection
to survive changes in the client's network address (NAT rebinding, mobile
network handoff, etc.).

=head1 CONNECTION MIGRATION

Connection migration allows a QUIC connection to continue even when the
client's IP address or port changes. This is accomplished by:

=over 4

=item * Maintaining multiple connection IDs per connection

=item * Allowing packets from different source addresses to be routed
to the same connection if they use a valid connection ID

=item * Path validation before fully migrating to a new path

=back

=head1 METHODS

=head2 new(%config)

Create a new connection ID manager.

Options:

=over 4

=item cid_length - Length of connection IDs in bytes (default: 8)

=item max_cids_per_conn - Maximum CIDs per connection (default: 8)

=item connection - Associated connection object

=back

=head2 generateConnectionIds($count)

Generate new connection IDs with stateless reset tokens.

=head2 registerConnectionId($cid, $connection)

Register a connection ID for global lookup.

=head2 lookupConnection($cid)

Find a connection by connection ID.

=head2 retireConnectionId($seq)

Retire a local connection ID by sequence number.

=head2 retirePriorTo($seq)

Retire all connection IDs with sequence < $seq.

=head2 getActiveConnectionIds()

Get all active (non-retired) connection IDs.

=head2 getPrimaryConnectionId()

Get the primary (lowest sequence) connection ID.

=head1 SEE ALSO

L<PageCamel::Protocol::QUIC::PathValidator>,
L<PageCamel::Protocol::QUIC::Connection>,
RFC 9000 Section 9

=cut
