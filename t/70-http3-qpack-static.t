#!/usr/bin/env perl
use v5.38;
use strict;
use warnings;
use Test::More;

# Test QPACK Static Table (RFC 9204)

use_ok('PageCamel::Protocol::HTTP3::QPACK::StaticTable');

# Test table size
is(PageCamel::Protocol::HTTP3::QPACK::StaticTable->size(), 99, 'Static table has 99 entries');

# Test known entries
{
    my ($name, $value) = PageCamel::Protocol::HTTP3::QPACK::StaticTable->get(0);
    is($name, ':authority', 'Index 0 is :authority');
    is($value, '', 'Index 0 value is empty');
}

{
    my ($name, $value) = PageCamel::Protocol::HTTP3::QPACK::StaticTable->get(17);
    is($name, ':method', 'Index 17 is :method');
    is($value, 'GET', 'Index 17 value is GET');
}

{
    my ($name, $value) = PageCamel::Protocol::HTTP3::QPACK::StaticTable->get(25);
    is($name, ':status', 'Index 25 is :status');
    is($value, '200', 'Index 25 value is 200');
}

# Test find() with exact match
{
    my ($index, $exact) = PageCamel::Protocol::HTTP3::QPACK::StaticTable->find(':method', 'GET');
    is($index, 17, 'Found :method GET at index 17');
    is($exact, 1, 'Exact match found');
}

# Test find() with name-only match
{
    my ($index, $exact) = PageCamel::Protocol::HTTP3::QPACK::StaticTable->find(':method', 'PATCH');
    ok(defined($index), 'Found :method by name');
    is($exact, 0, 'Name-only match (PATCH not in table)');
}

# Test find() with non-existent header
{
    my ($index, $exact) = PageCamel::Protocol::HTTP3::QPACK::StaticTable->find('x-custom-header', 'value');
    ok(!defined($index), 'Non-existent header returns undef');
}

# Test find_name()
{
    my $index = PageCamel::Protocol::HTTP3::QPACK::StaticTable->find_name(':status');
    ok(defined($index), 'Found :status by name');
}

# Test find_exact()
{
    my $index = PageCamel::Protocol::HTTP3::QPACK::StaticTable->find_exact(':status', '404');
    is($index, 27, 'Found :status 404 at index 27');
}

# Test case insensitivity
{
    my ($index, $exact) = PageCamel::Protocol::HTTP3::QPACK::StaticTable->find(':METHOD', 'GET');
    is($index, 17, 'Case-insensitive name lookup works');
}

# Test out of bounds
{
    my ($name, $value) = PageCamel::Protocol::HTTP3::QPACK::StaticTable->get(100);
    ok(!defined($name), 'Out of bounds returns undef');
}

done_testing();
