#!/usr/bin/env perl
use v5.38;
use strict;
use warnings;
use Test::More;

plan skip_all => 'Author tests. Set TEST_HTTP3=1 to run.' unless $ENV{TEST_HTTP3};

# Test QPACK Decoder

use_ok('PageCamel::Protocol::HTTP3::QPACK::Decoder');
use_ok('PageCamel::Protocol::HTTP3::QPACK::Encoder');

# Test basic creation
{
    my $decoder = PageCamel::Protocol::HTTP3::QPACK::Decoder->new();
    ok($decoder, 'Created decoder');

    my $stats = $decoder->stats();
    is($stats->{headers_decoded}, 0, 'Initial headers decoded is 0');
    is($stats->{bytes_processed}, 0, 'Initial bytes processed is 0');
}

# Test decoding encoder output (round-trip)
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();
    my $decoder = PageCamel::Protocol::HTTP3::QPACK::Decoder->new();

    # Encode some headers
    my $encoded = $encoder->encode([':method' => 'GET']);

    # Decode them
    my ($headers, $error) = $decoder->decode($encoded);

    ok(!$error, 'No decode error');
    ok($headers, 'Got headers');
    is(scalar(@$headers), 1, 'Got 1 header');
    is($headers->[0][0], ':method', 'Header name is :method');
    is($headers->[0][1], 'GET', 'Header value is GET');
}

# Test decoding multiple headers
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();
    my $decoder = PageCamel::Protocol::HTTP3::QPACK::Decoder->new();

    my $encoded = $encoder->encode([
        ':status' => '200',
        'content-type' => 'text/html',
        'content-length' => '1234',
    ]);

    my ($headers, $error) = $decoder->decode($encoded);

    ok(!$error, 'No decode error');
    is(scalar(@$headers), 3, 'Got 3 headers');
}

# Test decoding static table indexed headers
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();
    my $decoder = PageCamel::Protocol::HTTP3::QPACK::Decoder->new();

    # :status 200 is at static table index 25
    my $encoded = $encoder->encode([':status' => '200']);
    my ($headers, $error) = $decoder->decode($encoded);

    ok(!$error, 'No decode error for static indexed');
    is($headers->[0][0], ':status', 'Static header name decoded');
    is($headers->[0][1], '200', 'Static header value decoded');
}

# Test decoding literal header (not in static table)
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();
    my $decoder = PageCamel::Protocol::HTTP3::QPACK::Decoder->new();

    my $encoded = $encoder->encode(['x-custom-header' => 'custom-value']);
    my ($headers, $error) = $decoder->decode($encoded);

    ok(!$error, 'No decode error for literal');
    is($headers->[0][0], 'x-custom-header', 'Literal header name decoded');
    is($headers->[0][1], 'custom-value', 'Literal header value decoded');
}

# Test decoding with stream_id
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();
    my $decoder = PageCamel::Protocol::HTTP3::QPACK::Decoder->new();

    my $encoded = $encoder->encode([':method' => 'POST']);
    my ($headers, $error) = $decoder->decode($encoded, stream_id => 4);

    ok(!$error, 'No decode error with stream_id');
    ok($headers, 'Got headers with stream_id');
}

# Test decoder stream data
{
    my $decoder = PageCamel::Protocol::HTTP3::QPACK::Decoder->new();

    # Initially no pending data
    my $data = $decoder->get_decoder_stream_data();
    is($data, '', 'No initial decoder stream data');
}

# Test set_dynamic_table_capacity
{
    my $decoder = PageCamel::Protocol::HTTP3::QPACK::Decoder->new();

    $decoder->set_dynamic_table_capacity(2048);

    my $stats = $decoder->stats();
    # Capacity should be set (table_size will still be 0 with no entries)
    is($stats->{table_size}, 0, 'Table size is 0 with no entries');
}

# Test process_encoder_stream with capacity instruction
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();
    my $decoder = PageCamel::Protocol::HTTP3::QPACK::Decoder->new();

    # Generate capacity instruction
    $encoder->set_dynamic_table_capacity(1024);
    my $encoderData = $encoder->get_encoder_stream_data();

    # Process on decoder
    $decoder->process_encoder_stream($encoderData);

    # No error means success
    ok(1, 'Processed encoder stream capacity instruction');
}

