package PageCamel::Protocol::HTTP3::QPACK::DynamicTable;
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


# QPACK Dynamic Table entry overhead (per RFC 9204)
use constant ENTRY_OVERHEAD => 32;

sub new($class, %config) {
    my $self = bless {
        # Configuration
        max_capacity   => $config{max_capacity} // 4096,

        # State
        entries        => [],   # Array of [name, value] pairs
        size           => 0,    # Current size in bytes
        insert_count   => 0,    # Total entries ever inserted (for absolute indexing)
        dropped_count  => 0,    # Number of entries evicted

        # Lookup tables
        name_index     => {},   # name -> [indices...]
        name_value_index => {}, # "name\0value" -> index
    }, $class;

    return $self;
}

# Accessors

sub max_capacity($self) { return $self->{max_capacity}; }
sub size($self) { return $self->{size}; }
sub count($self) { return scalar @{$self->{entries}}; }
sub insert_count($self) { return $self->{insert_count}; }
sub dropped_count($self) { return $self->{dropped_count}; }

# Capacity management

sub set_capacity($self, $capacity) {
    $self->{max_capacity} = $capacity;
    $self->_evict_to_fit(0);  # Evict if needed
}

# Insert entry

sub insert($self, $name, $value) {
    my $entry_size = $self->_entry_size($name, $value);

    # Evict entries if needed to make room
    $self->_evict_to_fit($entry_size);

    # Check if entry fits
    if ($entry_size > $self->{max_capacity}) {
        # Entry too large - clear table but don't insert
        $self->clear();
        return -1;
    }

    # Insert at front (newest entries first in QPACK)
    unshift @{$self->{entries}}, [$name, $value];
    $self->{size} += $entry_size;
    $self->{insert_count}++;

    # Update lookup indexes
    $self->_rebuild_indexes();

    return 0;  # Relative index of new entry
}

# Duplicate entry (for QPACK duplicate instruction)

sub duplicate($self, $index) {
    my $entry = $self->get($index);
    return unless $entry;

    return $self->insert($entry->[0], $entry->[1]);
}

# Get entry by relative index (0 = most recent)

sub get($self, $index) {
    return unless $index >= 0 && $index < @{$self->{entries}};
    return $self->{entries}[$index];
}

sub get_name($self, $index) {
    my $entry = $self->get($index);
    return $entry ? $entry->[0] : undef;
}

sub get_value($self, $index) {
    my $entry = $self->get($index);
    return $entry ? $entry->[1] : undef;
}

# Get entry by absolute index (based on insert_count)

sub get_absolute($self, $abs_index) {
    # Convert absolute index to relative index
    my $rel_index = $self->{insert_count} - $abs_index - 1;
    return $self->get($rel_index);
}

# Convert between relative and absolute indexes

sub relative_to_absolute($self, $rel_index) {
    return $self->{insert_count} - $rel_index - 1;
}

sub absolute_to_relative($self, $abs_index) {
    return $self->{insert_count} - $abs_index - 1;
}

# Find entry

sub find($self, $name, $value = undef) {
    $name = lc($name);

    if (defined $value) {
        # Look for exact match
        my $key = "$name\0$value";
        if (exists $self->{name_value_index}{$key}) {
            return ($self->{name_value_index}{$key}, 1);  # (rel_index, exact)
        }
    }

    # Look for name-only match
    if (exists $self->{name_index}{$name} && @{$self->{name_index}{$name}}) {
        return ($self->{name_index}{$name}[0], 0);  # (rel_index, name_only)
    }

    return ();
}

sub find_name($self, $name) {
    $name = lc($name);
    return unless exists $self->{name_index}{$name};
    return $self->{name_index}{$name}[0];
}

sub find_exact($self, $name, $value) {
    $name = lc($name);
    my $key = "$name\0$value";
    return $self->{name_value_index}{$key};
}

# Clear table

sub clear($self) {
    $self->{dropped_count} += scalar @{$self->{entries}};
    $self->{entries} = [];
    $self->{size} = 0;
    $self->{name_index} = {};
    $self->{name_value_index} = {};
}

# Internal methods

sub _entry_size($self, $name, $value) {
    return length($name) + length($value) + ENTRY_OVERHEAD;
}

