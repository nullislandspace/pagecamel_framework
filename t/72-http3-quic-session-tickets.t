#!/usr/bin/env perl
use v5.38;
use strict;
use warnings;
use Test::More;

# Test QUIC Session Ticket Store

use_ok('PageCamel::Protocol::QUIC::SessionTicketStore');

# Test basic creation
{
    my $store = PageCamel::Protocol::QUIC::SessionTicketStore->new();
    ok($store, 'Created session ticket store');

    my $stats = $store->stats();
    is($stats->{ticketCount}, 0, 'Initial ticket count is 0');
}

# Test storing and retrieving tickets
{
    my $store = PageCamel::Protocol::QUIC::SessionTicketStore->new();

    my $clientId = 'client123';
    my $ticketId = 'ticket456';
    my $ticketData = 'encrypted_ticket_data';
    my $transportParams = {maxStreamData => 1000000};

    my $result = $store->storeTicket($clientId, $ticketId, $ticketData, $transportParams);
    ok($result, 'Ticket stored successfully');

    my $ticket = $store->retrieveTicket($ticketId);
    ok($ticket, 'Ticket retrieved');
    is($ticket->{clientId}, $clientId, 'Client ID matches');
    is($ticket->{ticketData}, $ticketData, 'Ticket data matches');
    is($ticket->{transportParams}{maxStreamData}, 1000000, 'Transport params match');
    ok(!$ticket->{used}, 'Ticket not marked as used');
}

# Test retrieveTicketForClient
{
    my $store = PageCamel::Protocol::QUIC::SessionTicketStore->new();

    $store->storeTicket('client1', 'ticket1', 'data1');
    $store->storeTicket('client1', 'ticket2', 'data2');
    $store->storeTicket('client2', 'ticket3', 'data3');

    my $ticket = $store->retrieveTicketForClient('client1');
    ok($ticket, 'Retrieved ticket for client1');
    is($ticket->{ticketData}, 'data2', 'Got most recent ticket');

    $ticket = $store->retrieveTicketForClient('client2');
    is($ticket->{ticketData}, 'data3', 'Got correct ticket for client2');

    $ticket = $store->retrieveTicketForClient('client3');
    ok(!$ticket, 'No ticket for unknown client');
}

# Test marking ticket as used
{
    my $store = PageCamel::Protocol::QUIC::SessionTicketStore->new();

    $store->storeTicket('client1', 'ticket1', 'data1');
    $store->markTicketUsed('ticket1');

    my $ticket = $store->retrieveTicket('ticket1');
    ok($ticket->{used}, 'Ticket marked as used');
    ok($ticket->{usedAt}, 'usedAt timestamp set');

    # Used ticket should not be returned for client
    my $clientTicket = $store->retrieveTicketForClient('client1');
    ok(!$clientTicket, 'Used ticket not returned for client');
}

# Test invalidating tickets
{
    my $store = PageCamel::Protocol::QUIC::SessionTicketStore->new();

    $store->storeTicket('client1', 'ticket1', 'data1');
    $store->invalidateTicket('ticket1');

    my $ticket = $store->retrieveTicket('ticket1');
    ok(!$ticket, 'Ticket invalidated');

    my $stats = $store->stats();
    is($stats->{ticketCount}, 0, 'Ticket count is 0');
}

# Test invalidating all client tickets
{
    my $store = PageCamel::Protocol::QUIC::SessionTicketStore->new();

    $store->storeTicket('client1', 'ticket1', 'data1');
    $store->storeTicket('client1', 'ticket2', 'data2');
    $store->storeTicket('client2', 'ticket3', 'data3');

    $store->invalidateClientTickets('client1');

    my $t1 = $store->retrieveTicket('ticket1');
    my $t2 = $store->retrieveTicket('ticket2');
    my $t3 = $store->retrieveTicket('ticket3');

    ok(!$t1, 'ticket1 invalidated');
    ok(!$t2, 'ticket2 invalidated');
    ok($t3, 'ticket3 still valid');
}

# Test capacity limit
{
    my $store = PageCamel::Protocol::QUIC::SessionTicketStore->new(
        max_tickets => 3,
    );

    for my $i (1..5) {
        $store->storeTicket("client$i", "ticket$i", "data$i");
    }

    my $stats = $store->stats();
    ok($stats->{ticketCount} <= 3, 'Ticket count within limit');
}

# Test stats
{
    my $store = PageCamel::Protocol::QUIC::SessionTicketStore->new();

    $store->storeTicket('client1', 'ticket1', 'data1');
    $store->storeTicket('client2', 'ticket2', 'data2');

    my $stats = $store->stats();
    is($stats->{ticketCount}, 2, 'Correct ticket count');
    is($stats->{clientCount}, 2, 'Correct client count');
}

done_testing();
