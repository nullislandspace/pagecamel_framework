package PageCamel::Protocol::HTTP3::QPACK::Decoder;
use v5.38;
use strict;
use warnings;

use PageCamel::Protocol::HTTP3::QPACK::StaticTable;
use PageCamel::Protocol::HTTP3::QPACK::DynamicTable;

our $VERSION = '0.01';

# QPACK instruction prefixes (for decoding)
use constant {
    # Header block instruction patterns (high bits)
    INDEXED_STATIC_MASK         => 0b11000000,
    INDEXED_STATIC_PATTERN      => 0b11000000,  # 1 1 T=1 index
    INDEXED_DYNAMIC_MASK        => 0b11000000,
    INDEXED_DYNAMIC_PATTERN     => 0b10000000,  # 1 0 index
    LITERAL_WITH_NAME_REF_MASK  => 0b11000000,
    LITERAL_WITH_NAME_REF_PATTERN => 0b01000000,  # 0 1 N T index value
    LITERAL_WITHOUT_NAME_REF_MASK => 0b11100000,
    LITERAL_WITHOUT_NAME_REF_PATTERN => 0b00100000,  # 0 0 1 N name value
    LITERAL_WITH_POST_BASE_MASK => 0b11110000,
    LITERAL_WITH_POST_BASE_PATTERN => 0b00010000,  # 0 0 0 1 N index value
    INDEXED_WITH_POST_BASE_MASK => 0b11110000,
    INDEXED_WITH_POST_BASE_PATTERN => 0b00010000,  # 0 0 0 1 index

    # Decoder stream instructions
    SECTION_ACK   => 0b10000000,  # 1 stream_id
    STREAM_CANCEL => 0b01000000,  # 0 1 stream_id
    INSERT_COUNT_INCREMENT => 0b00000000,  # 0 0 increment
};

sub new($class, %config) {
    my $self = bless {
        # Configuration
        max_table_capacity  => $config{max_table_capacity} // 4096,
        max_blocked_streams => $config{max_blocked_streams} // 100,

        # Dynamic table
        dynamic_table => PageCamel::Protocol::HTTP3::QPACK::DynamicTable->new(
            max_capacity => $config{max_table_capacity} // 4096,
        ),

        # State
        known_received_count => 0,
        pending_decoder_stream => '',  # Data to send on decoder stream

        # Statistics
        headers_decoded => 0,
        bytes_processed => 0,
    }, $class;

    return $self;
}

# Decode a header block
sub decode($self, $data, %opts) {
    my $stream_id = $opts{stream_id};

    my $pos = 0;
    my $len = length($data);

    # Decode Required Insert Count and Delta Base prefix
    my ($required_insert_count, $delta_base);
    ($required_insert_count, $pos) = $self->_decode_prefix_ric($data, $pos);
    ($delta_base, $pos) = $self->_decode_prefix_base($data, $pos);

    # Calculate base
    my $base = $required_insert_count + $delta_base;

    # Check if we can decode (no blocking in this simplified implementation)
    if ($required_insert_count > $self->{dynamic_table}->insert_count()) {
        # Would need to block - return error
        return (undef, "required_insert_count $required_insert_count > " .
                       "known " . $self->{dynamic_table}->insert_count());
    }

    # Decode headers
    my @headers;

    while ($pos < $len) {
        my ($name, $value);
        my $byte = ord(substr($data, $pos, 1));

        if (($byte & 0b11000000) == 0b11000000) {
            # Indexed Header Field (static table)
            # 1 1 index
            ($name, $value, $pos) = $self->_decode_indexed_static($data, $pos);
        }
        elsif (($byte & 0b11000000) == 0b10000000) {
            # Indexed Header Field (dynamic table)
            # 1 0 index
            ($name, $value, $pos) = $self->_decode_indexed_dynamic($data, $pos, $base);
        }
        elsif (($byte & 0b11110000) == 0b01010000) {
            # Literal with Name Reference (static table)
            # 0 1 0 1 T=1 index value
            ($name, $value, $pos) = $self->_decode_literal_name_ref_static($data, $pos);
        }
        elsif (($byte & 0b11110000) == 0b01000000) {
            # Literal with Name Reference (dynamic table)
            # 0 1 0 0 index value
            ($name, $value, $pos) = $self->_decode_literal_name_ref_dynamic($data, $pos, $base);
        }
        elsif (($byte & 0b11100000) == 0b00100000) {
            # Literal without Name Reference
            # 0 0 1 N name value
            ($name, $value, $pos) = $self->_decode_literal_no_name_ref($data, $pos);
        }
        elsif (($byte & 0b11110000) == 0b00010000) {
            # Literal with Post-Base Name Reference
            # 0 0 0 1 N index value
            ($name, $value, $pos) = $self->_decode_literal_post_base($data, $pos, $base);
        }
        elsif (($byte & 0b11110000) == 0b00000000) {
            # Indexed with Post-Base
            # 0 0 0 0 index
            ($name, $value, $pos) = $self->_decode_indexed_post_base($data, $pos, $base);
        }
        else {
            return (undef, "Unknown instruction byte: " . sprintf("0x%02x", $byte));
        }

        unless (defined $name) {
            return (undef, "Failed to decode header at position $pos");
        }

        push @headers, [$name, $value];
        $self->{headers_decoded}++;
    }

    $self->{bytes_processed} += $len;

    # Generate Section Acknowledgment
    if (defined $stream_id && $required_insert_count > 0) {
        $self->_send_section_ack($stream_id);
    }

    return (\@headers, undef);
}

