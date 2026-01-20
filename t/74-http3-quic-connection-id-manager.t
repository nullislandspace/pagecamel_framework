#!/usr/bin/env perl
use v5.38;
use strict;
use warnings;
use Test::More;

plan skip_all => 'Author tests. Set TEST_HTTP3=1 to run.' unless $ENV{TEST_HTTP3};

# Test QUIC Connection ID Manager

use_ok('PageCamel::Protocol::QUIC::ConnectionIDManager');

# Test basic creation
{
    my $mgr = PageCamel::Protocol::QUIC::ConnectionIDManager->new();
    ok($mgr, 'Created connection ID manager');

    my $stats = $mgr->stats();
    is($stats->{activeCidCount}, 0, 'Initial active CID count is 0');
    is($stats->{totalLocalCids}, 0, 'Initial total local CIDs is 0');
}

# Test connection ID generation
{
    my $mgr = PageCamel::Protocol::QUIC::ConnectionIDManager->new(
        cid_length => 8,
    );

    my @cids = $mgr->generateConnectionIds(1);
    ok(scalar(@cids) == 1, 'Generated 1 connection ID');
    ok($cids[0]->{connectionId}, 'Has connectionId field');
    is(length($cids[0]->{connectionId}), 8, 'Connection ID is 8 bytes');
    ok(defined($cids[0]->{sequenceNumber}), 'Has sequence number');
    ok(defined($cids[0]->{statelessResetToken}), 'Has stateless reset token');
}

# Test registering a connection
{
    my $mgr = PageCamel::Protocol::QUIC::ConnectionIDManager->new();
    my $mockConn = { id => 'test-connection' };

    my @cids = $mgr->generateConnectionIds(1);
    my $cid = $cids[0]->{connectionId};
    my $result = $mgr->registerConnectionId($cid, $mockConn);
    ok($result, 'Registered connection');

    my $stats = $mgr->stats();
    is($stats->{activeCidCount}, 1, 'Active CID count is 1');
}

# Test looking up a connection
{
    my $mgr = PageCamel::Protocol::QUIC::ConnectionIDManager->new();
    my $mockConn = { id => 'test-conn-1' };

    my @cids = $mgr->generateConnectionIds(1);
    my $cid = $cids[0]->{connectionId};
    $mgr->registerConnectionId($cid, $mockConn);

    my $found = $mgr->lookupConnection($cid);
    ok($found, 'Found connection by CID');
    is($found->{id}, 'test-conn-1', 'Correct connection returned');

    my $notFound = $mgr->lookupConnection('nonexistent');
    ok(!$notFound, 'Unknown CID returns undef');
}

# Test multiple connection IDs generation
{
    my $mgr = PageCamel::Protocol::QUIC::ConnectionIDManager->new(
        max_cids_per_conn => 8,
    );

    my @cids = $mgr->generateConnectionIds(4);
    is(scalar(@cids), 4, 'Generated 4 connection IDs');

    # Each should have unique sequence number
    my %seenSeq;
    for my $cidInfo (@cids) {
        ok(!$seenSeq{$cidInfo->{sequenceNumber}}, 'Unique sequence number');
        $seenSeq{$cidInfo->{sequenceNumber}} = 1;
    }
}

# Test retiring a connection ID
{
    my $mgr = PageCamel::Protocol::QUIC::ConnectionIDManager->new();
    my $mockConn = { id => 'retire-test' };

    my @cids = $mgr->generateConnectionIds(2);
    my $cid1 = $cids[0]->{connectionId};
    my $seq1 = $cids[0]->{sequenceNumber};
    my $cid2 = $cids[1]->{connectionId};

    $mgr->registerConnectionId($cid1, $mockConn);
    $mgr->registerConnectionId($cid2, $mockConn);

    # Retire first CID by sequence number
    $mgr->retireConnectionId($seq1);

    # First CID should no longer resolve
    my $conn1 = $mgr->lookupConnection($cid1);
    ok(!$conn1, 'Retired CID no longer resolves');

    # Second CID should still work
    my $conn2 = $mgr->lookupConnection($cid2);
    ok($conn2, 'Non-retired CID still works');
}

