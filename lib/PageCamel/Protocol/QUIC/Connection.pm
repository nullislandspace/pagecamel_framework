package PageCamel::Protocol::QUIC::Connection;
use v5.38;
use strict;
use warnings;

use PageCamel::XS::NGTCP2 qw(:constants);
use PageCamel::XS::NGTCP2::Stream;
use Carp qw(croak);
use Scalar::Util qw(weaken);

our $VERSION = '0.01';

sub new($class, %config) {
    my $self = bless {
        # Identity
        id             => $config{id} // croak("id required"),
        dcid           => $config{dcid} // croak("dcid required"),
        scid           => $config{scid} // croak("scid required"),

        # Network
        path           => $config{path} // croak("path required"),
        peer_addr      => $config{peer_addr},
        local_addr     => $config{local_addr},

        # TLS
        cert_file      => $config{cert_file},
        key_file       => $config{key_file},
        alpn_protocols => $config{alpn_protocols} // ['h3'],

        # Settings
        settings       => $config{settings},
        transport_params => $config{transport_params},
        enable_0rtt    => $config{enable_0rtt} // 1,

        # State
        state          => 'handshaking',  # handshaking, established, closing, closed
        connection_ids => [],
        streams        => {},
        pending_out    => [],

        # Parent server (weak ref to avoid circular reference)
        server         => undef,

        # Low-level connection handle
        quic_conn      => undef,

        # Callbacks
        on_stream_data  => $config{on_stream_data},
        on_stream_open  => $config{on_stream_open},
        on_stream_close => $config{on_stream_close},
        on_handshake    => $config{on_handshake},
        on_migration    => $config{on_migration},

        # Metrics
        bytes_sent     => 0,
        bytes_received => 0,
        packets_sent   => 0,
        packets_received => 0,
        streams_opened => 0,
        created_at     => time(),
    }, $class;

    if ($config{server}) {
        $self->{server} = $config{server};
        weaken($self->{server});
    }

    $self->_init_connection();

    return $self;
}

sub _init_connection($self) {
    # Create the low-level QUIC connection
    $self->{quic_conn} = PageCamel::XS::NGTCP2::Connection->server_new(
        dcid     => $self->{dcid},
        scid     => $self->{scid},
        path     => $self->{path},
        version  => NGTCP2_PROTO_VER_V1(),
        settings => $self->{settings},
        params   => $self->{transport_params},
        on_recv_stream_data => sub { $self->_on_recv_stream_data(@_) },
        on_stream_open => sub { $self->_on_stream_open(@_) },
        on_stream_close => sub { $self->_on_stream_close(@_) },
        on_handshake_completed => sub { $self->_on_handshake_completed(@_) },
        on_path_validation => sub { $self->_on_path_validation(@_) },
    );
}

# Accessors

sub id($self) { return $self->{id}; }
sub state($self) { return $self->{state}; }
sub peer_addr($self) { return $self->{peer_addr}; }
sub local_addr($self) { return $self->{local_addr}; }
sub is_established($self) { return $self->{state} eq 'established'; }
sub is_closing($self) { return $self->{state} eq 'closing'; }
sub is_closed($self) { return $self->{state} eq 'closed'; }

# Connection ID management

sub add_connection_id($self, $cid) {
    push @{$self->{connection_ids}}, $cid;
}

sub get_connection_ids($self) {
    return @{$self->{connection_ids}};
}

sub get_primary_cid($self) {
    return $self->{connection_ids}[0];
}

# Packet processing

sub process_packet($self, $packet, $peer_addr, $ts) {
    return if $self->is_closed();

    $self->{packets_received}++;
    $self->{bytes_received} += length($packet);

    # Check for path change (connection migration)
    if ($self->_addr_changed($peer_addr)) {
        if ($self->_handle_migration($peer_addr)) {
            $self->{peer_addr} = $peer_addr;
        }
    }

    # Process packet through ngtcp2
    my $rv = $self->{quic_conn}->read_pkt($self->{path}, $packet, $ts);

    if ($rv < 0) {
        # Error processing packet
        if ($rv == NGTCP2_ERR_DRAINING()) {
            $self->{state} = 'closing';
        } elsif ($rv == NGTCP2_ERR_CLOSING()) {
            $self->{state} = 'closing';
        } else {
            warn "QUIC: Error processing packet: " .
                 PageCamel::XS::NGTCP2::strerror($rv) . "\n";
        }
        return $rv;
    }

    return 0;
}

