#!/usr/bin/env perl
use v5.38;
use strict;
use warnings;
use Test::More;
use Time::HiRes qw(time);

# Test QUIC Anti-Replay protection

use_ok('PageCamel::Protocol::QUIC::AntiReplay');

# Test basic creation
{
    my $ar = PageCamel::Protocol::QUIC::AntiReplay->new();
    ok($ar, 'Created anti-replay instance');

    my $stats = $ar->stats();
    is($stats->{totalChecks}, 0, 'Initial total checks is 0');
    is($stats->{replaysBlocked}, 0, 'Initial replays blocked is 0');
}

# Test recording and detecting replay
{
    my $ar = PageCamel::Protocol::QUIC::AntiReplay->new();
    my $ticketId = 'ticket123';
    my $timestamp = time();

    # First use should not be a replay
    ok(!$ar->isReplay($ticketId, $timestamp), 'First use is not a replay');

    # Record the use
    $ar->recordTicketUse($ticketId, $timestamp);

    # Same ticket/timestamp should be detected as replay
    ok($ar->isReplay($ticketId, $timestamp), 'Same ticket is detected as replay');
}

# Test time window
{
    my $ar = PageCamel::Protocol::QUIC::AntiReplay->new(
        time_window    => 10,
        max_clock_skew => 5,
    );

    my $now = time();

    # Within window
    ok(!$ar->isReplay('ticket1', $now), 'Current time is valid');

    # Outside window (too old)
    ok($ar->isReplay('ticket2', $now - 20), 'Old timestamp rejected');

    # Outside window (future)
    ok($ar->isReplay('ticket3', $now + 10), 'Future timestamp rejected');
}

# Test acceptable time window
{
    my $ar = PageCamel::Protocol::QUIC::AntiReplay->new(
        time_window    => 10,
        max_clock_skew => 5,
    );

    my $window = $ar->getAcceptableTimeWindow();
    my $now = time();

    ok($window->{minTimestamp} < $now, 'Min timestamp is in past');
    ok($window->{maxTimestamp} > $now, 'Max timestamp is in future');
    ok($window->{maxTimestamp} - $window->{minTimestamp} > 10, 'Window spans time_window + skew');
}

# Test different tickets at same time
{
    my $ar = PageCamel::Protocol::QUIC::AntiReplay->new();
    my $timestamp = time();

    $ar->recordTicketUse('ticket-a', $timestamp);

    ok(!$ar->isReplay('ticket-b', $timestamp), 'Different ticket at same time is OK');
    ok($ar->isReplay('ticket-a', $timestamp), 'Same ticket is replay');
}

# Test same ticket at different times
{
    my $ar = PageCamel::Protocol::QUIC::AntiReplay->new();
    my $now = time();

    $ar->recordTicketUse('ticket1', $now);

    # Same ticket but different second (bucket)
    ok(!$ar->isReplay('ticket1', $now + 1), 'Same ticket different second is OK (exact match)');
}

# Test stats tracking
{
    my $ar = PageCamel::Protocol::QUIC::AntiReplay->new();
    my $now = time();

    # Perform some checks
    $ar->isReplay('ticket1', $now);
    $ar->recordTicketUse('ticket1', $now);
    $ar->isReplay('ticket1', $now);  # This should be blocked

    my $stats = $ar->stats();
    is($stats->{totalChecks}, 2, 'Total checks counted');
    is($stats->{replaysBlocked}, 1, 'Replays blocked counted');
}

# Test bloom filter behavior (probabilistic)
{
    my $ar = PageCamel::Protocol::QUIC::AntiReplay->new();
    my $now = time();

    # Record many different tickets
    for my $i (1..100) {
        $ar->recordTicketUse("ticket-$i", $now);
    }

    # All recorded tickets should be detected
    my $detected = 0;
    for my $i (1..100) {
        $detected++ if $ar->isReplay("ticket-$i", $now);
    }

    is($detected, 100, 'All recorded tickets detected as replays');

    # New tickets should not be detected (except possible false positives)
    my $falsePositives = 0;
    for my $i (101..200) {
        $falsePositives++ if $ar->isReplay("new-ticket-$i", $now);
    }

    ok($falsePositives < 10, 'False positive rate is acceptable');
}

done_testing();
