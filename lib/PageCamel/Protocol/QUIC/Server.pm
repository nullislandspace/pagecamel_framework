package PageCamel::Protocol::QUIC::Server;
use v5.38;
use strict;
use warnings;

use PageCamel::XS::NGTCP2 qw(:constants);
use PageCamel::Protocol::QUIC::Connection;
use Time::HiRes qw(time);
use Carp qw(croak);

our $VERSION = '0.01';

sub new($class, %config) {
    my $self = bless {
        # Configuration
        cert_file          => $config{cert_file} // croak("cert_file required"),
        key_file           => $config{key_file} // croak("key_file required"),
        alpn_protocols     => $config{alpn_protocols} // ['h3'],
        max_connections    => $config{max_connections} // 1000,
        idle_timeout       => $config{idle_timeout} // 30_000_000_000,  # 30s in ns
        max_streams_bidi   => $config{max_streams_bidi} // 100,
        max_streams_uni    => $config{max_streams_uni} // 100,
        initial_max_data   => $config{initial_max_data} // 10_485_760,  # 10MB
        max_stream_data    => $config{max_stream_data} // 1_048_576,    # 1MB
        enable_0rtt        => $config{enable_0rtt} // 1,
        enable_migration   => $config{enable_migration} // 1,

        # State
        connections        => {},  # connection_id -> Connection object
        cid_to_connection  => {},  # all connection IDs -> Connection object
        next_conn_seq      => 1,

        # Callbacks
        on_connection      => $config{on_connection},
        on_request         => $config{on_request},
        on_stream_data     => $config{on_stream_data},
        on_stream_close    => $config{on_stream_close},
        on_connection_close => $config{on_connection_close},
        on_migration       => $config{on_migration},

        # Settings and transport params (created once)
        settings           => undef,
        transport_params   => undef,
    }, $class;

    $self->_init_settings();
    $self->_init_transport_params();

    return $self;
}

sub _init_settings($self) {
    $self->{settings} = PageCamel::XS::NGTCP2::Settings->new();
    $self->{settings}->set_initial_ts(PageCamel::XS::NGTCP2::timestamp());
    $self->{settings}->set_max_tx_udp_payload_size(1350);
}

sub _init_transport_params($self) {
    $self->{transport_params} = PageCamel::XS::NGTCP2::TransportParams->new();
    $self->{transport_params}->set_initial_max_streams_bidi($self->{max_streams_bidi});
    $self->{transport_params}->set_initial_max_streams_uni($self->{max_streams_uni});
    $self->{transport_params}->set_initial_max_data($self->{initial_max_data});
    $self->{transport_params}->set_initial_max_stream_data_bidi_local($self->{max_stream_data});
    $self->{transport_params}->set_initial_max_stream_data_bidi_remote($self->{max_stream_data});
    $self->{transport_params}->set_initial_max_stream_data_uni($self->{max_stream_data});
    $self->{transport_params}->set_max_idle_timeout($self->{idle_timeout});
    $self->{transport_params}->set_max_udp_payload_size(1350);
    $self->{transport_params}->set_active_connection_id_limit(8);
}

sub accept_connection($self, $initial_packet, $peer_addr, $local_addr) {
    # Extract connection IDs from initial packet
    my ($dcid, $scid) = $self->_parse_initial_packet($initial_packet);
    return unless $dcid && $scid;

    # Check connection limit
    if (scalar(keys %{$self->{connections}}) >= $self->{max_connections}) {
        warn "QUIC: Maximum connection limit reached\n";
        return;
    }

    # Generate server's source connection ID
    my $server_scid = $self->_generate_connection_id();

    # Create path
    my $path = PageCamel::XS::NGTCP2::Path->new(
        $local_addr->{host},
        $local_addr->{port},
        $peer_addr->{host},
        $peer_addr->{port},
    );

    # Create QUIC connection
    my $conn_id = $self->{next_conn_seq}++;
    my $connection = PageCamel::Protocol::QUIC::Connection->new(
        id              => $conn_id,
        server          => $self,
        dcid            => $dcid,
        scid            => $server_scid,
        path            => $path,
        peer_addr       => $peer_addr,
        local_addr      => $local_addr,
        settings        => $self->{settings},
        transport_params => $self->{transport_params},
        cert_file       => $self->{cert_file},
        key_file        => $self->{key_file},
        alpn_protocols  => $self->{alpn_protocols},
        enable_0rtt     => $self->{enable_0rtt},
        on_stream_data  => sub { $self->_on_stream_data(@_) },
        on_stream_open  => sub { $self->_on_stream_open(@_) },
        on_stream_close => sub { $self->_on_stream_close(@_) },
        on_handshake    => sub { $self->_on_handshake(@_) },
        on_migration    => sub { $self->_on_migration(@_) },
    );

    # Register connection
    $self->{connections}{$conn_id} = $connection;
    $self->_register_connection_id($dcid, $connection);
    $self->_register_connection_id($server_scid, $connection);

    # Process the initial packet
    my $ts = PageCamel::XS::NGTCP2::timestamp();
    $connection->process_packet($initial_packet, $peer_addr, $ts);

    # Notify callback
    if ($self->{on_connection}) {
        $self->{on_connection}->($connection);
    }

    return $connection;
}

