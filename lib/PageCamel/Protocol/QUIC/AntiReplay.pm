package PageCamel::Protocol::QUIC::AntiReplay;
use v5.38;
use strict;
use warnings;

use Time::HiRes qw(time);
use Digest::SHA qw(sha256);
use Carp qw(croak);

our $VERSION = '0.01';

# Bloom filter constants
use constant {
    BLOOM_SIZE       => 65536,    # 64KB bit array (512K bits)
    BLOOM_HASH_COUNT => 8,        # Number of hash functions
};

sub new($class, %config) {
    my $self = bless {
        # Configuration
        timeWindow       => $config{time_window} // 10,      # 10 second window
        maxClockSkew     => $config{max_clock_skew} // 5,    # 5 second allowed skew
        rotationInterval => $config{rotation_interval} // 5, # Rotate bloom filter every 5 seconds

        # Bloom filters (two for rotation)
        bloomFilters     => [
            $class->_createBloomFilter(),
            $class->_createBloomFilter(),
        ],
        currentFilter    => 0,
        lastRotation     => time(),

        # Exact match set for recent tickets (more precise than bloom filter)
        recentTickets    => {},
        recentTicketsExpiry => {},

        # Statistics
        totalChecks      => 0,
        replaysBlocked   => 0,
        falsePositives   => 0,
    }, $class;

    return $self;
}

sub _createBloomFilter($class) {
    # Create a bit vector using vec()
    my $filter = '';
    vec($filter, BLOOM_SIZE * 8 - 1, 1) = 0;  # Pre-allocate
    return \$filter;
}

sub _hashTicket($self, $ticketId, $timestamp, $index) {
    # Generate multiple hash positions for bloom filter
    my $data = $ticketId . pack('N', int($timestamp)) . pack('C', $index);
    my $hash = sha256($data);

    # Use different portions of the hash for each index
    my $pos = unpack('N', substr($hash, $index * 4, 4));
    return $pos % (BLOOM_SIZE * 8);
}

sub recordTicketUse($self, $ticketId, $timestamp = undef) {
    $timestamp //= time();

    # Rotate bloom filter if needed
    $self->_maybeRotate();

    # Add to bloom filter
    my $filter = $self->{bloomFilters}[$self->{currentFilter}];
    for my $i (0 .. BLOOM_HASH_COUNT - 1) {
        my $pos = $self->_hashTicket($ticketId, $timestamp, $i);
        vec(${$filter}, $pos, 1) = 1;
    }

    # Add to exact match set
    my $key = $self->_ticketKey($ticketId, $timestamp);
    $self->{recentTickets}->{$key} = 1;
    $self->{recentTicketsExpiry}->{$key} = time() + $self->{timeWindow} + $self->{maxClockSkew};

    return 1;
}

sub isReplay($self, $ticketId, $timestamp = undef) {
    $timestamp //= time();
    $self->{totalChecks}++;

    # Rotate bloom filter if needed
    $self->_maybeRotate();

    # Check time window
    my $now = time();
    my $minTime = $now - $self->{timeWindow} - $self->{maxClockSkew};
    my $maxTime = $now + $self->{maxClockSkew};

    if($timestamp < $minTime || $timestamp > $maxTime) {
        # Outside acceptable time window - always reject
        $self->{replaysBlocked}++;
        return 1;
    }

    # Check exact match first (most reliable)
    my $key = $self->_ticketKey($ticketId, $timestamp);
    if($self->{recentTickets}->{$key}) {
        $self->{replaysBlocked}++;
        return 1;
    }

    # Check bloom filters (both current and previous for window coverage)
    for my $filter (@{$self->{bloomFilters}}) {
        my $found = 1;
        for my $i (0 .. BLOOM_HASH_COUNT - 1) {
            my $pos = $self->_hashTicket($ticketId, $timestamp, $i);
            unless(vec(${$filter}, $pos, 1)) {
                $found = 0;
                last;
            }
        }
        if($found) {
            # Bloom filter says it might be a replay
            # Could be false positive, but we must be safe
            $self->{replaysBlocked}++;
            return 1;
        }
    }

    return 0;
}

