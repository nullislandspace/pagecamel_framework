package PageCamel::Protocol::HTTP3::QPACK::StaticTable;
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


# QPACK Static Table (RFC 9204, Appendix A)
# Different from HPACK - optimized for HTTP/3

our @STATIC_TABLE = (
    # Index 0
    [':authority', ''],
    # Index 1
    [':path', '/'],
    # Index 2
    ['age', '0'],
    # Index 3
    ['content-disposition', ''],
    # Index 4
    ['content-length', '0'],
    # Index 5
    ['cookie', ''],
    # Index 6
    ['date', ''],
    # Index 7
    ['etag', ''],
    # Index 8
    ['if-modified-since', ''],
    # Index 9
    ['if-none-match', ''],
    # Index 10
    ['last-modified', ''],
    # Index 11
    ['link', ''],
    # Index 12
    ['location', ''],
    # Index 13
    ['referer', ''],
    # Index 14
    ['set-cookie', ''],
    # Index 15
    [':method', 'CONNECT'],
    # Index 16
    [':method', 'DELETE'],
    # Index 17
    [':method', 'GET'],
    # Index 18
    [':method', 'HEAD'],
    # Index 19
    [':method', 'OPTIONS'],
    # Index 20
    [':method', 'POST'],
    # Index 21
    [':method', 'PUT'],
    # Index 22
    [':scheme', 'http'],
    # Index 23
    [':scheme', 'https'],
    # Index 24
    [':status', '103'],
    # Index 25
    [':status', '200'],
    # Index 26
    [':status', '304'],
    # Index 27
    [':status', '404'],
    # Index 28
    [':status', '503'],
    # Index 29
    ['accept', '*/*'],
    # Index 30
    ['accept', 'application/dns-message'],
    # Index 31
    ['accept-encoding', 'gzip, deflate, br'],
    # Index 32
    ['accept-ranges', 'bytes'],
    # Index 33
    ['access-control-allow-headers', 'cache-control'],
    # Index 34
    ['access-control-allow-headers', 'content-type'],
    # Index 35
    ['access-control-allow-origin', '*'],
    # Index 36
    ['cache-control', 'max-age=0'],
    # Index 37
    ['cache-control', 'max-age=2592000'],
    # Index 38
    ['cache-control', 'max-age=604800'],
    # Index 39
    ['cache-control', 'no-cache'],
    # Index 40
    ['cache-control', 'no-store'],
    # Index 41
    ['cache-control', 'public, max-age=31536000'],
    # Index 42
    ['content-encoding', 'br'],
    # Index 43
    ['content-encoding', 'gzip'],
    # Index 44
    ['content-type', 'application/dns-message'],
    # Index 45
    ['content-type', 'application/javascript'],
    # Index 46
    ['content-type', 'application/json'],
    # Index 47
    ['content-type', 'application/x-www-form-urlencoded'],
    # Index 48
    ['content-type', 'image/gif'],
    # Index 49
    ['content-type', 'image/jpeg'],
    # Index 50
    ['content-type', 'image/png'],
    # Index 51
    ['content-type', 'text/css'],
    # Index 52
    ['content-type', 'text/html; charset=utf-8'],
    # Index 53
    ['content-type', 'text/plain'],
    # Index 54
    ['content-type', 'text/plain;charset=utf-8'],
    # Index 55
    ['range', 'bytes=0-'],
    # Index 56
    ['strict-transport-security', 'max-age=31536000'],
    # Index 57
    ['strict-transport-security', 'max-age=31536000; includesubdomains'],
    # Index 58
    ['strict-transport-security', 'max-age=31536000; includesubdomains; preload'],
    # Index 59
    ['vary', 'accept-encoding'],
    # Index 60
    ['vary', 'origin'],
    # Index 61
    ['x-content-type-options', 'nosniff'],
    # Index 62
    ['x-xss-protection', '1; mode=block'],
    # Index 63
    [':status', '100'],
    # Index 64
    [':status', '204'],
    # Index 65
    [':status', '206'],
    # Index 66
    [':status', '302'],
    # Index 67
    [':status', '400'],
    # Index 68
    [':status', '403'],
    # Index 69
    [':status', '421'],
    # Index 70
    [':status', '425'],
    # Index 71
    [':status', '500'],
    # Index 72
    ['accept-language', ''],
    # Index 73
    ['access-control-allow-credentials', 'FALSE'],
    # Index 74
    ['access-control-allow-credentials', 'TRUE'],
    # Index 75
    ['access-control-allow-headers', '*'],
    # Index 76
    ['access-control-allow-methods', 'get'],
    # Index 77
    ['access-control-allow-methods', 'get, post, options'],
    # Index 78
    ['access-control-allow-methods', 'options'],
    # Index 79
    ['access-control-expose-headers', 'content-length'],
    # Index 80
    ['access-control-request-headers', 'content-type'],
    # Index 81
    ['access-control-request-method', 'get'],
    # Index 82
    ['access-control-request-method', 'post'],
    # Index 83
    ['alt-svc', 'clear'],
    # Index 84
    ['authorization', ''],
    # Index 85
    ['content-security-policy', "script-src 'none'; object-src 'none'; base-uri 'none'"],
    # Index 86
    ['early-data', '1'],
    # Index 87
    ['expect-ct', ''],
    # Index 88
    ['forwarded', ''],
    # Index 89
    ['if-range', ''],
    # Index 90
    ['origin', ''],
    # Index 91
    ['purpose', 'prefetch'],
    # Index 92
    ['server', ''],
    # Index 93
    ['timing-allow-origin', '*'],
    # Index 94
    ['upgrade-insecure-requests', '1'],
    # Index 95
    ['user-agent', ''],
    # Index 96
    ['x-forwarded-for', ''],
    # Index 97
    ['x-frame-options', 'deny'],
    # Index 98
    ['x-frame-options', 'sameorigin'],
);

