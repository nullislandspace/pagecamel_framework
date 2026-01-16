package PageCamel::Protocol::HTTP3::QPACK::Encoder;
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

use PageCamel::Protocol::HTTP3::QPACK::StaticTable;
use PageCamel::Protocol::HTTP3::QPACK::DynamicTable;


# QPACK instruction prefixes
use constant {
    # Header block instructions
    INDEXED_STATIC         => 0b11000000,  # 1 1 T=1 index
    INDEXED_DYNAMIC        => 0b10000000,  # 1 0 index
    LITERAL_WITH_NAME_REF  => 0b01000000,  # 0 1 N T index value
    LITERAL_WITHOUT_NAME_REF => 0b00100000, # 0 0 1 N name value
    LITERAL_WITH_POST_BASE => 0b00010000,  # 0 0 0 1 N index value

    # Encoder stream instructions
    SET_DYNAMIC_TABLE_CAPACITY => 0b00100000,  # 0 0 1 capacity
    INSERT_WITH_NAME_REF       => 0b10000000,  # 1 T index value
    INSERT_WITHOUT_NAME_REF    => 0b01000000,  # 0 1 name value
    DUPLICATE                  => 0b00000000,  # 0 0 0 index
};

sub new($class, %config) {
    my $self = bless {
        # Configuration
        max_table_capacity => $config{max_table_capacity} // 4096,
        max_blocked_streams => $config{max_blocked_streams} // 100,
        use_huffman        => $config{use_huffman} // 0,  # Simplified: no Huffman

        # Dynamic table
        dynamic_table      => PageCamel::Protocol::HTTP3::QPACK::DynamicTable->new(
            max_capacity => $config{max_table_capacity} // 4096,
        ),

        # State
        blocked_streams    => 0,
        pending_encoder_stream => '',  # Data to send on encoder stream

        # Statistics
        headers_encoded    => 0,
        bytes_saved        => 0,
    }, $class;

    return $self;
}

# Encode headers for a request/response

sub encode($self, $headers, %opts) {
    my $stream_id = $opts{stream_id};
    my $is_request = $opts{is_request} // 1;

    my @header_list;
    if (ref($headers) eq 'ARRAY') {
        # Flat array: [name1, value1, name2, value2, ...]
        for (my $i = 0; $i < @$headers; $i += 2) {
            push @header_list, [$headers->[$i], $headers->[$i+1]];
        }
    }
    elsif (ref($headers) eq 'HASH') {
        for my $name (keys %$headers) {
            push @header_list, [$name, $headers->{$name}];
        }
    }
    elsif ($headers->can('each')) {
        # Headers object
        $headers->each(sub {
            my ($name, $value) = @_;
            push @header_list, [$name, $value];
        });
    }

    # Build encoded header block
    my $encoded = '';

    # Required Insert Count and Delta Base (simplified: no dynamic table refs)
    $encoded .= $self->_encode_prefix(0, 0);

    # Encode each header
    for my $header (@header_list) {
        my ($name, $value) = @$header;
        $name = lc($name);  # HTTP/3 requires lowercase

        $encoded .= $self->_encode_header($name, $value);
        $self->{headers_encoded}++;
    }

    return $encoded;
}

sub _encode_prefix($self, $required_insert_count, $delta_base) {
    # Encode Required Insert Count (prefix integer, 8-bit)
    my $prefix = $self->_encode_integer($required_insert_count, 8);

    # Encode Delta Base (prefix integer, 7-bit with sign)
    my $sign = $delta_base >= 0 ? 0 : 1;
    my $delta = abs($delta_base);
    $prefix .= chr(($sign << 7) | ($delta & 0x7f));
    if ($delta >= 0x7f) {
        $prefix .= $self->_encode_integer($delta - 0x7f, 7);
    }

    return $prefix;
}

