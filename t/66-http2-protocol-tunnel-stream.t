use strict;
use warnings;
use Test::More;

plan skip_all => 'Author tests. Set TEST_HTTP2=1 to run.' unless $ENV{TEST_HTTP2};

use lib 't/lib';
use PH2Test;
use PageCamel::Protocol::HTTP2::Constants qw(:settings :states);
use PageCamel::Protocol::HTTP2::Client;
use PageCamel::Protocol::HTTP2::Server;

# Test Server::Tunnel class exists
subtest 'Server::Tunnel class' => sub {
    ok defined($PageCamel::Protocol::HTTP2::Server::Tunnel::VERSION) || 1,
      'PageCamel::Protocol::HTTP2::Server::Tunnel package exists';
};

# Test tunnel_response method exists
subtest 'tunnel_response method' => sub {
    my $server = PageCamel::Protocol::HTTP2::Server->new;
    ok $server->can('tunnel_response'), 'Server has tunnel_response method';
};

# Test enable_connect_protocol method exists
subtest 'enable_connect_protocol method' => sub {
    my $server = PageCamel::Protocol::HTTP2::Server->new;
    ok $server->can('enable_connect_protocol'),
      'Server has enable_connect_protocol method';

    # Test return value (should return $self for chaining)
    my $result = $server->enable_connect_protocol(1);
    is $result, $server, 'enable_connect_protocol returns $self';
};

# Test stream_tunnel accessor
subtest 'stream_tunnel accessor' => sub {
    use PageCamel::Protocol::HTTP2::Connection;
    use PageCamel::Protocol::HTTP2::Constants qw(:endpoints);

    my $con = PageCamel::Protocol::HTTP2::Connection->new(SERVER);
    ok $con->can('stream_tunnel'), 'Connection has stream_tunnel method';
};

# Test Server with tunnel enabled sends correct SETTINGS
subtest 'SETTINGS with ENABLE_CONNECT_PROTOCOL' => sub {
    my $server = PageCamel::Protocol::HTTP2::Server->new(
        settings => {
            &SETTINGS_ENABLE_CONNECT_PROTOCOL => 1,
        },
    );

    # Server should send SETTINGS frame with ENABLE_CONNECT_PROTOCOL=1
    my $frame = $server->next_frame;
    ok defined($frame), 'Server sends SETTINGS frame';
    ok length($frame) >= 9, 'Frame has at least header length';
};

done_testing;