sub _ticketKey($self, $ticketId, $timestamp) {
    # Create a key that includes the timestamp bucket
    my $bucket = int($timestamp);
    return $ticketId . ':' . $bucket;
}

sub _maybeRotate($self) {
    my $now = time();

    if($now - $self->{lastRotation} >= $self->{rotationInterval}) {
        # Rotate to next filter
        $self->{currentFilter} = 1 - $self->{currentFilter};

        # Clear the new current filter
        my $filter = $self->{bloomFilters}[$self->{currentFilter}];
        ${$filter} = '';
        vec(${$filter}, BLOOM_SIZE * 8 - 1, 1) = 0;

        $self->{lastRotation} = $now;

        # Cleanup expired exact matches
        $self->_cleanupExact();
    }

    return;
}

sub _cleanupExact($self) {
    my $now = time();
    my @expired;

    for my $key (keys %{$self->{recentTicketsExpiry}}) {
        if($self->{recentTicketsExpiry}->{$key} < $now) {
            push @expired, $key;
        }
    }

    for my $key (@expired) {
        delete $self->{recentTickets}->{$key};
        delete $self->{recentTicketsExpiry}->{$key};
    }

    return;
}

sub getAcceptableTimeWindow($self) {
    my $now = time();
    return {
        minTimestamp => $now - $self->{timeWindow} - $self->{maxClockSkew},
        maxTimestamp => $now + $self->{maxClockSkew},
    };
}

sub stats($self) {
    return {
        totalChecks      => $self->{totalChecks},
        replaysBlocked   => $self->{replaysBlocked},
        recentTicketCount => scalar(keys %{$self->{recentTickets}}),
        currentFilter    => $self->{currentFilter},
        lastRotation     => $self->{lastRotation},
    };
}

1;

__END__

=head1 NAME

PageCamel::Protocol::QUIC::AntiReplay - 0-RTT replay attack prevention

=head1 SYNOPSIS

    use PageCamel::Protocol::QUIC::AntiReplay;

    my $antiReplay = PageCamel::Protocol::QUIC::AntiReplay->new(
        time_window    => 10,    # 10 second window
        max_clock_skew => 5,     # 5 second clock skew allowance
    );

    # Check if this is a replay
    if($antiReplay->isReplay($ticketId, $timestamp)) {
        # Reject the 0-RTT data!
        die "Replay attack detected";
    }

    # Record the ticket use
    $antiReplay->recordTicketUse($ticketId, $timestamp);

=head1 DESCRIPTION

This module implements anti-replay protection for QUIC 0-RTT data.
0-RTT allows clients to send data immediately on connection resumption,
but this data can be captured and replayed by attackers. This module
tracks ticket usage to detect and block replay attempts.

The implementation uses a combination of:

=over 4

=item * Bloom filters - Space-efficient probabilistic detection

=item * Exact match set - Precise detection for recent tickets

=item * Time window validation - Reject packets outside acceptable window

=back

=head1 SECURITY

B<CRITICAL>: 0-RTT data is inherently replayable. Applications should:

=over 4

=item * Only accept idempotent operations in 0-RTT (GET requests, etc.)

=item * Never accept state-modifying operations in 0-RTT (POST, DELETE, etc.)

=item * Use this module to detect and reject replay attempts

=back

=head1 METHODS

=head2 new(%config)

Create a new anti-replay instance.

Options:

=over 4

=item time_window - Acceptable time window in seconds (default: 10)

=item max_clock_skew - Maximum allowed clock skew (default: 5)

=item rotation_interval - Bloom filter rotation interval (default: 5)

=back

=head2 isReplay($ticketId, $timestamp)

Check if this ticket/timestamp combination has been seen before.
Returns true if this appears to be a replay attack.

=head2 recordTicketUse($ticketId, $timestamp)

Record that a ticket was used at the given timestamp.

=head2 getAcceptableTimeWindow()

Returns a hash with minTimestamp and maxTimestamp for valid 0-RTT.

=head2 stats()

Get anti-replay statistics.

=head1 SEE ALSO

L<PageCamel::Protocol::QUIC::SessionTicketStore>,
RFC 8446 Section 8 (0-RTT and Anti-Replay)

=cut