sub _encode_header($self, $name, $value) {
    # Try static table first
    my ($static_idx, $exact) = PageCamel::Protocol::HTTP3::QPACK::StaticTable->find($name, $value);

    if (defined $static_idx) {
        if ($exact) {
            # Indexed Header Field (static table, exact match)
            return $self->_encode_indexed_static($static_idx);
        } else {
            # Literal with Name Reference (static table)
            return $self->_encode_literal_with_name_ref_static($static_idx, $value);
        }
    }

    # Try dynamic table
    my ($dyn_idx, $dyn_exact) = $self->{dynamic_table}->find($name, $value);

    if (defined $dyn_idx && $dyn_exact) {
        # Indexed Header Field (dynamic table, exact match)
        return $self->_encode_indexed_dynamic($dyn_idx);
    }
    elsif (defined $dyn_idx) {
        # Literal with Name Reference (dynamic table)
        return $self->_encode_literal_with_name_ref_dynamic($dyn_idx, $value);
    }

    # Literal without Name Reference
    return $self->_encode_literal_without_name_ref($name, $value);
}

sub _encode_indexed_static($self, $index) {
    # 1 1 T=1 index (T=1 for static)
    # First byte: 11xxxxxx where x is first 6 bits of index
    return chr(INDEXED_STATIC | ($index & 0x3f)) if $index < 0x3f;

    return chr(INDEXED_STATIC | 0x3f) . $self->_encode_integer($index - 0x3f, 0);
}

sub _encode_indexed_dynamic($self, $index) {
    # 1 0 index
    # First byte: 10xxxxxx where x is first 6 bits of index
    return chr(INDEXED_DYNAMIC | ($index & 0x3f)) if $index < 0x3f;

    return chr(INDEXED_DYNAMIC | 0x3f) . $self->_encode_integer($index - 0x3f, 0);
}

sub _encode_literal_with_name_ref_static($self, $index, $value) {
    # 0 1 0 1 T=1 index value (N=0, T=1 for static)
    # First byte: 0101xxxx where x is first 4 bits of index
    my $encoded = '';

    if ($index < 0x0f) {
        $encoded = chr(0x50 | $index);
    } else {
        $encoded = chr(0x50 | 0x0f) . $self->_encode_integer($index - 0x0f, 0);
    }

    $encoded .= $self->_encode_string($value);

    return $encoded;
}

sub _encode_literal_with_name_ref_dynamic($self, $index, $value) {
    # 0 1 0 0 index value (N=0, T=0 for dynamic)
    # First byte: 0100xxxx where x is first 4 bits of index
    my $encoded = '';

    if ($index < 0x0f) {
        $encoded = chr(0x40 | $index);
    } else {
        $encoded = chr(0x40 | 0x0f) . $self->_encode_integer($index - 0x0f, 0);
    }

    $encoded .= $self->_encode_string($value);

    return $encoded;
}

sub _encode_literal_without_name_ref($self, $name, $value) {
    # 0 0 1 N name value
    # First byte: 0010xxxx where N=0 and x is first 3 bits of name length
    my $encoded = chr(0x20);  # Pattern 001xxxxx with N=0

    $encoded .= $self->_encode_string($name);
    $encoded .= $self->_encode_string($value);

    return $encoded;
}

sub _encode_string($self, $str) {
    my $len = length($str);

    # H bit = 0 (no Huffman in this implementation)
    if ($len < 0x7f) {
        return chr($len) . $str;
    } else {
        return chr(0x7f) . $self->_encode_integer($len - 0x7f, 0) . $str;
    }
}

sub _encode_integer($self, $value, $prefix_bits) {
    my $encoded = '';

    if ($prefix_bits == 0) {
        # No prefix, just encode the integer
        while ($value >= 128) {
            $encoded .= chr(($value & 0x7f) | 0x80);
            $value >>= 7;
        }
        $encoded .= chr($value);
    }
    else {
        # Integer fits in remaining bits
        my $max_prefix = (1 << $prefix_bits) - 1;
        if ($value < $max_prefix) {
            return chr($value);
        }

        # Need continuation bytes
        $value -= $max_prefix;
        while ($value >= 128) {
            $encoded .= chr(($value & 0x7f) | 0x80);
            $value >>= 7;
        }
        $encoded .= chr($value);
    }

    return $encoded;
}

