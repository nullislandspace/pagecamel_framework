package PageCamel::Protocol::HTTP2::Stream;
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
use PageCamel::Protocol::HTTP2::Constants qw(:states :endpoints :settings :frame_types
  :limits :errors);
use PageCamel::Protocol::HTTP2::HeaderCompression qw( headers_decode );
use PageCamel::Protocol::HTTP2::Trace qw(tracer);

# Streams related part of PageCamel::Protocol::HTTP2::Conntection

# Autogen properties
{
    no strict 'refs';
    for my $prop (
        qw(promised_sid headers pp_headers header_block trailer
        trailer_headers length blocked_data weight end reset tunnel)
      )
    {
        *{ __PACKAGE__ . '::stream_' . $prop } = sub {
            return
                !exists $_[0]->{streams}->{ $_[1] } ? undef
              : @_ == 2 ? $_[0]->{streams}->{ $_[1] }->{$prop}
              :           ( $_[0]->{streams}->{ $_[1] }->{$prop} = $_[2] );
          }
    }
}

sub new_stream {
    my $self = shift;
    return if $self->goaway;

    $self->{last_stream} += 2
      if exists $self->{streams}->{ $self->{type} == CLIENT ? 1 : 2 };
    $self->{streams}->{ $self->{last_stream} } = {
        'state'      => IDLE,
        'weight'     => DEFAULT_WEIGHT,
        'stream_dep' => 0,
        'fcw_recv'   => $self->dec_setting(SETTINGS_INITIAL_WINDOW_SIZE),
        'fcw_send'   => $self->enc_setting(SETTINGS_INITIAL_WINDOW_SIZE),
    };
    return $self->{last_stream};
}

sub new_peer_stream {
    my $self      = shift;
    my $stream_id = shift;
    if (   $stream_id < $self->{last_peer_stream}
        || ( $stream_id % 2 ) == ( $self->{type} == CLIENT ) ? 1 : 0
        || $self->goaway )
    {
        tracer->error("Peer send invalid stream id: $stream_id\n");
        $self->error(PROTOCOL_ERROR);
        return;
    }
    $self->{last_peer_stream} = $stream_id;
    if ( $self->dec_setting(SETTINGS_MAX_CONCURRENT_STREAMS) <=
        $self->{active_peer_streams} )
    {
        tracer->warning("SETTINGS_MAX_CONCURRENT_STREAMS exceeded\n");
        print STDERR "HTTP2 REFUSED_STREAM: stream=$stream_id active=$self->{active_peer_streams} max=" . $self->dec_setting(SETTINGS_MAX_CONCURRENT_STREAMS) . "\n";
        $self->stream_error( $stream_id, REFUSED_STREAM );
        return;
    }
    $self->{active_peer_streams}++;
    tracer->debug("Active streams: $self->{active_peer_streams}");
    $self->{streams}->{$stream_id} = {
        'state'      => IDLE,
        'weight'     => DEFAULT_WEIGHT,
        'stream_dep' => 0,
        'fcw_recv'   => $self->dec_setting(SETTINGS_INITIAL_WINDOW_SIZE),
        'fcw_send'   => $self->enc_setting(SETTINGS_INITIAL_WINDOW_SIZE),
    };
    $self->{on_new_peer_stream}->($stream_id)
      if exists $self->{on_new_peer_stream};

    return $self->{last_peer_stream};
}

sub stream {
    my ( $self, $stream_id ) = @_;
    return unless exists $self->{streams}->{$stream_id};

    return $self->{streams}->{$stream_id};
}

# stream_state ( $self, $stream_id, $new_state?, $pending? )

sub stream_state {
    my ( $self, $stream_id, @rest ) = @_;
    return unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};

    if (@rest) {
        my ( $new_state, $pending ) = @rest;

        if ($pending) {
            $self->stream_pending_state( $stream_id, $new_state );
        }
        else {
            $self->{on_change_state}->( $stream_id, $s->{state}, $new_state )
              if exists $self->{on_change_state};

            $s->{state} = $new_state;

            # Exec callbacks for new state
            if ( exists $s->{cb} && exists $s->{cb}->{ $s->{state} } ) {
                for my $cb ( @{ $s->{cb}->{ $s->{state} } } ) {
                    $cb->();
                }
            }

            # Cleanup
            if ( $new_state == CLOSED ) {
                $self->{active_peer_streams}--
                  if $self->{active_peer_streams}
                  && ( ( $stream_id % 2 ) ^ ( $self->{type} == CLIENT ) );
                tracer->info(
                    "Active streams: $self->{active_peer_streams} $stream_id");
                for my $key ( keys %{$s} ) {
                    next if grep { $key eq $_ } (
                        qw(state weight stream_dep
                          fcw_recv fcw_send reset)
                    );
                    delete $s->{$key};
                }
            }
        }
    }

    return $s->{state};
}

sub stream_pending_state {
    my $self      = shift;
    my $stream_id = shift;
    return unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};
    if (@_) {
        $s->{pending_state} = shift;
        $self->{pending_stream} =
          defined $s->{pending_state} ? $stream_id : undef;
    }
    return $s->{pending_state};
}

