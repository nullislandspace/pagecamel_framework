#!/usr/bin/env perl
use v5.38;
use strict;
use warnings;
use Test::More;

plan skip_all => 'Author tests. Set TEST_HTTP3=1 to run.' unless $ENV{TEST_HTTP3};

# Test new unified HTTP/3 module

use_ok('PageCamel::Protocol::HTTP3');

# Test version
ok(PageCamel::Protocol::HTTP3->VERSION, 'Module has VERSION');

# Test library initialization
{
    my $result = PageCamel::Protocol::HTTP3::init();
    is($result, 0, 'h3_init() returns H3_OK');
}

# Test return code constants
{
    is(PageCamel::Protocol::HTTP3::H3_OK(), 0, 'H3_OK is 0');
    is(PageCamel::Protocol::HTTP3::H3_WOULDBLOCK(), 1, 'H3_WOULDBLOCK is 1');
    ok(PageCamel::Protocol::HTTP3::H3_ERROR() < 0, 'H3_ERROR is negative');
    ok(PageCamel::Protocol::HTTP3::H3_ERROR_NOMEM() < 0, 'H3_ERROR_NOMEM is negative');
    ok(PageCamel::Protocol::HTTP3::H3_ERROR_INVALID() < 0, 'H3_ERROR_INVALID is negative');
    ok(PageCamel::Protocol::HTTP3::H3_ERROR_TLS() < 0, 'H3_ERROR_TLS is negative');
    ok(PageCamel::Protocol::HTTP3::H3_ERROR_QUIC() < 0, 'H3_ERROR_QUIC is negative');
    ok(PageCamel::Protocol::HTTP3::H3_ERROR_HTTP3() < 0, 'H3_ERROR_HTTP3 is negative');
    ok(PageCamel::Protocol::HTTP3::H3_ERROR_STREAM() < 0, 'H3_ERROR_STREAM is negative');
    ok(PageCamel::Protocol::HTTP3::H3_ERROR_CLOSED() < 0, 'H3_ERROR_CLOSED is negative');
}

# Test version string
{
    my $version = PageCamel::Protocol::HTTP3::version();
    ok($version, 'version() returns a value');
    like($version, qr/^\d+\.\d+/, 'version looks like a version string');
}

# Test timestamp function
{
    my $ts1 = PageCamel::Protocol::HTTP3::timestamp_ns();
    ok($ts1 > 0, 'timestamp_ns() returns positive value');

    # Small delay
    select(undef, undef, undef, 0.001);  # 1ms

    my $ts2 = PageCamel::Protocol::HTTP3::timestamp_ns();
    ok($ts2 > $ts1, 'timestamp_ns() increases over time');
}

# Test strerror function
{
    my $msg = PageCamel::Protocol::HTTP3::strerror(0);  # H3_OK
    ok($msg, 'strerror(0) returns a message');
    like($msg, qr/success/i, 'strerror(0) indicates success');

    my $err_msg = PageCamel::Protocol::HTTP3::strerror(-1);  # H3_ERROR
    ok($err_msg, 'strerror(-1) returns a message');
}

# Test connection state constants
{
    is(PageCamel::Protocol::HTTP3::H3_STATE_INITIAL(), 0, 'H3_STATE_INITIAL is 0');
    is(PageCamel::Protocol::HTTP3::H3_STATE_HANDSHAKING(), 1, 'H3_STATE_HANDSHAKING is 1');
    is(PageCamel::Protocol::HTTP3::H3_STATE_ESTABLISHED(), 2, 'H3_STATE_ESTABLISHED is 2');
    is(PageCamel::Protocol::HTTP3::H3_STATE_DRAINING(), 3, 'H3_STATE_DRAINING is 3');
    is(PageCamel::Protocol::HTTP3::H3_STATE_CLOSED(), 4, 'H3_STATE_CLOSED is 4');
}

# Cleanup
PageCamel::Protocol::HTTP3::cleanup();
pass('h3_cleanup() completed');

done_testing();