# Encoder stream operations

sub set_dynamic_table_capacity($self, $capacity) {
    $self->{dynamic_table}->set_capacity($capacity);

    # Generate encoder stream instruction
    my $instruction = chr(SET_DYNAMIC_TABLE_CAPACITY);
    $instruction .= $self->_encode_integer($capacity, 5);
    $self->{pending_encoder_stream} .= $instruction;
}

sub insert_header($self, $name, $value) {
    # Insert into dynamic table
    $self->{dynamic_table}->insert($name, $value);

    # Generate encoder stream instruction
    # Try to reference static table name
    my $name_idx = PageCamel::Protocol::HTTP3::QPACK::StaticTable->find_name($name);

    if (defined $name_idx) {
        # Insert With Name Reference (static)
        my $instruction = chr(INSERT_WITH_NAME_REF | 0x40);  # T=1 for static
        $instruction .= $self->_encode_integer($name_idx, 6);
        $instruction .= $self->_encode_string($value);
        $self->{pending_encoder_stream} .= $instruction;
    } else {
        # Insert Without Name Reference
        my $instruction = chr(INSERT_WITHOUT_NAME_REF);
        $instruction .= $self->_encode_string($name);
        $instruction .= $self->_encode_string($value);
        $self->{pending_encoder_stream} .= $instruction;
    }
}

sub get_encoder_stream_data($self) {
    my $data = $self->{pending_encoder_stream};
    $self->{pending_encoder_stream} = '';
    return $data;
}

# Statistics

sub stats($self) {
    return {
        headers_encoded => $self->{headers_encoded},
        bytes_saved     => $self->{bytes_saved},
        table_size      => $self->{dynamic_table}->size(),
        table_count     => $self->{dynamic_table}->count(),
    };
}

1;

__END__

=head1 NAME

PageCamel::Protocol::HTTP3::QPACK::Encoder - QPACK header encoder

=head1 SYNOPSIS

    use PageCamel::Protocol::HTTP3::QPACK::Encoder;

    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new(
        max_table_capacity => 4096,
    );

    # Encode headers
    my $encoded = $encoder->encode([
        ':status' => '200',
        'content-type' => 'text/html',
        'content-length' => '1234',
    ]);

    # Get encoder stream data (send on QPACK encoder stream)
    my $encoder_stream_data = $encoder->get_encoder_stream_data();

=head1 DESCRIPTION

This module implements QPACK header encoding as defined in RFC 9204.
QPACK is the header compression format used in HTTP/3.

=head1 METHODS

=head2 new(%config)

Create a new encoder.

Options:

=over 4

=item max_table_capacity - Dynamic table capacity (default: 4096)

=item max_blocked_streams - Max blocked streams (default: 100)

=item use_huffman - Use Huffman encoding (default: 0)

=back

=head2 encode($headers, %opts)

Encode headers into a QPACK header block.

$headers can be:
- Array reference: [name1, value1, name2, value2, ...]
- Hash reference: {name => value, ...}
- Object with each() method

Returns encoded binary data.

=head2 set_dynamic_table_capacity($capacity)

Set dynamic table capacity (generates encoder stream instruction).

=head2 insert_header($name, $value)

Insert header into dynamic table (generates encoder stream instruction).

=head2 get_encoder_stream_data()

Get pending data for the encoder stream.

=head2 stats()

Get encoding statistics.

=head1 SEE ALSO

L<PageCamel::Protocol::HTTP3::QPACK::Decoder>,
L<PageCamel::Protocol::HTTP3::QPACK::StaticTable>,
RFC 9204

=cut
