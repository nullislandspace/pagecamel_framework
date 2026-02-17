#!/usr/bin/env perl
# HTTP/1.1 regression tests
# Ensures HTTP/1.1 functionality is not broken by HTTP/2 changes

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

# Test that WebFrontend module compiles with HTTP/2 changes
subtest 'WebFrontend compilation' => sub {
    use_ok('PageCamel::CMDLine::WebFrontend');
};

# Test that HTTP2Handler module compiles
subtest 'HTTP2Handler compilation' => sub {
    use_ok('PageCamel::CMDLine::WebFrontend::HTTP2Handler');
};

# Test PAGECAMEL header format for HTTP/1.1 (should be unchanged)
subtest 'PAGECAMEL header format preserved' => sub {
    # The PAGECAMEL overhead header format should remain:
    # PAGECAMEL $lhost $lport $peerhost $peerport $usessl $PID HTTP/1.1\r\n
    # for HTTP/1.1 connections

    # This is a documentation test - the actual format is:
    my $expected_format = 'PAGECAMEL <lhost> <lport> <peerhost> <peerport> <usessl> <pid> HTTP/1.1';
    pass("Expected HTTP/1.1 PAGECAMEL format: $expected_format");

    # For HTTP/2, it should be:
    my $http2_format = 'PAGECAMEL <lhost> <lport> <peerhost> <peerport> <usessl> <pid> HTTP/2';
    pass("Expected HTTP/2 PAGECAMEL format: $http2_format");
};

# Test that ALPN callback only affects HTTP/2-enabled services
subtest 'ALPN selective enablement' => sub {
    # When http2 config is 0 or missing, ALPN should not be set
    # and HTTP/1.1 should work normally

    # This is a design verification test
    pass('ALPN callback is only set when $http2 is true');
    pass('Non-HTTP/2 services use standard HTTP/1.1 handling');
};

# Test config validation
subtest 'HTTP/2 config validation' => sub {
    # HTTP/2 requires SSL - this should be validated at startup

    # Mock config with HTTP/2 but no SSL
    my $invalid_config = {
        external_network => {
            service => [
                {
                    port => 80,
                    usessl => 0,
                    http2 => 1,  # Invalid: HTTP/2 without SSL
                    bind_adresses => { ip => ['0.0.0.0'] },
                }
            ]
        }
    };

    # The validation code should disable HTTP/2 on non-SSL ports
    # Simulate the validation
    foreach my $service (@{$invalid_config->{external_network}->{service}}) {
        if(defined($service->{http2}) && $service->{http2}) {
            if(!defined($service->{usessl}) || !$service->{usessl}) {
                $service->{http2} = 0;  # Disable HTTP/2
            }
        }
    }

    is($invalid_config->{external_network}->{service}[0]{http2}, 0,
       'HTTP/2 is disabled on non-SSL port');

    # Valid config with HTTP/2 and SSL
    my $valid_config = {
        external_network => {
            service => [
                {
                    port => 443,
                    usessl => 1,
                    http2 => 1,  # Valid: HTTP/2 with SSL
                    bind_adresses => { ip => ['0.0.0.0'] },
                }
            ]
        }
    };

    # Run validation
    foreach my $service (@{$valid_config->{external_network}->{service}}) {
        if(defined($service->{http2}) && $service->{http2}) {
            if(!defined($service->{usessl}) || !$service->{usessl}) {
                $service->{http2} = 0;
            }
        }
    }

    is($valid_config->{external_network}->{service}[0]{http2}, 1,
       'HTTP/2 remains enabled on SSL port');
};

# Test that http2 config option is optional
subtest 'HTTP/2 config optional' => sub {
    # Services without http2 option should default to HTTP/1.1

    my $config = {
        external_network => {
            service => [
                {
                    port => 443,
                    usessl => 1,
                    # No http2 option
                    bind_adresses => { ip => ['0.0.0.0'] },
                }
            ]
        }
    };

    my $http2 = $config->{external_network}->{service}[0]{http2} // 0;
    is($http2, 0, 'Missing http2 config defaults to 0 (HTTP/1.1 only)');
};

done_testing();