sub process_packet($self, $packet, $peer_addr) {
    # Extract destination connection ID
    my $dcid = $self->_extract_dcid($packet);
    return unless $dcid;

    # Look up connection
    my $connection = $self->{cid_to_connection}{$dcid};
    unless ($connection) {
        # May be initial packet for new connection
        return $self->accept_connection($packet, $peer_addr, $self->{local_addr});
    }

    # Process packet on existing connection
    my $ts = PageCamel::XS::NGTCP2::timestamp();
    return $connection->process_packet($packet, $peer_addr, $ts);
}

sub get_packets($self) {
    my @packets;
    my $ts = PageCamel::XS::NGTCP2::timestamp();

    for my $connection (values %{$self->{connections}}) {
        push @packets, $connection->get_packets($ts);
    }

    return @packets;
}

sub handle_timeouts($self) {
    my $ts = PageCamel::XS::NGTCP2::timestamp();
    my @closed;

    for my $conn_id (keys %{$self->{connections}}) {
        my $connection = $self->{connections}{$conn_id};

        if ($connection->is_closed()) {
            push @closed, $conn_id;
            next;
        }

        my $expiry = $connection->get_expiry();
        if ($expiry <= $ts) {
            $connection->handle_expiry($ts);
        }
    }

    # Clean up closed connections
    for my $conn_id (@closed) {
        $self->_close_connection($conn_id);
    }
}

sub get_next_timeout($self) {
    my $min_expiry;

    for my $connection (values %{$self->{connections}}) {
        my $expiry = $connection->get_expiry();
        if (!defined $min_expiry || $expiry < $min_expiry) {
            $min_expiry = $expiry;
        }
    }

    return $min_expiry;
}

sub close_connection($self, $conn_id, $error_code = 0, $reason = '') {
    my $connection = $self->{connections}{$conn_id};
    return unless $connection;

    $connection->close($error_code, $reason);
    $self->_close_connection($conn_id);
}

sub connection_count($self) {
    return scalar(keys %{$self->{connections}});
}

sub get_connection($self, $conn_id) {
    return $self->{connections}{$conn_id};
}

# Internal methods

sub _parse_initial_packet($self, $packet) {
    # QUIC long header format:
    # 1 byte: flags (0x80 set for long header)
    # 4 bytes: version
    # 1 byte: DCID length
    # N bytes: DCID
    # 1 byte: SCID length
    # N bytes: SCID

    return unless length($packet) >= 7;

    my $flags = unpack('C', $packet);
    return unless ($flags & 0x80);  # Must be long header

    my $version = unpack('N', substr($packet, 1, 4));

    my $dcid_len = unpack('C', substr($packet, 5, 1));
    return unless length($packet) >= 6 + $dcid_len + 1;

    my $dcid_data = substr($packet, 6, $dcid_len);

    my $scid_len = unpack('C', substr($packet, 6 + $dcid_len, 1));
    return unless length($packet) >= 7 + $dcid_len + $scid_len;

    my $scid_data = substr($packet, 7 + $dcid_len, $scid_len);

    my $dcid = PageCamel::XS::NGTCP2::CID->new($dcid_data);
    my $scid = PageCamel::XS::NGTCP2::CID->new($scid_data);

    return ($dcid, $scid);
}

sub _extract_dcid($self, $packet) {
    return unless length($packet) >= 1;

    my $flags = unpack('C', $packet);

    if ($flags & 0x80) {
        # Long header
        return unless length($packet) >= 6;
        my $dcid_len = unpack('C', substr($packet, 5, 1));
        return unless length($packet) >= 6 + $dcid_len;
        return substr($packet, 6, $dcid_len);
    } else {
        # Short header - DCID is at fixed offset with length from settings
        # For simplicity, assume 8-byte DCID
        return unless length($packet) >= 9;
        return substr($packet, 1, 8);
    }
}

sub _generate_connection_id($self) {
    # Generate random 8-byte connection ID
    my $cid_data = '';
    for (1..8) {
        $cid_data .= chr(int(rand(256)));
    }
    return PageCamel::XS::NGTCP2::CID->new($cid_data);
}

