#!/usr/bin/env perl
use v5.38;
use strict;
use warnings;
use Test::More;

plan skip_all => 'Author tests. Set TEST_HTTP3=1 to run.' unless $ENV{TEST_HTTP3};

# Test HTTP3Handler module

# Note: Full integration tests require a running QUIC connection
# and backend server. These tests verify module loading and
# translation method behavior via direct method calls.

# Check if HTTP3Handler can be loaded
use_ok('PageCamel::CMDLine::WebFrontend::HTTP3Handler');

# Test module compiles with required dependencies
use_ok('PageCamel::Protocol::HTTP3::Server');
use_ok('PageCamel::Protocol::HTTP3::QPACK::Encoder');
use_ok('PageCamel::Protocol::HTTP3::QPACK::Decoder');

# Test handler creation requires proper parameters
{
    eval {
        my $handler = PageCamel::CMDLine::WebFrontend::HTTP3Handler->new();
    };
    like($@, qr/quicConnection/, 'Requires quicConnection parameter');
}

{
    eval {
        my $handler = PageCamel::CMDLine::WebFrontend::HTTP3Handler->new(
            quicConnection => 'mock',
        );
    };
    like($@, qr/backendSocketPath/, 'Requires backendSocketPath parameter');
}

{
    eval {
        my $handler = PageCamel::CMDLine::WebFrontend::HTTP3Handler->new(
            quicConnection    => 'mock',
            backendSocketPath => '/tmp/test.sock',
        );
    };
    like($@, qr/pagecamelInfo/, 'Requires pagecamelInfo parameter');
}

# Create a mock handler for method testing
{
    my $handler = PageCamel::CMDLine::WebFrontend::HTTP3Handler->new(
        quicConnection    => 'mock',
        backendSocketPath => '/tmp/test.sock',
        pagecamelInfo     => {
            lhost    => '192.168.1.1',
            lport    => 443,
            peerhost => '10.0.0.1',
            peerport => 54321,
        },
    );

    ok($handler, 'Created handler with all required parameters');
    is(ref($handler), 'PageCamel::CMDLine::WebFrontend::HTTP3Handler', 'Correct class');
}

# Test translateRequest method
{
    my $handler = PageCamel::CMDLine::WebFrontend::HTTP3Handler->new(
        quicConnection    => 'mock',
        backendSocketPath => '/tmp/test.sock',
        pagecamelInfo     => {
            lhost    => '192.168.1.1',
            lport    => 443,
            peerhost => '10.0.0.1',
            peerport => 54321,
        },
    );

    my $request = $handler->translateRequest(
        4,  # streamId
        [
            ':method' => 'GET',
            ':scheme' => 'https',
            ':authority' => 'example.com',
            ':path' => '/test/path',
            'user-agent' => 'TestClient/1.0',
        ],
        undef,  # no body
    );

    ok($request, 'translateRequest returns content');
    # Note: PAGECAMEL overhead is now sent once per pooled connection (in createPooledBackend),
    # not per-request. This improves performance with connection pooling.
    unlike($request, qr/PAGECAMEL/, 'No PAGECAMEL overhead (sent per-connection now)');
    like($request, qr/GET \/test\/path HTTP\/1\.1/, 'Contains HTTP/1.1 request line');
    like($request, qr/Host: example\.com/, 'Contains Host header from :authority');
    like($request, qr/user-agent: TestClient\/1\.0/, 'Contains user-agent header');
}

# Test translateRequest with POST body
{
    my $handler = PageCamel::CMDLine::WebFrontend::HTTP3Handler->new(
        quicConnection    => 'mock',
        backendSocketPath => '/tmp/test.sock',
        pagecamelInfo     => {
            lhost    => '127.0.0.1',
            lport    => 8443,
            peerhost => '192.168.1.100',
            peerport => 12345,
        },
    );

    my $body = '{"key": "value"}';
    my $request = $handler->translateRequest(
        8,  # streamId
        [
            ':method' => 'POST',
            ':scheme' => 'https',
            ':authority' => 'api.example.com',
            ':path' => '/api/v1/data',
            'content-type' => 'application/json',
        ],
        $body,
    );

    ok($request, 'translateRequest with body returns content');
    like($request, qr/POST \/api\/v1\/data HTTP\/1\.1/, 'Contains POST request line');
    # POST without Content-Length uses chunked encoding for backend
    like($request, qr/Transfer-Encoding: chunked/, 'Contains Transfer-Encoding: chunked header');
    # Body is chunked: hex_size\r\ndata\r\n (16 bytes = 0x10)
    like($request, qr/10\r\n\{"key": "value"\}\r\n$/, 'Contains body as chunked data');
}

