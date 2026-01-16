package PageCamel::XS::NGTCP2;
use v5.38;
use strict;
use warnings;

our $VERSION = '0.01';

require XSLoader;
XSLoader::load('PageCamel::XS::NGTCP2', $VERSION);

# Export constants
use Exporter 'import';
our @EXPORT_OK = qw(
    NGTCP2_PROTO_VER_V1
    NGTCP2_PROTO_VER_V2
    NGTCP2_MAX_CIDLEN
    NGTCP2_MIN_CIDLEN
    NGTCP2_MAX_UDP_PAYLOAD_SIZE
    NGTCP2_DEFAULT_MAX_RECV_UDP_PAYLOAD_SIZE
    NGTCP2_DEFAULT_ACK_DELAY_EXPONENT
    NGTCP2_DEFAULT_MAX_ACK_DELAY
    NGTCP2_DEFAULT_ACTIVE_CONNECTION_ID_LIMIT
    NGTCP2_TLSEXT_QUIC_TRANSPORT_PARAMETERS_V1
    NGTCP2_ERR_INVALID_ARGUMENT
    NGTCP2_ERR_NOBUF
    NGTCP2_ERR_PROTO
    NGTCP2_ERR_INVALID_STATE
    NGTCP2_ERR_ACK_FRAME
    NGTCP2_ERR_STREAM_ID_BLOCKED
    NGTCP2_ERR_STREAM_IN_USE
    NGTCP2_ERR_STREAM_DATA_BLOCKED
    NGTCP2_ERR_FLOW_CONTROL
    NGTCP2_ERR_CONNECTION_ID_LIMIT
    NGTCP2_ERR_STREAM_LIMIT
    NGTCP2_ERR_FINAL_SIZE
    NGTCP2_ERR_CRYPTO
    NGTCP2_ERR_PKT_NUM_EXHAUSTED
    NGTCP2_ERR_REQUIRED_TRANSPORT_PARAM
    NGTCP2_ERR_MALFORMED_TRANSPORT_PARAM
    NGTCP2_ERR_FRAME_ENCODING
    NGTCP2_ERR_DECRYPT
    NGTCP2_ERR_STREAM_SHUT_WR
    NGTCP2_ERR_STREAM_NOT_FOUND
    NGTCP2_ERR_STREAM_STATE
    NGTCP2_ERR_RECV_VERSION_NEGOTIATION
    NGTCP2_ERR_CLOSING
    NGTCP2_ERR_DRAINING
    NGTCP2_ERR_TRANSPORT_PARAM
    NGTCP2_ERR_DISCARD_PKT
    NGTCP2_ERR_CONN_ID_BLOCKED
    NGTCP2_ERR_INTERNAL
    NGTCP2_ERR_CRYPTO_BUFFER_EXCEEDED
    NGTCP2_ERR_WRITE_MORE
    NGTCP2_ERR_RETRY
    NGTCP2_ERR_DROP_CONN
    NGTCP2_ERR_AEAD_LIMIT_REACHED
    NGTCP2_ERR_NO_VIABLE_PATH
    NGTCP2_ERR_VERSION_NEGOTIATION
    NGTCP2_ERR_HANDSHAKE_TIMEOUT
    NGTCP2_ERR_VERSION_NEGOTIATION_FAILURE
    NGTCP2_ERR_IDLE_CLOSE
    NGTCP2_CC_ALGO_RENO
    NGTCP2_CC_ALGO_CUBIC
    NGTCP2_CC_ALGO_BBR
    NGTCP2_CC_ALGO_BBR2
);

our %EXPORT_TAGS = (
    constants => \@EXPORT_OK,
    all => \@EXPORT_OK,
);

# Congestion control algorithm constants
use constant {
    NGTCP2_CC_ALGO_RENO  => 0,
    NGTCP2_CC_ALGO_CUBIC => 1,
    NGTCP2_CC_ALGO_BBR   => 2,
    NGTCP2_CC_ALGO_BBR2  => 3,
};

1;

__END__

=head1 NAME

PageCamel::XS::NGTCP2 - XS bindings for ngtcp2 QUIC library

=head1 SYNOPSIS

    use PageCamel::XS::NGTCP2 qw(:constants);

    # Create QUIC connection settings
    my $settings = PageCamel::XS::NGTCP2::Settings->new();
    $settings->set_initial_ts(PageCamel::XS::NGTCP2::timestamp());

    # Create transport parameters
    my $params = PageCamel::XS::NGTCP2::TransportParams->new();
    $params->set_initial_max_streams_bidi(100);
    $params->set_initial_max_streams_uni(100);
    $params->set_initial_max_data(1048576);

    # Create server connection
    my $conn = PageCamel::XS::NGTCP2::Connection->server_new(
        dcid        => $dcid,
        scid        => $scid,
        path        => $path,
        version     => NGTCP2_PROTO_VER_V1,
        callbacks   => $callbacks,
        settings    => $settings,
        params      => $params,
        tls_native  => $ssl,
    );

=head1 DESCRIPTION

This module provides XS bindings to the ngtcp2 QUIC library, enabling
QUIC protocol support in the PageCamel web framework.

ngtcp2 is a QUIC protocol implementation in C, created by Tatsuhiro
Tsujikawa, the author of nghttp2. It powers curl's HTTP/3 support and
has been security audited.

=head1 CLASSES

=head2 PageCamel::XS::NGTCP2::Connection

Represents a QUIC connection. See L<PageCamel::XS::NGTCP2::Connection>.

=head2 PageCamel::XS::NGTCP2::Settings

Connection settings configuration. See L<PageCamel::XS::NGTCP2::Settings>.

=head2 PageCamel::XS::NGTCP2::TransportParams

QUIC transport parameters. See L<PageCamel::XS::NGTCP2::TransportParams>.

=head2 PageCamel::XS::NGTCP2::Path

Network path (local/remote address pair).

=head2 PageCamel::XS::NGTCP2::CID

QUIC Connection ID.

=head1 FUNCTIONS

=head2 timestamp()

    my $ts = PageCamel::XS::NGTCP2::timestamp();

Returns the current timestamp in nanoseconds, suitable for use with
ngtcp2 timing functions.

=head2 version()

    my $ver = PageCamel::XS::NGTCP2::version();

Returns the ngtcp2 library version string.

=head2 is_supported_version($version)

    if (PageCamel::XS::NGTCP2::is_supported_version(NGTCP2_PROTO_VER_V1)) {
        # Version is supported
    }

Returns true if the specified QUIC version is supported.

=head1 CONSTANTS

=head2 Protocol Versions

=over 4

=item NGTCP2_PROTO_VER_V1 - QUIC version 1 (RFC 9000)

=item NGTCP2_PROTO_VER_V2 - QUIC version 2 (RFC 9369)

=back

=head2 Connection ID Limits

=over 4

=item NGTCP2_MAX_CIDLEN - Maximum connection ID length (20 bytes)

=item NGTCP2_MIN_CIDLEN - Minimum connection ID length (1 byte)

=back

=head2 Error Codes

See the ngtcp2 documentation for a complete list of error codes.

=head1 SEE ALSO

L<PageCamel::Protocol::QUIC::Server>, L<PageCamel::XS::NGHTTP3>,
L<https://github.com/ngtcp2/ngtcp2>

=head1 AUTHOR

PageCamel Framework

=head1 LICENSE

MIT License

=cut
