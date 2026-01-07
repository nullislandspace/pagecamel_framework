#!/usr/bin/env perl
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl PageCamel.t'

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Test::More;

# Author-only test - requires backend server setup
plan skip_all => 'Author tests. Set TEST_HTTP2=1 to run.' unless $ENV{TEST_HTTP2};

BEGIN {
    if(!defined($ENV{TZ})) {
        $ENV{TZ} = "CET";
    }
}

# Test that required modules compile
use_ok('PageCamel::CMDLine::WebFrontend');
use_ok('PageCamel::CMDLine::WebFrontend::HTTP2Handler');

# Test that PageCamel::Protocol::HTTP2 modules are available
SKIP: {
    eval { require PageCamel::Protocol::HTTP2::Server };
    skip 'PageCamel::Protocol::HTTP2 not installed', 3 if $@;

    use_ok('PageCamel::Protocol::HTTP2::Server');
    use_ok('PageCamel::Protocol::HTTP2::Constants');

    # Test SETTINGS_ENABLE_CONNECT_PROTOCOL constant
    require PageCamel::Protocol::HTTP2::Constants;
    PageCamel::Protocol::HTTP2::Constants->import(':settings');
    ok(defined(&PageCamel::Protocol::HTTP2::Constants::SETTINGS_ENABLE_CONNECT_PROTOCOL),
       'SETTINGS_ENABLE_CONNECT_PROTOCOL constant exists');
}

# Test Net::SSLeay ALPN support
SKIP: {
    eval { require Net::SSLeay };
    skip 'Net::SSLeay not installed', 2 if $@;

    use_ok('Net::SSLeay');

    # Check if ALPN functions exist
    my $has_alpn = Net::SSLeay->can('CTX_set_alpn_select_cb');
    ok($has_alpn, 'Net::SSLeay has ALPN support (CTX_set_alpn_select_cb)');
}

# Test IO::Socket::SSL ALPN support
SKIP: {
    eval { require IO::Socket::SSL };
    skip 'IO::Socket::SSL not installed', 2 if $@;

    use_ok('IO::Socket::SSL');

    # Check if alpn_selected method exists
    my $has_alpn = IO::Socket::SSL->can('alpn_selected');
    ok($has_alpn, 'IO::Socket::SSL has alpn_selected method');
}

done_testing();