sub get_packets($self, $ts) {
    return if $self->is_closed();

    my @packets;

    # Get packets from ngtcp2
    my @pkt_data = $self->{quic_conn}->write_pkt($ts);

    for my $data (@pkt_data) {
        next unless defined $data && length($data);

        $self->{packets_sent}++;
        $self->{bytes_sent} += length($data);

        push @packets, {
            data      => $data,
            peer_addr => $self->{peer_addr},
        };
    }

    return @packets;
}

sub get_expiry($self) {
    return $self->{quic_conn}->get_expiry();
}

sub handle_expiry($self, $ts) {
    return if $self->is_closed();

    my $rv = $self->{quic_conn}->handle_expiry($ts);

    if ($rv < 0) {
        if ($rv == NGTCP2_ERR_IDLE_CLOSE()) {
            $self->close(0, 'idle timeout');
        } else {
            warn "QUIC: Timeout error: " .
                 PageCamel::XS::NGTCP2::strerror($rv) . "\n";
        }
    }

    # Check if connection is in closing/draining state
    if ($self->{quic_conn}->is_in_closing_period()) {
        $self->{state} = 'closing';
    }
    if ($self->{quic_conn}->is_in_draining_period()) {
        $self->{state} = 'closed';
    }
}

# Stream operations

sub open_stream($self) {
    return unless $self->is_established();

    my $stream_id = $self->{quic_conn}->open_bidi_stream();
    return if $stream_id < 0;

    my $stream = PageCamel::XS::NGTCP2::Stream->new(
        connection => $self->{quic_conn},
        stream_id  => $stream_id,
    );

    $self->{streams}{$stream_id} = $stream;
    $self->{streams_opened}++;

    return $stream;
}

sub get_stream($self, $stream_id) {
    return $self->{streams}{$stream_id};
}

sub write_stream($self, $stream_id, $data, $fin = 0) {
    return unless $self->is_established();

    my $ts = PageCamel::XS::NGTCP2::timestamp();
    return $self->{quic_conn}->write_stream($stream_id, $data, $ts, $fin);
}

sub close_stream($self, $stream_id, $error_code = 0) {
    return unless exists $self->{streams}{$stream_id};

    $self->{quic_conn}->shutdown_stream($stream_id, $error_code);
    delete $self->{streams}{$stream_id};
}

sub extend_stream_window($self, $stream_id, $size) {
    $self->{quic_conn}->extend_max_stream_offset($stream_id, $size);
}

sub extend_connection_window($self, $size) {
    $self->{quic_conn}->extend_max_offset($size);
}

# Connection control

sub close($self, $error_code = 0, $reason = '') {
    return if $self->is_closed();

    $self->{state} = 'closing';

    # Close all streams
    for my $stream_id (keys %{$self->{streams}}) {
        $self->close_stream($stream_id, $error_code);
    }
}

sub destroy($self) {
    $self->{state} = 'closed';
    $self->{quic_conn} = undef;
    $self->{streams} = {};
}

# Connection migration

sub initiate_migration($self, $new_path) {
    my $ts = PageCamel::XS::NGTCP2::timestamp();
    return $self->{quic_conn}->initiate_migration($new_path, $ts);
}

# Metrics

sub metrics($self) {
    return {
        id               => $self->{id},
        state            => $self->{state},
        bytes_sent       => $self->{bytes_sent},
        bytes_received   => $self->{bytes_received},
        packets_sent     => $self->{packets_sent},
        packets_received => $self->{packets_received},
        streams_opened   => $self->{streams_opened},
        active_streams   => scalar(keys %{$self->{streams}}),
        connection_ids   => scalar(@{$self->{connection_ids}}),
        created_at       => $self->{created_at},
        uptime           => time() - $self->{created_at},
        negotiated_version => $self->{quic_conn}->get_negotiated_version(),
    };
}

# Internal callback handlers

sub _on_recv_stream_data($self, $stream_id, $offset, $data, $flags) {
    my $fin = ($flags & 0x01) ? 1 : 0;

    # Create stream object if needed
    unless (exists $self->{streams}{$stream_id}) {
        my $stream = PageCamel::XS::NGTCP2::Stream->new(
            connection => $self->{quic_conn},
            stream_id  => $stream_id,
        );
        $self->{streams}{$stream_id} = $stream;
    }

    # Extend flow control window
    $self->extend_stream_window($stream_id, length($data));
    $self->extend_connection_window(length($data));

    # Notify callback
    if ($self->{on_stream_data}) {
        $self->{on_stream_data}->($self, $stream_id, $data, $fin);
    }

    return 0;
}