sub stream_cb {
    my ( $self, $stream_id, $state, $cb ) = @_;

    return unless exists $self->{streams}->{$stream_id};

    push @{ $self->{streams}->{$stream_id}->{cb}->{$state} }, $cb;
    return;
}

sub stream_frame_cb {
    my ( $self, $stream_id, $frame, $cb ) = @_;

    return unless exists $self->{streams}->{$stream_id};

    push @{ $self->{streams}->{$stream_id}->{frame_cb}->{$frame} }, $cb;
    return;
}

sub stream_data {
    my ( $self, $stream_id, $data ) = @_;
    return unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};

    if (defined $data) {

        # Exec callbacks for data
        if ( exists $s->{frame_cb} && exists $s->{frame_cb}->{&DATA} ) {
            for my $cb ( @{ $s->{frame_cb}->{&DATA} } ) {
                $cb->( $data );
            }
        }
        else {
            $s->{data} .= $data;
        }
    }

    return $s->{data};
}

sub stream_headers_done {
    my $self      = shift;
    my $stream_id = shift;
    return unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};

    my $res =
      headers_decode( $self, \$s->{header_block}, 0,
        length $s->{header_block}, $stream_id );

    tracer->debug("Headers done for stream $stream_id\n");

    return unless defined $res;

    # Clear header_block
    $s->{header_block} = '';

    my $eh          = $self->decode_context->{emitted_headers};
    my $is_response = $self->{type} == CLIENT && !$s->{promised_sid};
    my $is_trailer  = !!$self->stream_trailer($stream_id);

    return
      unless $self->validate_headers( $eh, $stream_id, $is_response );

    if ( $s->{promised_sid} ) {
        $self->{streams}->{ $s->{promised_sid} }->{pp_headers} = $eh;
    }
    elsif ($is_trailer) {
        $self->stream_trailer_headers( $stream_id, $eh );
    }
    else {
        $s->{headers} = $eh;
    }

    # Exec callbacks for headers
    if ( exists $s->{frame_cb} && exists $s->{frame_cb}->{&HEADERS} ) {
        for my $cb ( @{ $s->{frame_cb}->{&HEADERS} } ) {
            $cb->($eh);
        }
    }

    # Clear emitted headers
    $self->decode_context->{emitted_headers} = [];

    return 1;
}

sub validate_headers {
    my ( $self, $headers, $stream_id, $is_response ) = @_;
    my $pseudo_flag = 1;
    my %pseudo_hash = ();

    # First pass: collect pseudo-headers to determine request type
    for my $i ( 0 .. @{$headers} / 2 - 1 ) {
        my ( $h, $v ) = ( $headers->[ $i * 2 ], $headers->[ $i * 2 + 1 ] );
        if ( $h =~ /^\:/ ) {
            $pseudo_hash{$h} = $v;
        }
    }

    # Determine allowed and required pseudo-headers based on request type
    my @h;  # Required pseudo-headers
    my @allowed_h;  # All allowed pseudo-headers

    if ($is_response) {
        @h = (qw(:status));
        @allowed_h = @h;
    }
    elsif ( exists $pseudo_hash{':method'} && $pseudo_hash{':method'} eq 'CONNECT' ) {
        # CONNECT method has special pseudo-header requirements
        if ( exists $pseudo_hash{':protocol'} ) {
            # Extended CONNECT (RFC 8441) - requires :protocol
            # Check if WE (the server) have enabled extended CONNECT protocol
            # dec_setting = our settings (what we advertise to peer)
            if ( !$self->dec_setting(SETTINGS_ENABLE_CONNECT_PROTOCOL) ) {
                tracer->warning(":protocol pseudo-header used without SETTINGS_ENABLE_CONNECT_PROTOCOL");
                $self->stream_error( $stream_id, PROTOCOL_ERROR );
                return;
            }
            # Extended CONNECT requires: :method, :scheme, :authority, :path, :protocol
            @h = qw(:method :scheme :authority :path :protocol);
            @allowed_h = @h;
        }
        else {
            # Standard CONNECT only requires :method and :authority
            # :scheme and :path MUST NOT be present
            @h = qw(:method :authority);
            @allowed_h = @h;
        }
    }
    else {
        # Regular request
        @h = qw(:method :scheme :authority :path);
        @allowed_h = @h;
    }

    # Reset pseudo_hash for second pass
    %pseudo_hash = ();
    $pseudo_flag = 1;

    # Trailer headers ?
    if ( my $t = $self->stream_trailer($stream_id) ) {
        for my $i ( 0 .. @{$headers} / 2 - 1 ) {
            my ( $h, $v ) = ( $headers->[ $i * 2 ], $headers->[ $i * 2 + 1 ] );
            if ( !exists $t->{$h} ) {
                tracer->warning(
                    "header <$h> doesn't listed in the trailer header");
                $self->stream_error( $stream_id, PROTOCOL_ERROR );
                return;
            }
        }
        return 1;
    }

    for my $i ( 0 .. @{$headers} / 2 - 1 ) {
        my ( $h, $v ) = ( $headers->[ $i * 2 ], $headers->[ $i * 2 + 1 ] );
        if ( $h =~ /^\:/ ) {
            if ( !$pseudo_flag ) {
                tracer->warning(
                    "pseudo-header <$h> appears after a regular header");
                $self->stream_error( $stream_id, PROTOCOL_ERROR );
                return;
            }
            elsif ( !grep { $_ eq $h } @allowed_h ) {
                tracer->warning("invalid pseudo-header <$h>");
                $self->stream_error( $stream_id, PROTOCOL_ERROR );
                return;
            }
            elsif ( exists $pseudo_hash{$h} ) {
                tracer->warning("repeated pseudo-header <$h>");
                $self->stream_error( $stream_id, PROTOCOL_ERROR );
                return;
            }

            $pseudo_hash{$h} = $v;
            next;
        }

        $pseudo_flag = 0 if $pseudo_flag;

        if ( $h eq 'connection' ) {
            tracer->warning("connection header is not valid in http/2");
            $self->stream_error( $stream_id, PROTOCOL_ERROR );
            return;
        }
        elsif ( $h eq 'te' && $v ne 'trailers' ) {
            tracer->warning("TE header can contain only value 'trailers'");
            $self->stream_error( $stream_id, PROTOCOL_ERROR );
            return;
        }
        elsif ( $h eq 'content-length' ) {
            $self->stream_length( $stream_id, $v );
        }
        elsif ( $h eq 'trailer' ) {
            my %th = map { $_ => 1 } split /\s*,\s*/, lc($v);
            if (
                grep { exists $th{$_} } (
                    qw(transfer-encoding content-length host authentication
                      cache-control expect max-forwards pragma range te
                      content-encoding content-type content-range trailer)
                )
              )
            {
                tracer->warning("trailer header contain forbidden headers");
                $self->stream_error( $stream_id, PROTOCOL_ERROR );
                return;
            }
            $self->stream_trailer( $stream_id, {%th} );
        }
    }

    for my $h (@h) {
        next if exists $pseudo_hash{$h};

        tracer->warning("missed mandatory pseudo-header $h");
        $self->stream_error( $stream_id, PROTOCOL_ERROR );
        return;
    }

    return 1;
}

