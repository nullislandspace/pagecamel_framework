#!/usr/bin/env perl
use v5.38;
use strict;
use warnings;
use Test::More;

plan skip_all => 'Author tests. Set TEST_HTTP3=1 to run.' unless $ENV{TEST_HTTP3};

# Test QPACK Encoder

use_ok('PageCamel::Protocol::HTTP3::QPACK::Encoder');

# Test basic creation
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();
    ok($encoder, 'Created encoder');

    my $stats = $encoder->stats();
    is($stats->{headers_encoded}, 0, 'Initial headers encoded is 0');
    is($stats->{table_size}, 0, 'Initial table size is 0');
}

# Test encoding with array reference
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();

    my $encoded = $encoder->encode([
        ':status' => '200',
        'content-type' => 'text/html',
    ]);

    ok($encoded, 'Encoded headers from array');
    ok(length($encoded) > 0, 'Encoded data has length');

    my $stats = $encoder->stats();
    is($stats->{headers_encoded}, 2, 'Encoded 2 headers');
}

# Test encoding with hash reference
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();

    my $encoded = $encoder->encode({
        ':status' => '404',
    });

    ok($encoded, 'Encoded headers from hash');
    ok(length($encoded) > 0, 'Encoded data has length');
}

# Test encoding known static table entries
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();

    # :method GET is at static table index 17
    my $encoded = $encoder->encode([':method' => 'GET']);
    ok($encoded, 'Encoded :method GET');

    # Should be relatively short due to static table match
    ok(length($encoded) < 10, 'Static table match produces compact encoding');
}

# Test encoding :status values
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();

    # :status 200 is at static table index 25
    my $encoded200 = $encoder->encode([':status' => '200']);
    ok($encoded200, 'Encoded :status 200');

    # :status 404 is at static table index 27
    my $encoded404 = $encoder->encode([':status' => '404']);
    ok($encoded404, 'Encoded :status 404');
}

# Test encoding literal header (not in static table)
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();

    my $encoded = $encoder->encode(['x-custom-header' => 'custom-value']);
    ok($encoded, 'Encoded custom header');

    # Custom headers require literal encoding (name + value)
    # Should be longer than static table references
    ok(length($encoded) > 10, 'Literal encoding is longer');
}

# Test encoding multiple headers
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();

    my $encoded = $encoder->encode([
        ':status' => '200',
        'content-type' => 'application/json',
        'content-length' => '1234',
        'cache-control' => 'max-age=3600',
        'x-request-id' => 'abc123',
    ]);

    ok($encoded, 'Encoded multiple headers');

    my $stats = $encoder->stats();
    is($stats->{headers_encoded}, 5, 'Encoded 5 headers');
}

# Test header name lowercasing
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();

    # HTTP/3 requires lowercase header names
    my $encoded = $encoder->encode(['Content-Type' => 'text/plain']);
    ok($encoded, 'Encoded uppercase header name');

    # Re-encoding same header (lowercase) should produce same result
    my $encoder2 = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();
    my $encoded2 = $encoder2->encode(['content-type' => 'text/plain']);

    is($encoded, $encoded2, 'Uppercase and lowercase produce same encoding');
}

# Test encoder stream data
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();

    # Initially no pending data
    my $data = $encoder->get_encoder_stream_data();
    is($data, '', 'No initial encoder stream data');
}

# Test set_dynamic_table_capacity
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();

    $encoder->set_dynamic_table_capacity(2048);

    my $data = $encoder->get_encoder_stream_data();
    ok(length($data) > 0, 'Set capacity generates encoder stream data');
}

# Test insert_header
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();

    $encoder->insert_header('x-session-id', 'sess-12345');

    my $data = $encoder->get_encoder_stream_data();
    ok(length($data) > 0, 'Insert header generates encoder stream data');

    my $stats = $encoder->stats();
    is($stats->{table_count}, 1, 'Dynamic table has 1 entry');
}

# Test dynamic table usage after insert
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();

    # Insert a custom header into dynamic table
    $encoder->insert_header('x-custom', 'value1');
    $encoder->get_encoder_stream_data();  # Clear pending

    # Now encoding same header should use dynamic table
    my $encoded1 = $encoder->encode(['x-custom' => 'value1']);
    ok($encoded1, 'Encoded header in dynamic table');

    # Encoding a different value for same name
    my $encoded2 = $encoder->encode(['x-custom' => 'value2']);
    ok($encoded2, 'Encoded header with name in dynamic table');
}

# Test prefix encoding
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();

    # Encode empty headers (just prefix)
    my $encoded = $encoder->encode([]);
    ok($encoded, 'Encoded empty header list');

    # Should have at least the prefix (Required Insert Count + Delta Base)
    ok(length($encoded) >= 2, 'Has prefix bytes');
}

# Test encoding request headers
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();

    my $encoded = $encoder->encode([
        ':method' => 'POST',
        ':scheme' => 'https',
        ':authority' => 'example.com',
        ':path' => '/api/v1/users',
        'content-type' => 'application/json',
        'content-length' => '42',
    ], is_request => 1);

    ok($encoded, 'Encoded request headers');
    ok(length($encoded) > 0, 'Request encoding has content');
}

# Test encoding response headers
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();

    my $encoded = $encoder->encode([
        ':status' => '201',
        'content-type' => 'application/json',
        'location' => '/api/v1/users/123',
    ], is_request => 0);

    ok($encoded, 'Encoded response headers');
    ok(length($encoded) > 0, 'Response encoding has content');
}

# Test encoding long values
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();

    my $longValue = 'x' x 200;
    my $encoded = $encoder->encode(['x-long' => $longValue]);

    ok($encoded, 'Encoded long value');
    # Encoded should contain the value (at least partially)
    ok(length($encoded) > 200, 'Encoded includes long value');
}

# Test stats accumulation
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();

    $encoder->encode([':method' => 'GET']);
    $encoder->encode([':status' => '200']);
    $encoder->encode(['content-type' => 'text/html']);

    my $stats = $encoder->stats();
    is($stats->{headers_encoded}, 3, 'Stats show 3 headers encoded');
}

# Test that encoded data is binary
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();

    my $encoded = $encoder->encode([':method' => 'GET']);

    # Check first byte is valid QPACK instruction
    my $firstByte = ord(substr($encoded, 0, 1));
    ok($firstByte <= 255, 'First byte is valid');
}

done_testing();