# Pre-build lookup tables for fast access
our %NAME_INDEX;      # name -> first index with this name
our %NAME_VALUE_INDEX; # "name\0value" -> index

sub _build_indexes {
    for my $i (0 .. $#STATIC_TABLE) {
        my ($name, $value) = @{$STATIC_TABLE[$i]};

        # First index for this name
        $NAME_INDEX{$name} //= $i;

        # Exact match index
        $NAME_VALUE_INDEX{"$name\0$value"} = $i;
    }
    return;
}

_build_indexes();

# Class methods

sub size($class = undef) {
    return scalar @STATIC_TABLE;
}

sub get($class, $index) {
    return unless $index >= 0 && $index < @STATIC_TABLE;
    return @{$STATIC_TABLE[$index]};
}

sub get_name($class, $index) {
    return unless $index >= 0 && $index < @STATIC_TABLE;
    return $STATIC_TABLE[$index][0];
}

sub get_value($class, $index) {
    return unless $index >= 0 && $index < @STATIC_TABLE;
    return $STATIC_TABLE[$index][1];
}

sub find($class, $name, $value = undef) {
    $name = lc($name);

    if (defined $value) {
        # Look for exact match first
        my $key = "$name\0$value";
        if (exists $NAME_VALUE_INDEX{$key}) {
            return ($NAME_VALUE_INDEX{$key}, 1);  # (index, exact_match)
        }
    }

    # Look for name-only match
    if (exists $NAME_INDEX{$name}) {
        return ($NAME_INDEX{$name}, 0);  # (index, name_only_match)
    }

    return ();  # Not found
}

sub find_name($class, $name) {
    $name = lc($name);
    return $NAME_INDEX{$name};
}

sub find_exact($class, $name, $value) {
    $name = lc($name);
    my $key = "$name\0$value";
    return $NAME_VALUE_INDEX{$key};
}

1;

__END__

=head1 NAME

PageCamel::Protocol::HTTP3::QPACK::StaticTable - QPACK static table

=head1 SYNOPSIS

    use PageCamel::Protocol::HTTP3::QPACK::StaticTable;

    # Get entry at index
    my ($name, $value) = PageCamel::Protocol::HTTP3::QPACK::StaticTable->get(17);
    # Returns (':method', 'GET')

    # Find index for name/value
    my ($index, $exact) = PageCamel::Protocol::HTTP3::QPACK::StaticTable->find(':method', 'GET');
    # Returns (17, 1)

    # Find index for name only
    my $index = PageCamel::Protocol::HTTP3::QPACK::StaticTable->find_name(':method');
    # Returns 15

=head1 DESCRIPTION

This module provides access to the QPACK static table as defined in
RFC 9204, Appendix A. The static table contains 99 pre-defined header
field entries that can be referenced by index.

The QPACK static table differs from the HPACK static table used in HTTP/2,
as it is optimized for HTTP/3 usage patterns.

=head1 CLASS METHODS

=head2 size()

Returns the number of entries in the static table (99).

=head2 get($index)

Returns (name, value) for the entry at $index.

=head2 get_name($index)

Returns the header name at $index.

=head2 get_value($index)

Returns the header value at $index.

=head2 find($name, $value)

Find an entry in the static table.

Returns ($index, $exact_match) where $exact_match is true if both
name and value matched.

=head2 find_name($name)

Find the first entry with the given name.

Returns the index or undef.

=head2 find_exact($name, $value)

Find an entry with exact name and value match.

Returns the index or undef.

=head1 SEE ALSO

L<PageCamel::Protocol::HTTP3::QPACK::Encoder>,
L<PageCamel::Protocol::HTTP3::QPACK::Decoder>,
RFC 9204 (QPACK)

=cut