sub _decode_prefix_ric($self, $data, $pos) {
    # Required Insert Count (8-bit prefix integer)
    my ($ric, $new_pos) = $self->_decode_integer($data, $pos, 8);
    return ($ric, $new_pos);
}

sub _decode_prefix_base($self, $data, $pos) {
    # Delta Base with sign (7-bit prefix, high bit is sign)
    my $byte = ord(substr($data, $pos, 1));
    my $sign = ($byte & 0x80) ? -1 : 1;
    my $value = $byte & 0x7f;

    $pos++;

    if ($value == 0x7f) {
        my ($rest, $new_pos) = $self->_decode_integer($data, $pos, 0);
        $value += $rest;
        $pos = $new_pos;
    }

    return ($sign * $value, $pos);
}

sub _decode_indexed_static($self, $data, $pos) {
    # 1 1 T=1 index (6-bit prefix)
    my $byte = ord(substr($data, $pos, 1));
    my $index = $byte & 0x3f;
    $pos++;

    if ($index == 0x3f) {
        my ($rest, $new_pos) = $self->_decode_integer($data, $pos, 0);
        $index += $rest;
        $pos = $new_pos;
    }

    my ($name, $value) = PageCamel::Protocol::HTTP3::QPACK::StaticTable->get($index);
    return ($name, $value, $pos);
}

sub _decode_indexed_dynamic($self, $data, $pos, $base) {
    # 1 0 index (6-bit prefix)
    my $byte = ord(substr($data, $pos, 1));
    my $index = $byte & 0x3f;
    $pos++;

    if ($index == 0x3f) {
        my ($rest, $new_pos) = $self->_decode_integer($data, $pos, 0);
        $index += $rest;
        $pos = $new_pos;
    }

    # Convert to absolute index: base - index - 1
    my $abs_index = $base - $index - 1;
    my $entry = $self->{dynamic_table}->get_absolute($abs_index);

    if ($entry) {
        return ($entry->[0], $entry->[1], $pos);
    }

    return (undef, undef, $pos);
}

sub _decode_literal_name_ref_static($self, $data, $pos) {
    # 0 1 0 1 T=1 index (4-bit prefix) value
    my $byte = ord(substr($data, $pos, 1));
    my $index = $byte & 0x0f;
    $pos++;

    if ($index == 0x0f) {
        my ($rest, $new_pos) = $self->_decode_integer($data, $pos, 0);
        $index += $rest;
        $pos = $new_pos;
    }

    my $name = PageCamel::Protocol::HTTP3::QPACK::StaticTable->get_name($index);

    my ($value, $new_pos) = $self->_decode_string($data, $pos);
    $pos = $new_pos;

    return ($name, $value, $pos);
}