# Test process_encoder_stream with insert instruction
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();
    my $decoder = PageCamel::Protocol::HTTP3::QPACK::Decoder->new();

    # Insert a header
    $encoder->insert_header('x-session', 'abc123');
    my $encoderData = $encoder->get_encoder_stream_data();

    # Process on decoder
    $decoder->process_encoder_stream($encoderData);

    my $stats = $decoder->stats();
    ok($stats->{table_count} >= 1, 'Decoder dynamic table has entries after insert');
}

# Test decoding request headers round-trip
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();
    my $decoder = PageCamel::Protocol::HTTP3::QPACK::Decoder->new();

    my $encoded = $encoder->encode([
        ':method' => 'POST',
        ':scheme' => 'https',
        ':authority' => 'example.com',
        ':path' => '/api/users',
        'content-type' => 'application/json',
    ], is_request => 1);

    my ($headers, $error) = $decoder->decode($encoded);

    ok(!$error, 'No error decoding request headers');
    is(scalar(@$headers), 5, 'Got 5 request headers');

    # Check all pseudo-headers
    my %h = map { $_->[0] => $_->[1] } @$headers;
    is($h{':method'}, 'POST', ':method decoded');
    is($h{':scheme'}, 'https', ':scheme decoded');
    is($h{':authority'}, 'example.com', ':authority decoded');
    is($h{':path'}, '/api/users', ':path decoded');
}

# Test decoding response headers round-trip
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();
    my $decoder = PageCamel::Protocol::HTTP3::QPACK::Decoder->new();

    my $encoded = $encoder->encode([
        ':status' => '201',
        'content-type' => 'application/json',
        'location' => '/api/users/123',
    ], is_request => 0);

    my ($headers, $error) = $decoder->decode($encoded);

    ok(!$error, 'No error decoding response headers');
    is(scalar(@$headers), 3, 'Got 3 response headers');

    my %h = map { $_->[0] => $_->[1] } @$headers;
    is($h{':status'}, '201', ':status decoded');
    is($h{'location'}, '/api/users/123', 'location decoded');
}

# Test decoding long values
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();
    my $decoder = PageCamel::Protocol::HTTP3::QPACK::Decoder->new();

    my $longValue = 'x' x 200;
    my $encoded = $encoder->encode(['x-long' => $longValue]);

    my ($headers, $error) = $decoder->decode($encoded);

    ok(!$error, 'No error decoding long value');
    is($headers->[0][1], $longValue, 'Long value decoded correctly');
}

# Test stats accumulation
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();
    my $decoder = PageCamel::Protocol::HTTP3::QPACK::Decoder->new();

    # Decode multiple headers
    for my $status ('200', '404', '500') {
        my $encoded = $encoder->encode([':status' => $status]);
        $decoder->decode($encoded);
    }

    my $stats = $decoder->stats();
    is($stats->{headers_decoded}, 3, 'Stats show 3 headers decoded');
    ok($stats->{bytes_processed} > 0, 'Bytes processed > 0');
}

# Test empty headers list
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();
    my $decoder = PageCamel::Protocol::HTTP3::QPACK::Decoder->new();

    my $encoded = $encoder->encode([]);
    my ($headers, $error) = $decoder->decode($encoded);

    ok(!$error, 'No error decoding empty headers');
    is(scalar(@$headers), 0, 'Got 0 headers');
}

# Test all common HTTP status codes
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();
    my $decoder = PageCamel::Protocol::HTTP3::QPACK::Decoder->new();

    for my $status (200, 204, 206, 304, 400, 404, 500) {
        my $encoded = $encoder->encode([':status' => "$status"]);
        my ($headers, $error) = $decoder->decode($encoded);

        ok(!$error, "No error for status $status");
        is($headers->[0][1], "$status", "Status $status decoded correctly");
    }
}

# Test all common HTTP methods
{
    my $encoder = PageCamel::Protocol::HTTP3::QPACK::Encoder->new();
    my $decoder = PageCamel::Protocol::HTTP3::QPACK::Decoder->new();

    for my $method (qw(GET POST PUT DELETE HEAD OPTIONS PATCH)) {
        my $encoded = $encoder->encode([':method' => $method]);
        my ($headers, $error) = $decoder->decode($encoded);

        ok(!$error, "No error for method $method");
        is($headers->[0][1], $method, "Method $method decoded correctly");
    }
}

done_testing();
