package PageCamel::XS::NGTCP2::Connection;
use v5.38;
use strict;
use warnings;

# This package is defined in NGTCP2.xs and provides the Perl-level
# interface to ngtcp2_conn objects.
#
# Objects of this class are created via server_new() in the main
# PageCamel::XS::NGTCP2 module.

1;

__END__

=head1 NAME

PageCamel::XS::NGTCP2::Connection - QUIC connection object

=head1 SYNOPSIS

    use PageCamel::XS::NGTCP2;

    my $conn = PageCamel::XS::NGTCP2::Connection->server_new(
        dcid     => $dcid,
        scid     => $scid,
        path     => $path,
        version  => PageCamel::XS::NGTCP2::NGTCP2_PROTO_VER_V1(),
        settings => $settings,
        params   => $params,
        on_recv_stream_data => sub {
            my ($stream_id, $offset, $data, $flags) = @_;
            # Handle incoming stream data
            return 0;
        },
        on_stream_open => sub {
            my ($stream_id) = @_;
            # Handle new stream
            return 0;
        },
        on_stream_close => sub {
            my ($stream_id, $app_error_code, $flags) = @_;
            # Handle stream close
            return 0;
        },
        on_handshake_completed => sub {
            # Handshake completed
            return 0;
        },
        on_path_validation => sub {
            my ($result, $flags) = @_;
            # Path validation result
            return 0;
        },
    );

    # Process incoming packet
    my $rv = $conn->read_pkt($path, $packet_data, $timestamp);

    # Write outgoing packets
    my @packets = $conn->write_pkt($timestamp);

    # Check expiry
    my $expiry = $conn->get_expiry();

=head1 DESCRIPTION

This class represents a QUIC connection managed by ngtcp2. It provides
methods for:

=over 4

=item * Processing incoming packets

=item * Generating outgoing packets

=item * Managing streams (open, write, close)

=item * Handling connection lifecycle events

=item * Connection migration

=back

=head1 CONSTRUCTOR

=head2 server_new(%options)

Creates a new server-side QUIC connection.

Required options:

=over 4

=item dcid => $cid

Destination connection ID (PageCamel::XS::NGTCP2::CID object)

=item scid => $cid

Source connection ID (PageCamel::XS::NGTCP2::CID object)

=item path => $path

Network path (PageCamel::XS::NGTCP2::Path object)

=item settings => $settings

Connection settings (PageCamel::XS::NGTCP2::Settings object)

=item params => $params

Transport parameters (PageCamel::XS::NGTCP2::TransportParams object)

=back

Optional callback options:

=over 4

=item on_recv_stream_data => \&callback

Called when stream data is received. Receives: stream_id, offset, data, flags.

=item on_stream_open => \&callback

Called when a new stream is opened. Receives: stream_id.

=item on_stream_close => \&callback

Called when a stream is closed. Receives: stream_id, app_error_code, flags.

=item on_handshake_completed => \&callback

Called when the QUIC handshake completes.

=item on_path_validation => \&callback

Called with path validation results. Receives: result, flags.

=back

=head1 METHODS

=head2 read_pkt($path, $data, $timestamp)

Process an incoming QUIC packet.

Returns 0 on success, negative error code on failure.

=head2 write_pkt($timestamp)

Generate outgoing QUIC packets.

Returns list of packet data to send.

=head2 get_expiry()

Get the next timeout timestamp in nanoseconds.

=head2 handle_expiry($timestamp)

Handle timeout. Call this when the expiry time has passed.

=head2 is_handshake_completed()

Returns true if the QUIC handshake has completed.

=head2 is_in_closing_period()

Returns true if the connection is in the closing state.

=head2 is_in_draining_period()

Returns true if the connection is in the draining state.

=head2 open_bidi_stream()

Open a new bidirectional stream.

Returns stream ID on success, negative error code on failure.

=head2 open_uni_stream()

Open a new unidirectional stream.

Returns stream ID on success, negative error code on failure.

=head2 write_stream($stream_id, $data, $timestamp, $fin)

Write data to a stream.

Set $fin to 1 to indicate end of stream.

Returns bytes written or negative error code.

=head2 shutdown_stream($stream_id, $app_error_code)

Shutdown a stream with the given application error code.

=head2 extend_max_stream_offset($stream_id, $datalen)

Extend the stream's flow control window.

=head2 extend_max_offset($datalen)

Extend the connection's flow control window.

=head2 initiate_migration($path, $timestamp)

Initiate connection migration to a new network path.

=head2 get_num_scid()

Get the number of source connection IDs.

=head2 get_negotiated_version()

Get the negotiated QUIC version.

=head1 SEE ALSO

L<PageCamel::XS::NGTCP2>, L<PageCamel::Protocol::QUIC::Server>

=cut