# RST_STREAM for stream errors
sub stream_error {
    my ( $self, $stream_id, $error ) = @_;
    $self->enqueue( RST_STREAM, 0, $stream_id, $error );
    return;
}

# Flow control windown of stream
sub _stream_fcw {
    my $dir       = shift;
    my $self      = shift;
    my $stream_id = shift;
    return unless exists $self->{streams}->{$stream_id};
    my $s = $self->{streams}->{$stream_id};

    if (@_) {
        $s->{$dir} += shift;
        tracer->debug( "Stream $stream_id $dir now is " . $s->{$dir} . "\n" );
    }
    return $s->{$dir};
}

sub stream_fcw_send {
    my ( $self, $stream_id, @rest ) = @_;
    return _stream_fcw( 'fcw_send', $self, $stream_id, @rest );
}

sub stream_fcw_recv {
    my ( $self, $stream_id, @rest ) = @_;
    return _stream_fcw( 'fcw_recv', $self, $stream_id, @rest );
}

sub stream_fcw_update {
    my ( $self, $stream_id ) = @_;

    # TODO: check size of data of stream  in memory
    my $size = $self->dec_setting(SETTINGS_INITIAL_WINDOW_SIZE);
    tracer->debug("update fcw recv of stream $stream_id with $size b.\n");
    $self->stream_fcw_recv( $stream_id, $size );
    $self->enqueue( WINDOW_UPDATE, 0, $stream_id, $size );
    return;
}

sub stream_send_blocked {
    my ( $self, $stream_id ) = @_;
    my $s = $self->{streams}->{$stream_id} or return;

    if ( defined( $s->{blocked_data} ) && length( $s->{blocked_data} )
        && $self->stream_fcw_send($stream_id) > 0 )
    {
        $self->send_data($stream_id);
    }
    return;
}

sub stream_reprio {
    my ( $self, $stream_id, $exclusive, $stream_dep ) = @_;
    return
      unless exists $self->{streams}->{$stream_id}
      && ( $stream_dep == 0 || exists $self->{streams}->{$stream_dep} )
      && $stream_id != $stream_dep;
    my $s = $self->{streams};

    if ( $s->{$stream_id}->{stream_dep} != $stream_dep ) {

        # check if new stream_dep is stream child
        if ( $stream_dep != 0 ) {
            my $sid = $stream_dep;
            while ( $sid = $s->{$sid}->{stream_dep} ) {
                next unless $sid == $stream_id;

                # Child take my stream dep
                $s->{$stream_dep}->{stream_dep} =
                  $s->{$stream_id}->{stream_dep};
                last;
            }
        }

        # Set new stream dep
        $s->{$stream_id}->{stream_dep} = $stream_dep;
    }

    if ($exclusive) {

        # move all siblings to children
        for my $sid ( keys %{$s} ) {
            next
              if $s->{$sid}->{stream_dep} != $stream_dep
              || $sid == $stream_id;

            $s->{$sid}->{stream_dep} = $stream_id;
        }
    }

    return 1;
}

1;
