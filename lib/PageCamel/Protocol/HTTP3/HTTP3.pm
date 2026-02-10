package PageCamel::Protocol::HTTP3; ## no critic (Modules::RequireFilenameMatchesPackage)
#---AUTOPRAGMASTART---
use v5.42;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 5.0;
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use XSLoader;
XSLoader::load('PageCamel::Protocol::HTTP3', $VERSION);

=head1 NAME

PageCamel::Protocol::HTTP3 - Unified HTTP/3 library with C-to-C ngtcp2/nghttp3 wiring

=head1 SYNOPSIS

    use PageCamel::Protocol::HTTP3;

    # Initialize library (once at startup)
    PageCamel::Protocol::HTTP3::init();

    # Create server connection
    my $conn = PageCamel::Protocol::HTTP3::Connection->new_server(
        dcid => $client_dcid,
        scid => $our_scid,
        local_addr => '0.0.0.0',
        local_port => 443,
        remote_addr => $client_ip,
        remote_port => $client_port,
        ssl_domains => {
            'example.com' => {
                sslcert => '/path/to/cert.pem',
                sslkey => '/path/to/key.pem',
                internal_socket => '/run/backend.sock',
            },
        },
        default_domain => 'example.com',
        on_send_packet => sub($data, $addr, $port) { ... },
        on_request => sub($stream_id, $headers_ref, $body, $is_connect) { ... },
        on_stream_close => sub($stream_id, $error_code) { ... },
    );

    # Process incoming UDP packet
    $conn->process_packet($udp_data, $remote_addr, $remote_port);

    # Flush outgoing packets
    $conn->flush_packets();

    # Send response
    $conn->send_response($stream_id, 200, ['content-type', 'text/html'], $body);

    # Cleanup (once at shutdown)
    PageCamel::Protocol::HTTP3::cleanup();

=head1 DESCRIPTION

This module provides a unified HTTP/3 implementation that integrates ngtcp2
(QUIC) and nghttp3 (HTTP/3) with direct C-to-C callback wiring.

The key improvement over the previous implementation is that all internal
communication between ngtcp2 and nghttp3 happens entirely in C. Only the
final application callbacks (on_request, on_stream_close, send_packet) cross
the Perl/XS boundary.

This eliminates the data corruption issues caused by Perl/XS trampolines in
the critical read_data callback path, where nghttp3 caches pointers that
must remain valid until acknowledged.

=head1 LIBRARY FUNCTIONS

=head2 init()

    my $rv = PageCamel::Protocol::HTTP3::init();

Initialize the HTTP/3 library. Call once at application startup.
Returns H3_OK (0) on success.

=head2 cleanup()

    PageCamel::Protocol::HTTP3::cleanup();

Clean up the HTTP/3 library. Call once at application shutdown.

=head2 version()

    my $version = PageCamel::Protocol::HTTP3::version();

Returns the library version string.

=head2 timestamp_ns()

    my $ts = PageCamel::Protocol::HTTP3::timestamp_ns();

Returns the current timestamp in nanoseconds (monotonic clock).

=head2 strerror($code)

    my $msg = PageCamel::Protocol::HTTP3::strerror($error_code);

Convert an error code to a human-readable string.

=head1 CONSTANTS

=head2 Return Codes

    H3_OK           # Success (0)
    H3_WOULDBLOCK   # Would block (1)
    H3_ERROR        # General error (-1)
    H3_ERROR_NOMEM  # Out of memory (-2)
    H3_ERROR_INVALID # Invalid argument (-3)
    H3_ERROR_TLS    # TLS error (-4)
    H3_ERROR_QUIC   # QUIC error (-5)
    H3_ERROR_HTTP3  # HTTP/3 error (-6)
    H3_ERROR_STREAM # Stream error (-7)
    H3_ERROR_CLOSED # Connection closed (-8)

=head1 CONNECTION CLASS

=head2 PageCamel::Protocol::HTTP3::Connection->new_server(%config)

Create a new server connection.

Required parameters:

=over 4

=item dcid - Client's Destination Connection ID (binary string)

=item scid - Our Source Connection ID (binary string)

=item local_addr - Local IP address string

=item local_port - Local port number

=item remote_addr - Remote IP address string

=item remote_port - Remote port number

=item ssl_domains - Hash of domain configurations

=item default_domain - Default domain name

=back

Optional parameters:

=over 4

=item default_backend - Default backend socket path

=item initial_max_data - Initial connection flow control limit

=item initial_max_stream_data_bidi - Initial stream flow control limit

=item initial_max_streams_bidi - Maximum bidirectional streams

=item max_idle_timeout_ms - Idle timeout in milliseconds

=item cc_algo - Congestion control algorithm (0=RENO, 1=CUBIC, 2=BBR, 3=BBR2)

=item enable_debug - Enable debug logging

=item on_send_packet - Callback for sending UDP packets

=item on_request - Callback when a complete request is received

=item on_request_body - Callback for streaming request body data

=item on_stream_close - Callback when a stream is closed

=back

=head2 $conn->process_packet($data, $remote_addr, $remote_port)

Process an incoming UDP packet. Returns H3_OK on success or an error code.

=head2 $conn->flush_packets()

Generate and send outgoing packets via the send_packet callback.
Returns the number of packets sent or an error code.

=head2 $conn->get_timeout_ms()

Get the timeout in milliseconds until the next required processing.

=head2 $conn->handle_timeout()

Handle timeout expiry. Returns H3_OK on success or an error code.

=head2 $conn->send_response($stream_id, $status, \@headers, $body)

Send a complete HTTP response with headers and body.

=head2 $conn->send_response_headers($stream_id, $status, \@headers, $has_body)

Send response headers. Set $has_body to 1 if body data will follow.

=head2 $conn->send_response_body($stream_id, $data, $eof)

Send response body data. Set $eof to 1 for the final chunk.

=head2 $conn->get_hostname()

Get the negotiated hostname (from SNI).

=head2 $conn->get_backend()

Get the selected backend socket path for the negotiated domain.

=head2 $conn->is_handshake_complete()

Returns true if the QUIC handshake is complete.

=head2 $conn->is_closing()

Returns true if the connection is closing or draining.

=head2 $conn->close_stream($stream_id, $error_code)

Close a stream with an error code.

=head2 $conn->get_stream_buffer_size($stream_id)

Get the number of buffered bytes for a stream's response body.

=head1 CALLBACKS

=head2 on_send_packet($data, $remote_addr, $remote_port)

Called when a UDP packet needs to be sent.

=head2 on_request($stream_id, \@headers, $body, $is_connect)

Called when a complete HTTP request is received. The headers array contains
alternating name/value pairs. $is_connect is true for extended CONNECT
(WebSocket) requests.

=head2 on_request_body($stream_id, $data, $fin)

Called when request body data arrives (for streaming uploads). $fin is true
for the final chunk.

=head2 on_stream_close($stream_id, $error_code)

Called when a stream is closed.

=head1 AUTHOR

PageCamel Framework

=head1 LICENSE

MIT

=cut

1;