sub _decode_literal_name_ref_dynamic($self, $data, $pos, $base) {
    # 0 1 0 0 index (4-bit prefix) value
    my $byte = ord(substr($data, $pos, 1));
    my $index = $byte & 0x0f;
    $pos++;

    if ($index == 0x0f) {
        my ($rest, $new_pos) = $self->_decode_integer($data, $pos, 0);
        $index += $rest;
        $pos = $new_pos;
    }

    # Convert to absolute index
    my $abs_index = $base - $index - 1;
    my $name = $self->{dynamic_table}->get_name($self->{dynamic_table}->absolute_to_relative($abs_index));

    my ($value, $new_pos) = $self->_decode_string($data, $pos);
    $pos = $new_pos;

    return ($name, $value, $pos);
}

sub _decode_literal_no_name_ref($self, $data, $pos) {
    # 0 0 1 N name (3-bit prefix for name length indicator) value
    # Skip the instruction byte
    $pos++;

    my ($name, $new_pos) = $self->_decode_string($data, $pos);
    $pos = $new_pos;

    my ($value, $final_pos) = $self->_decode_string($data, $pos);

    return ($name, $value, $final_pos);
}

sub _decode_literal_post_base($self, $data, $pos, $base) {
    # 0 0 0 1 N index (3-bit prefix) value
    my $byte = ord(substr($data, $pos, 1));
    my $index = $byte & 0x07;
    $pos++;

    if ($index == 0x07) {
        my ($rest, $new_pos) = $self->_decode_integer($data, $pos, 0);
        $index += $rest;
        $pos = $new_pos;
    }

    # Post-base index: base + index
    my $abs_index = $base + $index;
    my $name = $self->{dynamic_table}->get_name($self->{dynamic_table}->absolute_to_relative($abs_index));

    my ($value, $new_pos) = $self->_decode_string($data, $pos);

    return ($name, $value, $new_pos);
}

sub _decode_indexed_post_base($self, $data, $pos, $base) {
    # 0 0 0 0 index (4-bit prefix)
    my $byte = ord(substr($data, $pos, 1));
    my $index = $byte & 0x0f;
    $pos++;

    if ($index == 0x0f) {
        my ($rest, $new_pos) = $self->_decode_integer($data, $pos, 0);
        $index += $rest;
        $pos = $new_pos;
    }

    # Post-base index: base + index
    my $abs_index = $base + $index;
    my $entry = $self->{dynamic_table}->get_absolute($abs_index);

    if ($entry) {
        return ($entry->[0], $entry->[1], $pos);
    }

    return (undef, undef, $pos);
}

sub _decode_string($self, $data, $pos) {
    return ('', $pos) if $pos >= length($data);

    my $byte = ord(substr($data, $pos, 1));
    my $huffman = ($byte & 0x80) ? 1 : 0;
    my $len = $byte & 0x7f;
    $pos++;

    if ($len == 0x7f) {
        my ($rest, $new_pos) = $self->_decode_integer($data, $pos, 0);
        $len += $rest;
        $pos = $new_pos;
    }

    my $str = substr($data, $pos, $len);
    $pos += $len;

    if ($huffman) {
        # Huffman decoding not implemented - would need Huffman table
        # For now, return raw data (this is a simplification)
        # In production, implement RFC 7541 Appendix B Huffman table
    }

    return ($str, $pos);
}

sub _decode_integer($self, $data, $pos, $prefix_bits) {
    return (0, $pos) if $pos >= length($data);

    my $value;

    if ($prefix_bits == 0) {
        # No prefix - read continuation bytes
        $value = 0;
        my $shift = 0;

        while ($pos < length($data)) {
            my $byte = ord(substr($data, $pos, 1));
            $pos++;

            $value |= ($byte & 0x7f) << $shift;
            $shift += 7;

            last unless ($byte & 0x80);
        }
    }
    else {
        my $byte = ord(substr($data, $pos, 1));
        my $max_prefix = (1 << $prefix_bits) - 1;
        $value = $byte & $max_prefix;
        $pos++;

        if ($value == $max_prefix) {
            # Need continuation bytes
            my $shift = 0;
            while ($pos < length($data)) {
                $byte = ord(substr($data, $pos, 1));
                $pos++;

                $value += ($byte & 0x7f) << $shift;
                $shift += 7;

                last unless ($byte & 0x80);
            }
        }
    }

    return ($value, $pos);
}

