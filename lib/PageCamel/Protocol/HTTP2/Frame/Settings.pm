package PageCamel::Protocol::HTTP2::Frame::Settings;
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
use PageCamel::Protocol::HTTP2::Constants qw(const_name :flags :errors :limits :settings);
use PageCamel::Protocol::HTTP2::Trace qw(tracer);

my %s_check = (
    &SETTINGS_MAX_FRAME_SIZE => {
        validator => sub {
            $_[0] <= MAX_PAYLOAD_SIZE && $_[0] >= DEFAULT_MAX_FRAME_SIZE;
        },
        error => PROTOCOL_ERROR
    },
    &SETTINGS_ENABLE_PUSH => {
        validator => sub {
            $_[0] == 0 || $_[0] == 1;
        },
        error => PROTOCOL_ERROR
    },
    &SETTINGS_INITIAL_WINDOW_SIZE => {
        validator => sub {
            $_[0] <= MAX_FCW_SIZE;
        },
        error => FLOW_CONTROL_ERROR
    },
    &SETTINGS_ENABLE_CONNECT_PROTOCOL => {
        validator => sub {
            $_[0] == 0 || $_[0] == 1;
        },
        error => PROTOCOL_ERROR
    },
);

my %s_action = (
    &SETTINGS_INITIAL_WINDOW_SIZE => sub {
        my ( $con, $size ) = @_;
        $con->fcw_initial_change($size);
    }
);

sub decode {
    my ( $con, $buf_ref, $buf_offset, $length ) = @_;
    my $frame_ref = $con->decode_context->{frame};

    if ( $frame_ref->{stream} != 0 ) {
        $con->error(PROTOCOL_ERROR);
        return;
    }

    # just ack for our previous settings
    if ( $frame_ref->{flags} & ACK ) {
        if ( $length != 0 ) {
            tracer->error(
                "ACK settings frame have non-zero ($length) payload\n");
            $con->error(FRAME_SIZE_ERROR);
            return;
        }
        return 0

          # received empty settings (default), accept it
    }
    elsif ( $length == 0 ) {
        $con->accept_settings();
        return 0;
    }

    if ( $length % 6 != 0 ) {
        tracer->error("Settings frame payload is broken (length $length)\n");
        $con->error(FRAME_SIZE_ERROR);
        return;
    }

    my @settings = unpack( '(nN)*', substr( ${$buf_ref}, $buf_offset, $length ) );
    while ( my ( $key, $value ) = splice @settings, 0, 2 ) {
        if ( !defined $con->enc_setting($key) ) {
            tracer->debug("\tUnknown setting $key\n");

            # ignore unknown setting
            next;
        }
        elsif ( exists $s_check{$key}
            && !$s_check{$key}{validator}->($value) )
        {
            tracer->debug( "\tInvalid value of setting "
                  . const_name( "settings", $key ) . ": "
                  . $value );
            $con->error( $s_check{$key}{error} );
            return;
        }

        # Settings change may run some action
        $s_action{$key}->( $con, $value ) if exists $s_action{$key};

        tracer->debug(
            "\tSettings " . const_name( "settings", $key ) . " = $value\n" );

        # SETTINGS_ENABLE_CONNECT_PROTOCOL (8) is special: it indicates what WE support,
        # not what the peer requests. Don't let peer's value overwrite our advertised value.
        # RFC 8441: This setting is only meaningful from server to client.
        if ( $key == SETTINGS_ENABLE_CONNECT_PROTOCOL ) {
            tracer->debug("\tSkipping ENABLE_CONNECT_PROTOCOL from peer (our capability, not theirs)\n");
            next;
        }

        $con->enc_setting( $key, $value );
    }

    $con->accept_settings();
    return $length;
}

sub encode {
    my ( $con, $flags_ref, $stream, $data ) = @_;
    my $payload = '';
    for my $key ( sort keys %{$data} ) {
        tracer->debug( "\tSettings "
              . const_name( "settings", $key )
              . " = $data->{$key}\n" );
        $payload .= pack( 'nN', $key, $data->{$key} );
    }
    return $payload;
}

1;
