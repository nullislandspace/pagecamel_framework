package PageCamel::XS::NGHTTP3;
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


require XSLoader;
XSLoader::load('PageCamel::XS::NGHTTP3', $VERSION);

# Export constants
use Exporter 'import';
our @EXPORT_OK = qw(
    NGHTTP3_QPACK_MAX_TABLE_CAPACITY
    NGHTTP3_QPACK_BLOCKED_STREAMS
    NGHTTP3_H3_NO_ERROR
    NGHTTP3_H3_GENERAL_PROTOCOL_ERROR
    NGHTTP3_H3_INTERNAL_ERROR
    NGHTTP3_H3_STREAM_CREATION_ERROR
    NGHTTP3_H3_CLOSED_CRITICAL_STREAM
    NGHTTP3_H3_FRAME_UNEXPECTED
    NGHTTP3_H3_FRAME_ERROR
    NGHTTP3_H3_EXCESSIVE_LOAD
    NGHTTP3_H3_ID_ERROR
    NGHTTP3_H3_SETTINGS_ERROR
    NGHTTP3_H3_MISSING_SETTINGS
    NGHTTP3_H3_REQUEST_REJECTED
    NGHTTP3_H3_REQUEST_CANCELLED
    NGHTTP3_H3_REQUEST_INCOMPLETE
    NGHTTP3_H3_MESSAGE_ERROR
    NGHTTP3_H3_CONNECT_ERROR
    NGHTTP3_H3_VERSION_FALLBACK
    NGHTTP3_ERR_INVALID_ARGUMENT
    NGHTTP3_ERR_NOBUF
    NGHTTP3_ERR_INVALID_STATE
    NGHTTP3_ERR_WOULDBLOCK
    NGHTTP3_ERR_STREAM_NOT_FOUND
    NGHTTP3_ERR_MALFORMED_HTTP_HEADER
    NGHTTP3_ERR_REMOVE_HTTP_HEADER
    NGHTTP3_ERR_MALFORMED_HTTP_MESSAGING
    NGHTTP3_ERR_QPACK_FATAL
    NGHTTP3_ERR_QPACK_HEADER_TOO_LARGE
    NGHTTP3_ERR_IGNORE_STREAM
    NGHTTP3_ERR_CONN_CLOSING
    NGHTTP3_ERR_QPACK_DECOMPRESSION_FAILED
    NGHTTP3_ERR_QPACK_ENCODER_STREAM_ERROR
    NGHTTP3_ERR_QPACK_DECODER_STREAM_ERROR
    NGHTTP3_ERR_H3_FRAME_UNEXPECTED
    NGHTTP3_ERR_H3_FRAME_ERROR
    NGHTTP3_ERR_H3_MISSING_SETTINGS
    NGHTTP3_ERR_H3_INTERNAL_ERROR
    NGHTTP3_ERR_H3_CLOSED_CRITICAL_STREAM
    NGHTTP3_ERR_H3_GENERAL_PROTOCOL_ERROR
    NGHTTP3_ERR_H3_ID_ERROR
    NGHTTP3_ERR_H3_SETTINGS_ERROR
    NGHTTP3_ERR_H3_STREAM_CREATION_ERROR
    NGHTTP3_ERR_H3_MESSAGE_ERROR
    NGHTTP3_ERR_NOMEM
    NGHTTP3_ERR_CALLBACK_FAILURE
);

our %EXPORT_TAGS = (
    constants => \@EXPORT_OK,
    all => \@EXPORT_OK,
);

1;

__END__

=head1 NAME

PageCamel::XS::NGHTTP3 - XS bindings for nghttp3 HTTP/3 library

=head1 SYNOPSIS

    use PageCamel::XS::NGHTTP3 qw(:constants);
    use PageCamel::XS::NGTCP2;

    # Create HTTP/3 settings
    my $settings = PageCamel::XS::NGHTTP3::Settings->new();
    $settings->set_max_field_section_size(16384);

    # Create HTTP/3 server connection
    my $http3 = PageCamel::XS::NGHTTP3::Connection->server_new(
        quic_conn => $quic_conn,
        settings  => $settings,
        on_recv_header => sub {
            my ($stream_id, $name, $value, $flags) = @_;
            # Process header
            return 0;
        },
        on_end_headers => sub {
            my ($stream_id) = @_;
            # Headers complete
            return 0;
        },
        on_recv_data => sub {
            my ($stream_id, $data) = @_;
            # Process request body
            return 0;
        },
        on_end_stream => sub {
            my ($stream_id) = @_;
            # Request complete
            return 0;
        },
    );

    # Submit response
    my @headers = (
        ':status' => '200',
        'content-type' => 'text/html',
        'content-length' => length($body),
    );
    $http3->submit_response($stream_id, \@headers);

    # Send response body
    $http3->submit_body($stream_id, $body, 1);  # 1 = fin

=head1 DESCRIPTION

This module provides XS bindings to the nghttp3 HTTP/3 library, enabling
HTTP/3 protocol support in the PageCamel web framework.

nghttp3 is an HTTP/3 implementation in C, created by Tatsuhiro Tsujikawa.
It provides QPACK header compression and HTTP/3 framing over QUIC streams.

=head1 CLASSES

=head2 PageCamel::XS::NGHTTP3::Connection

Represents an HTTP/3 connection. See L<PageCamel::XS::NGHTTP3::Server>.

=head2 PageCamel::XS::NGHTTP3::Settings

HTTP/3 connection settings.

=head1 FUNCTIONS

=head2 version()

    my $ver = PageCamel::XS::NGHTTP3::version();

Returns the nghttp3 library version string.

=head1 CONSTANTS

=head2 HTTP/3 Error Codes

=over 4

=item NGHTTP3_H3_NO_ERROR - No error

=item NGHTTP3_H3_GENERAL_PROTOCOL_ERROR - General protocol error

=item NGHTTP3_H3_INTERNAL_ERROR - Internal error

=item NGHTTP3_H3_STREAM_CREATION_ERROR - Stream creation error

=item NGHTTP3_H3_CLOSED_CRITICAL_STREAM - Critical stream closed

=item NGHTTP3_H3_FRAME_UNEXPECTED - Unexpected frame

=item NGHTTP3_H3_FRAME_ERROR - Frame error

=item NGHTTP3_H3_EXCESSIVE_LOAD - Excessive load

=item NGHTTP3_H3_ID_ERROR - ID error

=item NGHTTP3_H3_SETTINGS_ERROR - Settings error

=item NGHTTP3_H3_MISSING_SETTINGS - Missing settings

=item NGHTTP3_H3_REQUEST_REJECTED - Request rejected

=item NGHTTP3_H3_REQUEST_CANCELLED - Request cancelled

=item NGHTTP3_H3_REQUEST_INCOMPLETE - Request incomplete

=item NGHTTP3_H3_MESSAGE_ERROR - Message error

=item NGHTTP3_H3_CONNECT_ERROR - CONNECT error

=item NGHTTP3_H3_VERSION_FALLBACK - Version fallback

=back

=head2 Library Error Codes

See nghttp3 documentation for the full list.

=head1 SEE ALSO

L<PageCamel::XS::NGTCP2>, L<PageCamel::Protocol::HTTP3::Server>,
L<https://github.com/ngtcp2/nghttp3>

=head1 AUTHOR

PageCamel Framework

=head1 LICENSE

MIT License

=cut