# Process encoder stream data
sub process_encoder_stream($self, $data) {
    my $pos = 0;
    my $len = length($data);

    while ($pos < $len) {
        my $byte = ord(substr($data, $pos, 1));

        if (($byte & 0b11100000) == 0b00100000) {
            # Set Dynamic Table Capacity
            # 0 0 1 capacity (5-bit prefix)
            my $capacity = $byte & 0x1f;
            $pos++;

            if ($capacity == 0x1f) {
                my ($rest, $new_pos) = $self->_decode_integer($data, $pos, 0);
                $capacity += $rest;
                $pos = $new_pos;
            }

            $self->{dynamic_table}->set_capacity($capacity);
        }
        elsif (($byte & 0b11000000) == 0b10000000) {
            # Insert With Name Reference
            # 1 T index (6-bit prefix) value
            my $static = ($byte & 0x40) ? 1 : 0;
            my $index = $byte & 0x3f;
            $pos++;

            if ($index == 0x3f) {
                my ($rest, $new_pos) = $self->_decode_integer($data, $pos, 0);
                $index += $rest;
                $pos = $new_pos;
            }

            my $name;
            if ($static) {
                $name = PageCamel::Protocol::HTTP3::QPACK::StaticTable->get_name($index);
            } else {
                $name = $self->{dynamic_table}->get_name($index);
            }

            my ($value, $new_pos) = $self->_decode_string($data, $pos);
            $pos = $new_pos;

            $self->{dynamic_table}->insert($name, $value);
        }
        elsif (($byte & 0b11000000) == 0b01000000) {
            # Insert Without Name Reference
            # 0 1 name (5-bit prefix for length) value
            $pos++;

            my ($name, $new_pos) = $self->_decode_string($data, $pos - 1);
            # Adjust - the string decode expects pos at start of length byte
            # Re-decode properly
            $pos--;
            my $name_huffman = ($byte & 0x20) ? 1 : 0;
            my $name_len = $byte & 0x1f;
            $pos++;

            if ($name_len == 0x1f) {
                my ($rest, $np) = $self->_decode_integer($data, $pos, 0);
                $name_len += $rest;
                $pos = $np;
            }

            $name = substr($data, $pos, $name_len);
            $pos += $name_len;

            my ($value, $final_pos) = $self->_decode_string($data, $pos);
            $pos = $final_pos;

            $self->{dynamic_table}->insert($name, $value);
        }
        elsif (($byte & 0b11100000) == 0b00000000) {
            # Duplicate
            # 0 0 0 index (5-bit prefix)
            my $index = $byte & 0x1f;
            $pos++;

            if ($index == 0x1f) {
                my ($rest, $new_pos) = $self->_decode_integer($data, $pos, 0);
                $index += $rest;
                $pos = $new_pos;
            }

            $self->{dynamic_table}->duplicate($index);
        }
        else {
            # Unknown instruction
            last;
        }
    }

    # Send Insert Count Increment if we inserted entries
    my $insert_count = $self->{dynamic_table}->insert_count();
    if ($insert_count > $self->{known_received_count}) {
        my $increment = $insert_count - $self->{known_received_count};
        $self->_send_insert_count_increment($increment);
        $self->{known_received_count} = $insert_count;
    }
}

# Decoder stream operations

sub _send_section_ack($self, $stream_id) {
    # Section Acknowledgment: 1 stream_id (7-bit prefix)
    my $instruction;

    if ($stream_id < 0x7f) {
        $instruction = chr(SECTION_ACK | $stream_id);
    } else {
        $instruction = chr(SECTION_ACK | 0x7f);
        $instruction .= $self->_encode_integer($stream_id - 0x7f);
    }

    $self->{pending_decoder_stream} .= $instruction;
}