# Test translateWebsocketUpgrade method
{
    my $handler = PageCamel::CMDLine::WebFrontend::HTTP3Handler->new(
        quicConnection    => 'mock',
        backendSocketPath => '/tmp/test.sock',
        pagecamelInfo     => {
            lhost    => '10.0.0.1',
            lport    => 443,
            peerhost => '172.16.0.1',
            peerport => 33333,
        },
    );

    my $request = $handler->translateWebsocketUpgrade(
        12,  # streamId
        [
            ':method' => 'CONNECT',
            ':protocol' => 'websocket',
            ':scheme' => 'https',
            ':authority' => 'ws.example.com',
            ':path' => '/socket',
            'sec-websocket-protocol' => 'chat',
        ],
    );

    ok($request, 'translateWebsocketUpgrade returns content');
    # Note: PAGECAMEL overhead is now sent once per pooled connection (in createPooledBackend),
    # not per-request. This improves performance with connection pooling.
    unlike($request, qr/PAGECAMEL/, 'No PAGECAMEL overhead (sent per-connection now)');
    like($request, qr/GET \/socket HTTP\/1\.1/, 'Contains GET request (not CONNECT)');
    like($request, qr/Host: ws\.example\.com/, 'Contains Host header');
    like($request, qr/Upgrade: websocket/, 'Contains Upgrade header');
    like($request, qr/Connection: Upgrade/, 'Contains Connection header');
    like($request, qr/Sec-WebSocket-Key:/, 'Contains Sec-WebSocket-Key');
    like($request, qr/Sec-WebSocket-Version: 13/, 'Contains Sec-WebSocket-Version');
}

# Test initial state of handler
{
    my $handler = PageCamel::CMDLine::WebFrontend::HTTP3Handler->new(
        quicConnection    => 'mock',
        backendSocketPath => '/tmp/test.sock',
        pagecamelInfo     => {
            lhost    => '0.0.0.0',
            lport    => 443,
            peerhost => '1.2.3.4',
            peerport => 99999,
        },
    );

    is(scalar(keys %{$handler->{streamBackends}}), 0, 'Initial streamBackends is empty');
    is(scalar(keys %{$handler->{streamResponses}}), 0, 'Initial streamResponses is empty');
    is(scalar(keys %{$handler->{streamStates}}), 0, 'Initial streamStates is empty');
    is($handler->{streamsHandled}, 0, 'Initial streamsHandled is 0');
}

# Test cleanupStream method
{
    my $handler = PageCamel::CMDLine::WebFrontend::HTTP3Handler->new(
        quicConnection    => 'mock',
        backendSocketPath => '/tmp/test.sock',
        pagecamelInfo     => {
            lhost    => '0.0.0.0',
            lport    => 443,
            peerhost => '5.6.7.8',
            peerport => 11111,
        },
    );

    # Add some mock state
    $handler->{streamBackends}->{4} = undef;
    $handler->{streamResponses}->{4} = 'some data';
    $handler->{streamStates}->{4} = 'waiting_response';
    $handler->{tobackendbuffers}->{4} = 'request data';

    # Clean up the stream
    $handler->cleanupStream(4);

    ok(!exists $handler->{streamBackends}->{4}, 'streamBackends cleaned');
    ok(!exists $handler->{streamResponses}->{4}, 'streamResponses cleaned');
    ok(!exists $handler->{streamStates}->{4}, 'streamStates cleaned');
    ok(!exists $handler->{tobackendbuffers}->{4}, 'tobackendbuffers cleaned');
}

# Test cleanup method (cleans all streams)
{
    my $handler = PageCamel::CMDLine::WebFrontend::HTTP3Handler->new(
        quicConnection    => 'mock',
        backendSocketPath => '/tmp/test.sock',
        pagecamelInfo     => {
            lhost    => '0.0.0.0',
            lport    => 443,
            peerhost => '9.10.11.12',
            peerport => 22222,
        },
    );

    # Add mock state for multiple streams
    for my $sid (4, 8, 12, 16) {
        $handler->{streamBackends}->{$sid} = undef;
        $handler->{streamStates}->{$sid} = 'active';
    }

    # Clean up all
    $handler->cleanup();

    is(scalar(keys %{$handler->{streamBackends}}), 0, 'All streamBackends cleaned');
    is(scalar(keys %{$handler->{streamStates}}), 0, 'All streamStates cleaned');
}

done_testing();
