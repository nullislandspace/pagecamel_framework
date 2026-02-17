#!/usr/bin/env perl
# WebSocket over HTTP/2 (RFC 8441) tests

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

# Test HTTP2Handler WebSocket upgrade translation
# Note: PAGECAMEL overhead is sent once per backend connection in createPooledBackend(),
# not with each request. The translateWebsocketUpgrade method only generates the HTTP/1.1 upgrade request.
subtest 'HTTP2Handler WebSocket upgrade translation' => sub {
    use_ok('PageCamel::CMDLine::WebFrontend::HTTP2Handler');

    # Create a mock handler
    my $handler = bless {
        pagecamelInfo => {
            lhost    => '192.168.1.1',
            lport    => 443,
            peerhost => '10.0.0.1',
            peerport => 54321,
            usessl   => 1,
            pid      => $$,
        },
        streamWebsocketKey => {},
    }, 'PageCamel::CMDLine::WebFrontend::HTTP2Handler';

    # Extended CONNECT request for WebSocket
    # Headers come as flat list from PageCamel::Protocol::HTTP2
    my $headers = [
        ':method',        'CONNECT',
        ':scheme',        'https',
        ':path',          '/ws/chat',
        ':authority',     'ws.example.com',
        ':protocol',      'websocket',
        'sec-websocket-protocol', 'chat',
        'origin',         'https://example.com',
    ];

    my $request = $handler->translateWebsocketUpgrade(1, $headers);

    # Verify HTTP/1.1 WebSocket upgrade request (PAGECAMEL is sent separately on connection creation)
    like($request, qr/^GET \/ws\/chat HTTP\/1\.1\r\n/,
         'Translated to GET request');

    # Verify Upgrade header
    like($request, qr/Upgrade: websocket\r\n/,
         'Upgrade: websocket header present');

    # Verify Connection header
    like($request, qr/Connection: Upgrade\r\n/,
         'Connection: Upgrade header present');

    # Verify Sec-WebSocket-Key is generated
    like($request, qr/Sec-WebSocket-Key: [A-Za-z0-9+\/=]+\r\n/,
         'Sec-WebSocket-Key is generated');

    # Verify Sec-WebSocket-Version
    like($request, qr/Sec-WebSocket-Version: 13\r\n/,
         'Sec-WebSocket-Version: 13 header present');

    # Verify custom WebSocket headers are preserved
    like($request, qr/sec-websocket-protocol: chat\r\n/i,
         'Sec-WebSocket-Protocol header preserved');

    # Verify Host header
    like($request, qr/Host: ws\.example\.com\r\n/,
         'Host header is correct');
};

# Test WebSocket key generation
subtest 'WebSocket key generation' => sub {
    my $handler = bless {}, 'PageCamel::CMDLine::WebFrontend::HTTP2Handler';

    my $key1 = $handler->generateWebsocketKey();
    my $key2 = $handler->generateWebsocketKey();

    ok(defined($key1), 'Key 1 is generated');
    ok(defined($key2), 'Key 2 is generated');

    # Keys should be base64 encoded
    like($key1, qr/^[A-Za-z0-9+\/=]+$/, 'Key 1 is base64 encoded');
    like($key2, qr/^[A-Za-z0-9+\/=]+$/, 'Key 2 is base64 encoded');

    # Keys should be unique
    isnt($key1, $key2, 'Generated keys are unique');

    # Key should be approximately 24 characters (16 bytes base64 encoded)
    ok(length($key1) >= 20 && length($key1) <= 28, 'Key length is reasonable');
};

# Test PageCamel::Protocol::HTTP2 extended CONNECT support
subtest 'PageCamel::Protocol::HTTP2 extended CONNECT support' => sub {
    SKIP: {
        eval { require PageCamel::Protocol::HTTP2::Server };
        skip 'PageCamel::Protocol::HTTP2 not installed', 4 if $@;

        require PageCamel::Protocol::HTTP2::Constants;
        PageCamel::Protocol::HTTP2::Constants->import(':settings');

        # Verify SETTINGS_ENABLE_CONNECT_PROTOCOL constant
        is(PageCamel::Protocol::HTTP2::Constants::SETTINGS_ENABLE_CONNECT_PROTOCOL(), 8,
           'SETTINGS_ENABLE_CONNECT_PROTOCOL = 8');

        # Test server with on_connect_request callback
        my $connect_called = 0;
        my $server = PageCamel::Protocol::HTTP2::Server->new(
            on_connect_request => sub {
                $connect_called = 1;
            },
        );

        ok($server, 'Server created with on_connect_request callback');

        # Test enable_connect_protocol method
        can_ok($server, 'enable_connect_protocol');

        $server->enable_connect_protocol(1);
        my $frame = $server->next_frame();
        ok(defined($frame), 'Server generates SETTINGS frame');
    }
};

done_testing();