sub _send_stream_cancel($self, $stream_id) {
    # Stream Cancellation: 0 1 stream_id (6-bit prefix)
    my $instruction;

    if ($stream_id < 0x3f) {
        $instruction = chr(STREAM_CANCEL | $stream_id);
    } else {
        $instruction = chr(STREAM_CANCEL | 0x3f);
        $instruction .= $self->_encode_integer($stream_id - 0x3f);
    }

    $self->{pending_decoder_stream} .= $instruction;
}

sub _send_insert_count_increment($self, $increment) {
    # Insert Count Increment: 0 0 increment (6-bit prefix)
    my $instruction;

    if ($increment < 0x3f) {
        $instruction = chr(INSERT_COUNT_INCREMENT | $increment);
    } else {
        $instruction = chr(INSERT_COUNT_INCREMENT | 0x3f);
        $instruction .= $self->_encode_integer($increment - 0x3f);
    }

    $self->{pending_decoder_stream} .= $instruction;
}

sub _encode_integer($self, $value) {
    my $encoded = '';

    while ($value >= 128) {
        $encoded .= chr(($value & 0x7f) | 0x80);
        $value >>= 7;
    }
    $encoded .= chr($value);

    return $encoded;
}

sub get_decoder_stream_data($self) {
    my $data = $self->{pending_decoder_stream};
    $self->{pending_decoder_stream} = '';
    return $data;
}

# Set dynamic table capacity (from SETTINGS)
sub set_dynamic_table_capacity($self, $capacity) {
    $self->{dynamic_table}->set_capacity($capacity);
}

# Statistics
sub stats($self) {
    return {
        headers_decoded => $self->{headers_decoded},
        bytes_processed => $self->{bytes_processed},
        table_size      => $self->{dynamic_table}->size(),
        table_count     => $self->{dynamic_table}->count(),
        known_received  => $self->{known_received_count},
    };
}

1;

__END__

=head1 NAME

PageCamel::Protocol::HTTP3::QPACK::Decoder - QPACK header decoder

=head1 SYNOPSIS

    use PageCamel::Protocol::HTTP3::QPACK::Decoder;

    my $decoder = PageCamel::Protocol::HTTP3::QPACK::Decoder->new(
        max_table_capacity => 4096,
    );

    # Decode header block
    my ($headers, $error) = $decoder->decode($encoded_data,
        stream_id => 4,
    );

    if ($error) {
        die "Decode error: $error";
    }

    for my $header (@$headers) {
        my ($name, $value) = @$header;
        print "$name: $value\n";
    }

    # Process encoder stream data
    $decoder->process_encoder_stream($encoder_data);

    # Get decoder stream data (send on QPACK decoder stream)
    my $decoder_data = $decoder->get_decoder_stream_data();

=head1 DESCRIPTION

This module implements QPACK header decoding as defined in RFC 9204.
QPACK is the header compression format used in HTTP/3.

=head1 METHODS

=head2 new(%config)

Create a new decoder.

Options:

=over 4

=item max_table_capacity - Dynamic table capacity (default: 4096)

=item max_blocked_streams - Max blocked streams (default: 100)

=back

=head2 decode($data, %opts)

Decode a QPACK header block.

Returns ($headers_arrayref, $error). $headers_arrayref contains
[name, value] pairs. $error is undef on success.

Options:

=over 4

=item stream_id - Stream ID (for section acknowledgment)

=back

=head2 process_encoder_stream($data)

Process data received on the encoder stream. This updates the
dynamic table based on encoder instructions.

=head2 get_decoder_stream_data()

Get pending data for the decoder stream.

=head2 set_dynamic_table_capacity($capacity)

Set the maximum dynamic table capacity.

=head2 stats()

Get decoding statistics.

=head1 QPACK STREAMS

QPACK uses two unidirectional streams:

=over 4

=item Encoder Stream - Carries dynamic table updates from encoder to decoder

=item Decoder Stream - Carries acknowledgments from decoder to encoder

=back

The decoder must call process_encoder_stream() with data received
on the encoder stream, and send get_decoder_stream_data() output
on the decoder stream.

=head1 SEE ALSO

L<PageCamel::Protocol::HTTP3::QPACK::Encoder>,
L<PageCamel::Protocol::HTTP3::QPACK::StaticTable>,
RFC 9204

=cut