sub _evict_to_fit($self, $new_entry_size) {
    # Evict oldest entries until there's room
    while ($self->{size} + $new_entry_size > $self->{max_capacity} &&
           @{$self->{entries}}) {
        my $entry = pop @{$self->{entries}};
        my $entry_size = $self->_entry_size($entry->[0], $entry->[1]);
        $self->{size} -= $entry_size;
        $self->{dropped_count}++;
    }

    # Rebuild indexes after eviction
    $self->_rebuild_indexes() if $new_entry_size == 0;
}

sub _rebuild_indexes($self) {
    # Clear and rebuild lookup indexes
    $self->{name_index} = {};
    $self->{name_value_index} = {};

    for my $i (0 .. $#{$self->{entries}}) {
        my ($name, $value) = @{$self->{entries}[$i]};
        $name = lc($name);

        # Name index (all indices with this name)
        $self->{name_index}{$name} //= [];
        push @{$self->{name_index}{$name}}, $i;

        # Name+value index (first occurrence only)
        my $key = "$name\0$value";
        $self->{name_value_index}{$key} //= $i;
    }
}

# Acknowledgment tracking for QPACK

sub get_known_received_count($self) {
    # Returns the insert count that we know the peer has acknowledged
    # This is needed for QPACK encoder to avoid referencing entries
    # that the decoder might not have yet
    return $self->{insert_count};  # Simplified - assumes all acknowledged
}

sub acknowledge($self, $stream_id, $insert_count) {
    # Mark that decoder has acknowledged entries up to insert_count
    # Used for proper QPACK synchronization
}

1;

__END__

=head1 NAME

PageCamel::Protocol::HTTP3::QPACK::DynamicTable - QPACK dynamic table

=head1 SYNOPSIS

    use PageCamel::Protocol::HTTP3::QPACK::DynamicTable;

    my $table = PageCamel::Protocol::HTTP3::QPACK::DynamicTable->new(
        max_capacity => 4096,
    );

    # Insert entry
    $table->insert('content-type', 'application/json');

    # Get by relative index (0 = most recent)
    my ($name, $value) = @{$table->get(0)};

    # Find entry
    my ($index, $exact) = $table->find('content-type', 'application/json');

    # Set new capacity (may evict entries)
    $table->set_capacity(2048);

=head1 DESCRIPTION

This module implements the QPACK dynamic table as defined in RFC 9204.
The dynamic table stores recently-used header fields that can be
referenced by index in subsequent header blocks.

Unlike the HPACK dynamic table in HTTP/2, QPACK uses absolute indexing
to handle out-of-order delivery in HTTP/3.

=head1 CONSTRUCTOR

=head2 new(%config)

Create a new dynamic table.

Options:

=over 4

=item max_capacity - Maximum table size in bytes (default: 4096)

=back

=head1 METHODS

=head2 Accessors

=over 4

=item max_capacity() - Current maximum capacity

=item size() - Current size in bytes

=item count() - Number of entries

=item insert_count() - Total entries ever inserted

=item dropped_count() - Number of evicted entries

=back

=head2 Capacity Management

=over 4

=item set_capacity($capacity)

Set a new maximum capacity. May evict entries.

=back

=head2 Entry Management

=over 4

=item insert($name, $value)

Insert a new entry. Returns relative index (0) or -1 if too large.

=item duplicate($index)

Duplicate an existing entry (QPACK optimization).

=item clear()

Clear all entries.

=back

=head2 Entry Access

=over 4

=item get($rel_index)

Get entry by relative index (0 = newest).

=item get_name($rel_index)

Get header name by relative index.

=item get_value($rel_index)

Get header value by relative index.

=item get_absolute($abs_index)

Get entry by absolute index.

=back

=head2 Index Conversion

=over 4

=item relative_to_absolute($rel_index)

=item absolute_to_relative($abs_index)

=back

=head2 Lookup

=over 4

=item find($name, $value)

Returns ($index, $exact_match) or empty list.

=item find_name($name)

Returns index of first entry with name.

=item find_exact($name, $value)

Returns index of exact match.

=back

=head1 QPACK INDEXING

QPACK uses absolute indexing starting from 0 for the first entry
ever inserted. Relative indexing (0 = newest) is also supported
for encoding efficiency.

=head1 SEE ALSO

L<PageCamel::Protocol::HTTP3::QPACK::StaticTable>,
L<PageCamel::Protocol::HTTP3::QPACK::Encoder>,
RFC 9204

=cut
