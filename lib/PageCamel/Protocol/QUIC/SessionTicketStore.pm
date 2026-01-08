package PageCamel::Protocol::QUIC::SessionTicketStore;
use v5.38;
use strict;
use warnings;

use Time::HiRes qw(time);
use Carp qw(croak);

our $VERSION = '0.01';

sub new($class, %config) {
    my $self = bless {
        # Configuration
        maxTickets       => $config{max_tickets} // 10000,
        ticketLifetime   => $config{ticket_lifetime} // 86400,  # 24 hours
        cleanupInterval  => $config{cleanup_interval} // 300,   # 5 minutes

        # Storage
        tickets          => {},  # ticket_id -> ticket_data
        ticketsByClient  => {},  # client_id -> [ticket_ids...]

        # State
        lastCleanup      => time(),
        ticketCount      => 0,
    }, $class;

    return $self;
}

sub storeTicket($self, $clientId, $ticketId, $ticketData, $transportParams = undef) {
    # Run cleanup if needed
    $self->cleanupExpired() if(time() - $self->{lastCleanup} > $self->{cleanupInterval});

    # Check capacity
    if($self->{ticketCount} >= $self->{maxTickets}) {
        $self->_evictOldest();
    }

    my $now = time();

    # Store ticket
    $self->{tickets}->{$ticketId} = {
        clientId         => $clientId,
        ticketData       => $ticketData,
        transportParams  => $transportParams,
        createdAt        => $now,
        expiresAt        => $now + $self->{ticketLifetime},
        used             => 0,
    };

    # Index by client
    $self->{ticketsByClient}->{$clientId} //= [];
    push @{$self->{ticketsByClient}->{$clientId}}, $ticketId;

    $self->{ticketCount}++;

    return 1;
}

sub retrieveTicket($self, $ticketId) {
    my $ticket = $self->{tickets}->{$ticketId};
    return unless(defined($ticket));

    # Check expiration
    if($ticket->{expiresAt} < time()) {
        $self->invalidateTicket($ticketId);
        return;
    }

    return $ticket;
}

sub retrieveTicketForClient($self, $clientId) {
    my $ticketIds = $self->{ticketsByClient}->{$clientId};
    return unless(defined($ticketIds) && @{$ticketIds});

    # Return the most recent valid ticket
    for my $ticketId (reverse @{$ticketIds}) {
        my $ticket = $self->retrieveTicket($ticketId);
        return $ticket if(defined($ticket) && !$ticket->{used});
    }

    return;
}

sub markTicketUsed($self, $ticketId) {
    my $ticket = $self->{tickets}->{$ticketId};
    return unless(defined($ticket));

    $ticket->{used} = 1;
    $ticket->{usedAt} = time();

    return 1;
}

sub invalidateTicket($self, $ticketId) {
    my $ticket = $self->{tickets}->{$ticketId};
    return unless(defined($ticket));

    # Remove from client index
    my $clientId = $ticket->{clientId};
    if(defined($self->{ticketsByClient}->{$clientId})) {
        $self->{ticketsByClient}->{$clientId} =
            [grep { $_ ne $ticketId } @{$self->{ticketsByClient}->{$clientId}}];

        # Clean up empty client entry
        if(!@{$self->{ticketsByClient}->{$clientId}}) {
            delete $self->{ticketsByClient}->{$clientId};
        }
    }

    # Remove ticket
    delete $self->{tickets}->{$ticketId};
    $self->{ticketCount}--;

    return 1;
}

sub invalidateClientTickets($self, $clientId) {
    my $ticketIds = $self->{ticketsByClient}->{$clientId};
    return unless(defined($ticketIds));

    for my $ticketId (@{$ticketIds}) {
        delete $self->{tickets}->{$ticketId};
        $self->{ticketCount}--;
    }

    delete $self->{ticketsByClient}->{$clientId};

    return 1;
}

sub cleanupExpired($self) {
    my $now = time();
    my @expiredIds;

    for my $ticketId (keys %{$self->{tickets}}) {
        my $ticket = $self->{tickets}->{$ticketId};
        if($ticket->{expiresAt} < $now) {
            push @expiredIds, $ticketId;
        }
    }

    for my $ticketId (@expiredIds) {
        $self->invalidateTicket($ticketId);
    }

    $self->{lastCleanup} = $now;

    return scalar(@expiredIds);
}

sub _evictOldest($self) {
    # Find and remove the oldest ticket
    my $oldestId;
    my $oldestTime = time();

    for my $ticketId (keys %{$self->{tickets}}) {
        my $ticket = $self->{tickets}->{$ticketId};
        if($ticket->{createdAt} < $oldestTime) {
            $oldestTime = $ticket->{createdAt};
            $oldestId = $ticketId;
        }
    }

    if(defined($oldestId)) {
        $self->invalidateTicket($oldestId);
    }

    return;
}

sub stats($self) {
    return {
        ticketCount      => $self->{ticketCount},
        maxTickets       => $self->{maxTickets},
        clientCount      => scalar(keys %{$self->{ticketsByClient}}),
        lastCleanup      => $self->{lastCleanup},
    };
}

1;

__END__

=head1 NAME

PageCamel::Protocol::QUIC::SessionTicketStore - TLS 1.3 session ticket storage for 0-RTT

=head1 SYNOPSIS

    use PageCamel::Protocol::QUIC::SessionTicketStore;

    my $store = PageCamel::Protocol::QUIC::SessionTicketStore->new(
        max_tickets     => 10000,
        ticket_lifetime => 86400,
    );

    # Store a new ticket
    $store->storeTicket($clientId, $ticketId, $ticketData, $transportParams);

    # Retrieve a ticket
    my $ticket = $store->retrieveTicket($ticketId);

    # Mark ticket as used (for 0-RTT)
    $store->markTicketUsed($ticketId);

    # Cleanup expired tickets
    $store->cleanupExpired();

=head1 DESCRIPTION

This module provides storage for TLS 1.3 session tickets used in QUIC
0-RTT connection resumption. It maintains tickets indexed by both
ticket ID and client ID for efficient lookup.

=head1 METHODS

=head2 new(%config)

Create a new session ticket store.

Options:

=over 4

=item max_tickets - Maximum number of tickets to store (default: 10000)

=item ticket_lifetime - Ticket validity in seconds (default: 86400)

=item cleanup_interval - Automatic cleanup interval (default: 300)

=back

=head2 storeTicket($clientId, $ticketId, $ticketData, $transportParams)

Store a new session ticket.

=head2 retrieveTicket($ticketId)

Retrieve a ticket by ID. Returns undef if not found or expired.

=head2 retrieveTicketForClient($clientId)

Retrieve the most recent valid ticket for a client.

=head2 markTicketUsed($ticketId)

Mark a ticket as used (for single-use enforcement).

=head2 invalidateTicket($ticketId)

Remove a specific ticket.

=head2 invalidateClientTickets($clientId)

Remove all tickets for a client.

=head2 cleanupExpired()

Remove all expired tickets.

=head2 stats()

Get storage statistics.

=head1 SEE ALSO

L<PageCamel::Protocol::QUIC::AntiReplay>,
L<PageCamel::Protocol::QUIC::Connection>

=cut
