package PageCamel::XS::NGTCP2::Stream;
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

# This package provides a high-level wrapper around QUIC stream operations.
# It wraps the stream-related methods from PageCamel::XS::NGTCP2::Connection.

sub new($class, %args) {
    my $self = bless {
        connection => $args{connection},
        stream_id  => $args{stream_id},
        state      => 'open',
        write_buffer => '',
        bytes_sent => 0,
        bytes_acked => 0,
    }, $class;
    return $self;
}

sub stream_id($self) {
    return $self->{stream_id};
}

sub connection($self) {
    return $self->{connection};
}

sub state($self) {
    return $self->{state};
}

sub write($self, $data, $timestamp) {
    return $self->{connection}->write_stream(
        $self->{stream_id},
        $data,
        $timestamp,
        0  # not fin
    );
}

sub write_fin($self, $data, $timestamp) {
    my $rv = $self->{connection}->write_stream(
        $self->{stream_id},
        $data,
        $timestamp,
        1  # fin
    );
    $self->{state} = 'half_closed_local' if $rv >= 0;
    return $rv;
}

sub close($self, $app_error_code = 0) {
    my $rv = $self->{connection}->shutdown_stream(
        $self->{stream_id},
        $app_error_code
    );
    $self->{state} = 'closed' if $rv >= 0;
    return $rv;
}

sub extend_flow_control($self, $datalen) {
    return $self->{connection}->extend_max_stream_offset(
        $self->{stream_id},
        $datalen
    );
}

sub is_open($self) {
    return $self->{state} eq 'open';
}

sub is_closed($self) {
    return $self->{state} eq 'closed';
}

sub is_bidi($self) {
    # In QUIC, bidirectional streams have stream IDs where (id & 0x2) == 0
    return ($self->{stream_id} & 0x2) == 0;
}

sub is_client_initiated($self) {
    # Client-initiated streams have (id & 0x1) == 0
    return ($self->{stream_id} & 0x1) == 0;
}

sub is_server_initiated($self) {
    return !$self->is_client_initiated();
}

1;

__END__

=head1 NAME

PageCamel::XS::NGTCP2::Stream - High-level QUIC stream wrapper

=head1 SYNOPSIS

    use PageCamel::XS::NGTCP2::Stream;

    # Create stream wrapper for an existing stream
    my $stream = PageCamel::XS::NGTCP2::Stream->new(
        connection => $quic_conn,
        stream_id  => $stream_id,
    );

    # Write data to stream
    $stream->write($data, $timestamp);

    # Write final data and close write side
    $stream->write_fin($final_data, $timestamp);

    # Close stream completely
    $stream->close();

=head1 DESCRIPTION

This class provides a high-level object-oriented wrapper around QUIC
stream operations. It simplifies stream management by tracking state
and providing convenient methods.

=head1 CONSTRUCTOR

=head2 new(%args)

Create a new stream wrapper.

Arguments:

=over 4

=item connection => $conn

The PageCamel::XS::NGTCP2::Connection object

=item stream_id => $id

The stream ID

=back

=head1 METHODS

=head2 stream_id()

Returns the stream ID.

=head2 connection()

Returns the underlying connection object.

=head2 state()

Returns the stream state: 'open', 'half_closed_local', 'half_closed_remote', 'closed'.

=head2 write($data, $timestamp)

Write data to the stream without closing it.

=head2 write_fin($data, $timestamp)

Write final data and close the write side of the stream.

=head2 close($app_error_code)

Close the stream with an application error code (default 0).

=head2 extend_flow_control($datalen)

Extend the stream's receive window by $datalen bytes.

=head2 is_open()

Returns true if the stream is open for both reading and writing.

=head2 is_closed()

Returns true if the stream is fully closed.

=head2 is_bidi()

Returns true if this is a bidirectional stream.

=head2 is_client_initiated()

Returns true if the stream was initiated by the client.

=head2 is_server_initiated()

Returns true if the stream was initiated by the server.

=head1 QUIC STREAM IDS

QUIC stream IDs encode information in the lowest 2 bits:

=over 4

=item Bit 0: Initiator (0 = client, 1 = server)

=item Bit 1: Direction (0 = bidirectional, 1 = unidirectional)

=back

=head1 SEE ALSO

L<PageCamel::XS::NGTCP2::Connection>, L<PageCamel::Protocol::QUIC::Server>

=cut