sub _on_stream_open($self, $stream_id) {
    $self->{streams_opened}++;

    if ($self->{on_stream_open}) {
        $self->{on_stream_open}->($self, $stream_id);
    }

    return 0;
}

sub _on_stream_close($self, $stream_id, $error_code, $flags) {
    delete $self->{streams}{$stream_id};

    if ($self->{on_stream_close}) {
        $self->{on_stream_close}->($self, $stream_id, $error_code);
    }

    return 0;
}

sub _on_handshake_completed($self) {
    $self->{state} = 'established';

    if ($self->{on_handshake}) {
        $self->{on_handshake}->($self);
    }

    return 0;
}

sub _on_path_validation($self, $result, $flags) {
    # Path validation completed (for connection migration)
    if ($result == 0) {  # Success
        if ($self->{on_migration}) {
            $self->{on_migration}->($self, undef, $self->{peer_addr});
        }
    }

    return 0;
}

sub _addr_changed($self, $new_addr) {
    return 0 unless $self->{peer_addr};
    return 0 unless $new_addr;

    return ($self->{peer_addr}{host} ne $new_addr->{host} ||
            $self->{peer_addr}{port} ne $new_addr->{port});
}

sub _handle_migration($self, $new_addr) {
    # Create new path for migration
    my $new_path = PageCamel::XS::NGTCP2::Path->new(
        $self->{local_addr}{host},
        $self->{local_addr}{port},
        $new_addr->{host},
        $new_addr->{port},
    );

    # Initiate migration
    return $self->initiate_migration($new_path) == 0;
}

1;

__END__

=head1 NAME

PageCamel::Protocol::QUIC::Connection - QUIC connection object

=head1 SYNOPSIS

    # Connections are typically created by PageCamel::Protocol::QUIC::Server

    # Process incoming packet
    $connection->process_packet($packet, $peer_addr, $timestamp);

    # Get outgoing packets
    for my $pkt ($connection->get_packets($timestamp)) {
        send_udp($pkt->{data}, $pkt->{peer_addr});
    }

    # Write to stream
    $connection->write_stream($stream_id, $data, $fin);

    # Close connection
    $connection->close(0, 'done');

=head1 DESCRIPTION

This class represents a single QUIC connection. It wraps the low-level
ngtcp2 connection handle and provides a higher-level interface for
stream management and packet processing.

=head1 METHODS

=head2 Accessors

=over 4

=item id() - Connection ID

=item state() - Connection state (handshaking, established, closing, closed)

=item peer_addr() - Remote address

=item local_addr() - Local address

=item is_established() - True if handshake completed

=item is_closing() - True if closing

=item is_closed() - True if closed

=back

=head2 Connection ID Management

=over 4

=item add_connection_id($cid) - Add a connection ID

=item get_connection_ids() - Get all connection IDs

=item get_primary_cid() - Get the primary connection ID

=back

=head2 Packet Processing

=over 4

=item process_packet($packet, $peer_addr, $ts) - Process incoming packet

=item get_packets($ts) - Get outgoing packets

=item get_expiry() - Get next timeout timestamp

=item handle_expiry($ts) - Handle timeout

=back

=head2 Stream Operations

=over 4

=item open_stream() - Open a new bidirectional stream

=item get_stream($stream_id) - Get a stream object

=item write_stream($stream_id, $data, $fin) - Write data to stream

=item close_stream($stream_id, $error_code) - Close a stream

=item extend_stream_window($stream_id, $size) - Extend stream flow control

=item extend_connection_window($size) - Extend connection flow control

=back

=head2 Connection Control

=over 4

=item close($error_code, $reason) - Close the connection

=item destroy() - Destroy the connection object

=item initiate_migration($new_path) - Initiate connection migration

=back

=head2 Metrics

=over 4

=item metrics() - Get connection metrics hash

=back

=head1 CALLBACKS

Set callbacks via the constructor:

=over 4

=item on_stream_data($conn, $stream_id, $data, $fin)

=item on_stream_open($conn, $stream_id)

=item on_stream_close($conn, $stream_id, $error_code)

=item on_handshake($conn)

=item on_migration($conn, $old_path, $new_path)

=back

=head1 SEE ALSO

L<PageCamel::Protocol::QUIC::Server>, L<PageCamel::XS::NGTCP2>

=cut
