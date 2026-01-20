#!/usr/bin/env perl
use v5.38;
use strict;
use warnings;
use Test::More;

plan skip_all => 'Author tests. Set TEST_HTTP3=1 to run.' unless $ENV{TEST_HTTP3};

# Test QPACK Dynamic Table

use_ok('PageCamel::Protocol::HTTP3::QPACK::DynamicTable');

# Test basic creation
{
    my $table = PageCamel::Protocol::HTTP3::QPACK::DynamicTable->new(
        max_capacity => 4096,
    );
    ok($table, 'Created dynamic table');
    is($table->max_capacity(), 4096, 'Max capacity is 4096');
    is($table->size(), 0, 'Initial size is 0');
    is($table->count(), 0, 'Initial count is 0');
}

# Test insertion
{
    my $table = PageCamel::Protocol::HTTP3::QPACK::DynamicTable->new();
    my $result = $table->insert('content-type', 'application/json');
    is($result, 0, 'Insert returns relative index 0');
    is($table->count(), 1, 'Count is 1 after insert');
    is($table->insert_count(), 1, 'Insert count is 1');
    ok($table->size() > 0, 'Size increased after insert');
}

# Test retrieval by relative index
{
    my $table = PageCamel::Protocol::HTTP3::QPACK::DynamicTable->new();
    $table->insert('header-a', 'value-a');
    $table->insert('header-b', 'value-b');
    $table->insert('header-c', 'value-c');

    # Relative index 0 is most recent
    my $entry = $table->get(0);
    is($entry->[0], 'header-c', 'Relative index 0 is most recent');
    is($entry->[1], 'value-c', 'Correct value for index 0');

    $entry = $table->get(2);
    is($entry->[0], 'header-a', 'Relative index 2 is oldest');
}

# Test find()
{
    my $table = PageCamel::Protocol::HTTP3::QPACK::DynamicTable->new();
    $table->insert('content-type', 'text/html');
    $table->insert('content-type', 'application/json');

    my ($index, $exact) = $table->find('content-type', 'application/json');
    is($index, 0, 'Found exact match at index 0');
    is($exact, 1, 'Exact match flag set');

    ($index, $exact) = $table->find('content-type', 'text/plain');
    ok(defined($index), 'Found name-only match');
    is($exact, 0, 'Exact match flag not set');
}

# Test eviction
{
    my $table = PageCamel::Protocol::HTTP3::QPACK::DynamicTable->new(
        max_capacity => 100,  # Small capacity
    );

    # Insert entries until eviction occurs
    for my $i (1..10) {
        $table->insert("header-$i", "value-$i");
    }

    # Some entries should have been evicted
    ok($table->count() < 10, 'Some entries evicted due to capacity');
    ok($table->dropped_count() > 0, 'Dropped count > 0');
}

# Test set_capacity()
{
    my $table = PageCamel::Protocol::HTTP3::QPACK::DynamicTable->new(
        max_capacity => 4096,
    );

    for my $i (1..5) {
        $table->insert("header-$i", "value-$i");
    }

    my $countBefore = $table->count();
    $table->set_capacity(50);  # Very small

    ok($table->count() < $countBefore, 'Reducing capacity evicts entries');
    is($table->max_capacity(), 50, 'Capacity updated');
}

# Test clear()
{
    my $table = PageCamel::Protocol::HTTP3::QPACK::DynamicTable->new();
    $table->insert('header', 'value');
    $table->clear();

    is($table->count(), 0, 'Count is 0 after clear');
    is($table->size(), 0, 'Size is 0 after clear');
}

# Test duplicate()
{
    my $table = PageCamel::Protocol::HTTP3::QPACK::DynamicTable->new();
    $table->insert('original', 'value');
    $table->duplicate(0);

    is($table->count(), 2, 'Count is 2 after duplicate');
    my $entry = $table->get(0);
    is($entry->[0], 'original', 'Duplicated entry has correct name');
}

# Test absolute indexing
{
    my $table = PageCamel::Protocol::HTTP3::QPACK::DynamicTable->new();
    $table->insert('header-1', 'value-1');
    $table->insert('header-2', 'value-2');
    $table->insert('header-3', 'value-3');

    # Absolute index 0 is first ever inserted
    my $entry = $table->get_absolute(0);
    is($entry->[0], 'header-1', 'Absolute index 0 is first inserted');

    $entry = $table->get_absolute(2);
    is($entry->[0], 'header-3', 'Absolute index 2 is third inserted');
}

# Test index conversion
{
    my $table = PageCamel::Protocol::HTTP3::QPACK::DynamicTable->new();
    $table->insert('header-1', 'value-1');
    $table->insert('header-2', 'value-2');
    $table->insert('header-3', 'value-3');

    my $abs = $table->relative_to_absolute(0);
    is($abs, 2, 'Relative 0 -> Absolute 2');

    my $rel = $table->absolute_to_relative(0);
    is($rel, 2, 'Absolute 0 -> Relative 2');
}

done_testing();
