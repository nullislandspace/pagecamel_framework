package PageCamel::XS::NGHTTP3::Server;
#---AUTOPRAGMASTART---
use v5.40;
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

# This package is defined in NGHTTP3.xs and provides the Perl-level
# interface to nghttp3_conn objects for server-side HTTP/3.
#
# Objects of this class are created via server_new() in the main
# PageCamel::XS::NGHTTP3 module.

1;

__END__

=head1 NAME

PageCamel::XS::NGHTTP3::Server - HTTP/3 server connection object

=head1 SYNOPSIS

    use PageCamel::XS::NGHTTP3;

    my $settings = PageCamel::XS::NGHTTP3::Settings->new();
    $settings->set_max_field_section_size(16384);
    $settings->set_enable_connect_protocol(1);

    my $h3 = PageCamel::XS::NGHTTP3::Connection->server_new(
        settings => $settings,
        on_recv_header => sub {
            my ($stream_id, $name, $value, $flags) = @_;
            print "Header: $name: $value\n";
            return 0;
        },
        on_end_headers => sub {
            my ($stream_id, $fin) = @_;
            print "Headers complete for stream $stream_id\n";
            return 0;
        },
        on_recv_data => sub {
            my ($stream_id, $data) = @_;
            print "Received " . length($data) . " bytes on stream $stream_id\n";
            return 0;
        },
        on_end_stream => sub {
            my ($stream_id) = @_;
            print "Stream $stream_id complete\n";
            return 0;
        },
    );

    # Bind control and QPACK streams
    $h3->bind_control_stream($control_stream_id);
    $h3->bind_qpack_encoder_stream($qpack_enc_stream_id);
    $h3->bind_qpack_decoder_stream($qpack_dec_stream_id);

    # Process incoming HTTP/3 data from QUIC
    my $rv = $h3->read_stream($stream_id, $data, $fin);

    # Get outgoing data for QUIC
    my ($out_data, $out_fin) = $h3->writev_stream($stream_id);

    # Submit response
    $h3->submit_response($stream_id, [
        ':status' => '200',
        'content-type' => 'text/html',
    ]);

=head1 DESCRIPTION

This class represents a server-side HTTP/3 connection managed by nghttp3.
It handles HTTP/3 framing and QPACK header compression over QUIC streams.

=head1 CONSTRUCTOR

=head2 server_new(%options)

Creates a new server-side HTTP/3 connection.

Optional options:

=over 4

=item settings => $settings

HTTP/3 settings (PageCamel::XS::NGHTTP3::Settings object)

=back

Callback options:

=over 4

=item on_recv_header => \&callback

Called for each received header. Receives: stream_id, name, value, flags.

=item on_end_headers => \&callback

Called when all headers are received. Receives: stream_id, fin.

=item on_recv_data => \&callback

Called when request body data is received. Receives: stream_id, data.

=item on_end_stream => \&callback

Called when the stream is complete. Receives: stream_id.

=item on_reset_stream => \&callback

Called when a stream is reset. Receives: stream_id, app_error_code.

=item on_stop_sending => \&callback

Called for STOP_SENDING. Receives: stream_id, app_error_code.

=back

=head1 METHODS

=head2 bind_control_stream($stream_id)

Bind the HTTP/3 control stream. Must be called during connection setup.

=head2 bind_qpack_encoder_stream($stream_id)

Bind the QPACK encoder stream.

=head2 bind_qpack_decoder_stream($stream_id)

Bind the QPACK decoder stream.

=head2 read_stream($stream_id, $data, $fin)

Process incoming HTTP/3 data from QUIC stream.

=head2 writev_stream($stream_id)

Get outgoing HTTP/3 data to write to QUIC.

Returns: ($data, $fin)

=head2 add_write_offset($stream_id, $n)

Acknowledge that $n bytes have been sent on the QUIC stream.

=head2 add_ack_offset($stream_id, $n)

Acknowledge that $n bytes have been received (for flow control).

=head2 submit_response($stream_id, \@headers)

Submit an HTTP/3 response. Headers should be a flat array:
    [':status' => '200', 'content-type' => 'text/html', ...]

=head2 submit_trailers($stream_id, \@headers)

Submit HTTP/3 trailers after the response body.

=head2 shutdown_stream_read($stream_id)

Stop reading from the stream.

=head2 shutdown_stream_write($stream_id)

Stop writing to the stream.

=head2 close_stream($stream_id, $app_error_code)

Close the stream with an error code.

=head2 resume_stream($stream_id)

Resume a blocked stream.

=head2 block_stream($stream_id)

Block a stream from processing.

=head2 unblock_stream($stream_id)

Unblock a previously blocked stream.

=head1 HTTP/3 STREAM TYPES

HTTP/3 uses different stream types:

=over 4

=item Control Stream (unidirectional)

Carries HTTP/3 control frames (SETTINGS, GOAWAY, etc.)

=item QPACK Encoder Stream (unidirectional)

Carries QPACK encoder instructions

=item QPACK Decoder Stream (unidirectional)

Carries QPACK decoder instructions

=item Request Streams (bidirectional)

Carry HTTP requests and responses

=back

=head1 SEE ALSO

L<PageCamel::XS::NGHTTP3>, L<PageCamel::XS::NGTCP2>,
L<PageCamel::Protocol::HTTP3::Server>

=cut
