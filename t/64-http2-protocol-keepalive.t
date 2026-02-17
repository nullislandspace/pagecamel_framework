use strict;
use warnings;
use Test::More;

plan skip_all => 'Author tests. Set TEST_HTTP2=1 to run.' unless $ENV{TEST_HTTP2};

use PageCamel::Protocol::HTTP2::Client;
use PageCamel::Protocol::HTTP2::Server;
use PageCamel::Protocol::HTTP2::Constants qw(:errors);
use lib 't/lib';
use PH2Test qw(fake_connect);

my %common = (
    ':scheme'    => 'https',
    ':authority' => 'localhost:8000',
    ':path'      => '/',
    ':method'    => 'GET',
    headers      => [],
);

subtest 'sequential requests' => sub {

    my $tests = 10;
    plan tests => $tests;

    my $server;
    $server = PageCamel::Protocol::HTTP2::Server->new(
        on_request => sub {
            $server->response_stream(
                ':status' => 204,
                stream_id => shift,
                headers   => [],
            );
        },
    );

    my $client = PageCamel::Protocol::HTTP2::Client->new;

    my $req;
    $req = sub {
        return if --$tests < 0;
        pass "request $tests";
        $client->request( %common, on_done => $req );
    };
    $req->();

    fake_connect( $server, $client );
};

subtest 'client keepalive' => sub {

    my $tests = 10;
    plan tests => $tests + 2;

    my $server;
    $server = PageCamel::Protocol::HTTP2::Server->new(
        on_request => sub {
            $server->response_stream(
                ':status' => 204,
                stream_id => shift,
                headers   => [],
            );
        },
    );

    my $client = PageCamel::Protocol::HTTP2::Client->new->keepalive(1);

    for my $i ( 1 .. $tests ) {
        $client->request(
            %common,
            on_done => sub {
                pass "request $i";
            },
        );
        fake_connect( $server, $client );
    }

    $client->close;
    fake_connect( $server, $client );

    eval { $client->request(%common); };
    ok $@, "request failed after close";
    like $@, qr/closed/, "connection closed";
};

subtest 'client no keepalive' => sub {

    plan tests => 2;

    my $server;
    $server = PageCamel::Protocol::HTTP2::Server->new(
        on_request => sub {
            $server->response_stream(
                ':status' => 204,
                stream_id => shift,
                headers   => [],
            );
        },
    );

    my $client = PageCamel::Protocol::HTTP2::Client->new(
        keepalive => 0,
        on_error  => sub {
            is( shift, PROTOCOL_ERROR, "request failed" );
        },
    );

    $client->request(
        %common,
        on_done => sub {
            pass "request complete";
        },
    );
    fake_connect( $server, $client );

    $client->request(
        %common,
        on_done => sub {
            fail "keepalive?";
        }
    );
    fake_connect( $server, $client );
};

done_testing;
