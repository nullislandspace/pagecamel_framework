#!/usr/bin/env perl
# HTTP/2 proxy functionality tests
# Requires a running PageCamel backend for full testing

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

# Test HTTP2Handler request translation
subtest 'HTTP2Handler request translation' => sub {
    use_ok('PageCamel::CMDLine::WebFrontend::HTTP2Handler');

    # Create a mock handler to test translation methods
    my $handler = bless {
        pagecamelInfo => {
            lhost    => '192.168.1.1',
            lport    => 443,
            peerhost => '10.0.0.1',
            peerport => 54321,
            usessl   => 1,
            pid      => $$,
        },
    }, 'PageCamel::CMDLine::WebFrontend::HTTP2Handler';

    # Test translateRequest method
    # Headers come as flat list from Protocol::HTTP2
    my $headers = [
        ':method',    'GET',
        ':scheme',    'https',
        ':path',      '/test/path',
        ':authority', 'example.com',
        'user-agent', 'TestClient/1.0',
        'accept',     '*/*',
    ];

    my $request = $handler->translateRequest(1, $headers, undef);

    # Verify PAGECAMEL overhead header
    like($request, qr/^PAGECAMEL 192\.168\.1\.1 443 10\.0\.0\.1 54321 1 \d+ HTTP\/2\r\n/,
         'PAGECAMEL header contains HTTP/2 version');

    # Verify HTTP/1.1 request line
    like($request, qr/GET \/test\/path HTTP\/1\.1\r\n/,
         'HTTP/1.1 request line is correct');

    # Verify Host header
    like($request, qr/Host: example\.com\r\n/,
         'Host header is present');

    # Verify user-agent header
    like($request, qr/user-agent: TestClient\/1\.0\r\n/i,
         'User-Agent header is preserved');

    # Verify headers end with double CRLF
    like($request, qr/\r\n\r\n$/,
         'Request ends with double CRLF');
};

# Test HTTP2Handler with request body
subtest 'HTTP2Handler POST request with body' => sub {
    my $handler = bless {
        pagecamelInfo => {
            lhost    => '192.168.1.1',
            lport    => 443,
            peerhost => '10.0.0.1',
            peerport => 54321,
            usessl   => 1,
            pid      => $$,
        },
    }, 'PageCamel::CMDLine::WebFrontend::HTTP2Handler';

    my $headers = [
        ':method',       'POST',
        ':scheme',       'https',
        ':path',         '/api/data',
        ':authority',    'api.example.com',
        'content-type',  'application/json',
    ];

    my $body = '{"key": "value"}';
    my $request = $handler->translateRequest(1, $headers, $body);

    # Verify POST method
    like($request, qr/POST \/api\/data HTTP\/1\.1\r\n/,
         'POST request line is correct');

    # Verify Content-Length is added
    like($request, qr/Content-Length: 16\r\n/,
         'Content-Length header is added');

    # Verify body is appended
    like($request, qr/\r\n\r\n\{"key": "value"\}$/,
         'Request body is appended');
};

# Test that hop-by-hop headers are filtered
subtest 'Hop-by-hop header filtering' => sub {
    my $handler = bless {
        pagecamelInfo => {
            lhost    => '192.168.1.1',
            lport    => 443,
            peerhost => '10.0.0.1',
            peerport => 54321,
            usessl   => 1,
            pid      => $$,
        },
    }, 'PageCamel::CMDLine::WebFrontend::HTTP2Handler';

    my $headers = [
        ':method',           'GET',
        ':scheme',           'https',
        ':path',             '/',
        ':authority',        'example.com',
        'connection',        'keep-alive',      # Should be filtered
        'keep-alive',        'timeout=5',       # Should be filtered
        'transfer-encoding', 'chunked',         # Should be filtered
        'upgrade',           'websocket',       # Should be filtered
        'x-custom-header',   'custom-value',    # Should be preserved
    ];

    my $request = $handler->translateRequest(1, $headers, undef);

    # These should NOT be in the output
    unlike($request, qr/connection:/i,
           'Connection header is filtered');
    unlike($request, qr/keep-alive:/i,
           'Keep-Alive header is filtered');
    unlike($request, qr/transfer-encoding:/i,
           'Transfer-Encoding header is filtered');
    unlike($request, qr/upgrade:/i,
           'Upgrade header is filtered');

    # Custom header should be preserved
    like($request, qr/x-custom-header: custom-value/i,
         'Custom headers are preserved');
};

done_testing();