# Test getActiveConnectionIds
{
    my $mgr = PageCamel::Protocol::QUIC::ConnectionIDManager->new();

    my @cids = $mgr->generateConnectionIds(3);
    my @active = $mgr->getActiveConnectionIds();
    is(scalar(@active), 3, 'Has 3 active connection IDs');
}

# Test getPrimaryConnectionId
{
    my $mgr = PageCamel::Protocol::QUIC::ConnectionIDManager->new();

    my @cids = $mgr->generateConnectionIds(3);
    my $primary = $mgr->getPrimaryConnectionId();
    ok($primary, 'Got primary connection ID');
    is($primary, $cids[0]->{connectionId}, 'Primary is lowest sequence number');
}

# Test CID uniqueness
{
    my $mgr = PageCamel::Protocol::QUIC::ConnectionIDManager->new();
    my %seen;
    my $collisions = 0;

    my @cids = $mgr->generateConnectionIds(8);
    for my $cidInfo (@cids) {
        if($seen{$cidInfo->{connectionId}}) {
            $collisions++;
        }
        $seen{$cidInfo->{connectionId}} = 1;
    }

    is($collisions, 0, 'No CID collisions in generation');
}

# Test stats
{
    my $mgr = PageCamel::Protocol::QUIC::ConnectionIDManager->new(
        max_cids_per_conn => 10,
    );

    my @cids = $mgr->generateConnectionIds(5);

    my $stats = $mgr->stats();
    is($stats->{activeCidCount}, 5, 'Correct active count');
    is($stats->{totalLocalCids}, 5, 'Correct total local CIDs');
    is($stats->{nextLocalSeq}, 5, 'Correct next sequence');
}

# Test remote connection ID management
{
    my $mgr = PageCamel::Protocol::QUIC::ConnectionIDManager->new();

    $mgr->addRemoteConnectionId(0, 'remote-cid-0', 'reset-token-0');
    $mgr->addRemoteConnectionId(1, 'remote-cid-1', 'reset-token-1');

    my $remoteCid = $mgr->getRemoteConnectionId();
    is($remoteCid, 'remote-cid-0', 'Got lowest sequence remote CID');

    my $stats = $mgr->stats();
    is($stats->{totalRemoteCids}, 2, 'Has 2 remote CIDs');
    is($stats->{nextRemoteSeq}, 2, 'Next remote sequence is 2');
}

# Test stateless reset validation
{
    my $mgr = PageCamel::Protocol::QUIC::ConnectionIDManager->new();

    $mgr->addRemoteConnectionId(0, 'remote-cid-0', 'valid-reset-token');

    ok($mgr->isValidStatelessReset('valid-reset-token'), 'Valid reset token accepted');
    ok(!$mgr->isValidStatelessReset('invalid-token'), 'Invalid reset token rejected');
}

# Test needsMoreConnectionIds
{
    my $mgr = PageCamel::Protocol::QUIC::ConnectionIDManager->new(
        max_cids_per_conn => 8,
    );

    ok($mgr->needsMoreConnectionIds(), 'Needs more CIDs initially');

    $mgr->generateConnectionIds(6);
    ok(!$mgr->needsMoreConnectionIds(), 'Does not need more CIDs with 6/8');
}

# Test retirePriorTo
{
    my $mgr = PageCamel::Protocol::QUIC::ConnectionIDManager->new();

    my @cids = $mgr->generateConnectionIds(5);
    my $stats = $mgr->stats();
    is($stats->{activeCidCount}, 5, 'Started with 5 active CIDs');

    # Retire all CIDs with sequence < 3
    $mgr->retirePriorTo(3);

    $stats = $mgr->stats();
    is($stats->{activeCidCount}, 2, 'Only 2 CIDs remain after retirePriorTo(3)');
}

done_testing();