sub _register_connection_id($self, $cid, $connection) {
    my $cid_data = ref($cid) ? $cid->data() : $cid;
    $self->{cid_to_connection}{$cid_data} = $connection;
    $connection->add_connection_id($cid_data);
}

sub _unregister_connection_id($self, $cid) {
    my $cid_data = ref($cid) ? $cid->data() : $cid;
    delete $self->{cid_to_connection}{$cid_data};
}

sub _close_connection($self, $conn_id) {
    my $connection = delete $self->{connections}{$conn_id};
    return unless $connection;

    # Unregister all connection IDs
    for my $cid ($connection->get_connection_ids()) {
        $self->_unregister_connection_id($cid);
    }

    # Notify callback
    if ($self->{on_connection_close}) {
        $self->{on_connection_close}->($connection);
    }

    $connection->destroy();
}

# Callback handlers

sub _on_stream_data($self, $connection, $stream_id, $data, $fin) {
    if ($self->{on_stream_data}) {
        $self->{on_stream_data}->($connection, $stream_id, $data, $fin);
    }
}

sub _on_stream_open($self, $connection, $stream_id) {
    # Stream opened - may trigger HTTP/3 layer
}

sub _on_stream_close($self, $connection, $stream_id, $error_code) {
    if ($self->{on_stream_close}) {
        $self->{on_stream_close}->($connection, $stream_id, $error_code);
    }
}

sub _on_handshake($self, $connection) {
    # Handshake completed
}

sub _on_migration($self, $connection, $old_path, $new_path) {
    if ($self->{on_migration}) {
        $self->{on_migration}->($connection, $old_path, $new_path);
    }
}

1;

__END__

=head1 NAME

PageCamel::Protocol::QUIC::Server - QUIC protocol server

=head1 SYNOPSIS

    use PageCamel::Protocol::QUIC::Server;

    my $server = PageCamel::Protocol::QUIC::Server->new(
        cert_file => '/path/to/cert.pem',
        key_file  => '/path/to/key.pem',
        on_connection => sub {
            my ($conn) = @_;
            print "New connection: " . $conn->id() . "\n";
        },
        on_stream_data => sub {
            my ($conn, $stream_id, $data, $fin) = @_;
            # Process stream data
        },
    );

    # In your event loop:
    while (1) {
        # Receive UDP packet
        my ($packet, $peer_addr) = $udp_socket->recv();

        # Process packet
        $server->process_packet($packet, $peer_addr);

        # Get outgoing packets
        for my $pkt ($server->get_packets()) {
            $udp_socket->send($pkt->{data}, $pkt->{peer_addr});
        }

        # Handle timeouts
        $server->handle_timeouts();
    }

=head1 DESCRIPTION

This class implements a QUIC protocol server using the ngtcp2 library.
It manages multiple concurrent QUIC connections and provides callbacks
for handling connection events.

=head1 METHODS

=head2 new(%config)

Create a new QUIC server.

Required configuration:

=over 4

=item cert_file - Path to TLS certificate

=item key_file - Path to TLS private key

=back

Optional configuration:

=over 4

=item alpn_protocols - ALPN protocols (default: ['h3'])

=item max_connections - Maximum concurrent connections (default: 1000)

=item idle_timeout - Idle timeout in nanoseconds (default: 30s)

=item max_streams_bidi - Max bidirectional streams (default: 100)

=item max_streams_uni - Max unidirectional streams (default: 100)

=item initial_max_data - Initial max data (default: 10MB)

=item max_stream_data - Max stream data (default: 1MB)

=item enable_0rtt - Enable 0-RTT (default: 1)

=item enable_migration - Enable connection migration (default: 1)

=back

Callbacks:

=over 4

=item on_connection - Called when new connection is established

=item on_stream_data - Called when stream data is received

=item on_stream_close - Called when stream is closed

=item on_connection_close - Called when connection is closed

=item on_migration - Called when connection migrates

=back

=head2 accept_connection($packet, $peer_addr, $local_addr)

Accept a new QUIC connection from an initial packet.

=head2 process_packet($packet, $peer_addr)

Process an incoming QUIC packet.

=head2 get_packets()

Get all outgoing packets to send.

=head2 handle_timeouts()

Handle connection timeouts.

=head2 get_next_timeout()

Get the next timeout timestamp.

=head2 close_connection($conn_id, $error_code, $reason)

Close a connection.

=head2 connection_count()

Get the number of active connections.

=head2 get_connection($conn_id)

Get a connection by ID.

=head1 SEE ALSO

L<PageCamel::Protocol::QUIC::Connection>, L<PageCamel::XS::NGTCP2>

=cut
