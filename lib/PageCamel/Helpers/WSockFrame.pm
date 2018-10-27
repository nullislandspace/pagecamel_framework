package PageCamel::Helpers::WSockFrame;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 1;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---


use Config;
use Encode ();
use Scalar::Util 'readonly';

use constant MAX_RAND_INT       => 2**32;
use constant MATH_RANDOM_SECURE => eval "require Math::Random::Secure;";

our %TYPES = (
    continuation => 0x00,
    text         => 0x01,
    binary       => 0x02,
    ping         => 0x09,
    pong         => 0x0a,
    close        => 0x08
);

sub new {
    my $class = shift;
    $class = ref $class if ref $class;
    my $buffer;

    if (@_ == 1) {
        $buffer = shift @_;
    }
    else {
        my %args = @_;
        $buffer = delete $args{buffer};
    }

    my $self = {@_};
    bless $self, $class;

    $buffer = '' unless defined $buffer;

    #if (Encode::is_utf8($buffer)) {
    #    $self->{buffer} = Encode::encode('UTF-8', $buffer);
    #}
    #else {
        $self->{buffer} = $buffer;
    #}

    if (defined($self->{type}) && defined($TYPES{$self->{type}})) {
        $self->opcode($TYPES{$self->{type}});
    }

    $self->{version} ||= 'draft-ietf-hybi-17';

    $self->{fragments} = [];

    $self->{max_fragments_amount} ||= 128;
    #$self->{max_payload_size}     ||= 65536;
    $self->{max_payload_size}     ||= 500 * 1024 * 1024;

    return $self;
}

sub version {
    my $self = shift;

    return $self->{version};
}

sub append {
    my $self = shift;

    return unless defined $_[0];

    $self->{buffer} .= $_[0];
    $_[0] = '' unless readonly $_[0];

    return $self;
}

sub next {
    my $self = shift;

    my $bytes = $self->next_bytes;
    return unless defined $bytes;

    #return Encode::decode('UTF-8', $bytes);
    return $bytes;
}

sub fin {
    @_ > 1 ? $_[0]->{fin} =
        $_[1]
      : defined($_[0]->{fin}) ? $_[0]->{fin}
      :                         1;
}
sub rsv { @_ > 1 ? $_[0]->{rsv} = $_[1] : $_[0]->{rsv} }

sub opcode {
    @_ > 1 ? $_[0]->{opcode} =
        $_[1]
      : defined($_[0]->{opcode}) ? $_[0]->{opcode}
      :                            1;
}
sub masked { @_ > 1 ? $_[0]->{masked} = $_[1] : $_[0]->{masked} }

sub is_ping         { $_[0]->opcode == 9 }
sub is_pong         { $_[0]->opcode == 10 }
sub is_close        { $_[0]->opcode == 8 }
sub is_continuation { $_[0]->opcode == 0 }
sub is_text         { $_[0]->opcode == 1 }
sub is_binary       { $_[0]->opcode == 2 }

sub next_bytes {
    my $self = shift;

    if (   $self->version eq 'draft-hixie-75'
        || $self->version eq 'draft-ietf-hybi-00')
    {
        if ($self->{buffer} =~ s/^\xff\x00//) {
            $self->opcode(8);
            return '';
        }

        return unless $self->{buffer} =~ s/^[^\x00]*\x00(.*?)\xff//s;

        return $1;
    }

    return unless length $self->{buffer} >= 2;

    while (length $self->{buffer}) {
        my $hdr = substr($self->{buffer}, 0, 1);

        my @bits = split //, unpack("B*", $hdr);

        $self->fin($bits[0]);
        $self->rsv([@bits[1 .. 3]]);

        my $opcode = unpack('C', $hdr) & 0b00001111;

        my $offset = 1;    # FIN,RSV[1-3],OPCODE

        my $payload_len = unpack 'C', substr($self->{buffer}, 1, 1);

        my $masked = ($payload_len & 0b10000000) >> 7;
        $self->masked($masked);

        $offset += 1;      # + MASKED,PAYLOAD_LEN

        $payload_len = $payload_len & 0b01111111;
        if ($payload_len == 126) {
            return unless length($self->{buffer}) >= $offset + 2;

            $payload_len = unpack 'n', substr($self->{buffer}, $offset, 2);

            $offset += 2;
        }
        elsif ($payload_len > 126) {
            return unless length($self->{buffer}) >= $offset + 4;

            my $bits = join '', map { unpack 'B*', $_ } split //,
              substr($self->{buffer}, $offset, 8);

            # Most significant bit must be 0.
            # And here is a crazy way of doing it %)
            $bits =~ s{^.}{0};

            # Can we handle 64bit numbers?
            if ($Config{ivsize} <= 4 || $Config{longsize} < 8 || $] < 5.010) {
                $bits = substr($bits, 32);
                $payload_len = unpack 'N', pack 'B*', $bits;
            }
            else {
                $payload_len = unpack 'Q>', pack 'B*', $bits;
            }

            $offset += 8;
        }

        if ($payload_len > $self->{max_payload_size}) {
            $self->{buffer} = '';
            die "Payload is too big. "
              . "Deny big message ($payload_len) "
              . "or increase max_payload_size ($self->{max_payload_size})";
        }

        my $mask;
        if ($self->masked) {
            return unless length($self->{buffer}) >= $offset + 4;

            $mask = substr($self->{buffer}, $offset, 4);
            $offset += 4;
        }

        return if length($self->{buffer}) < $offset + $payload_len;

        my $payload = substr($self->{buffer}, $offset, $payload_len);

        if ($self->masked) {
            $payload = $self->_mask($payload, $mask);
        }

        substr($self->{buffer}, 0, $offset + $payload_len, '');

        # Injected control frame
        if (@{$self->{fragments}} && $opcode & 0b1000) {
            $self->opcode($opcode);
            return $payload;
        }

        if ($self->fin) {
            if (@{$self->{fragments}}) {
                $self->opcode(shift @{$self->{fragments}});
            }
            else {
                $self->opcode($opcode);
            }
            $payload = join '', @{$self->{fragments}}, $payload;
            $self->{fragments} = [];
            return $payload;
        }
        else {

            # Remember first fragment opcode
            if (!@{$self->{fragments}}) {
                push @{$self->{fragments}}, $opcode;
            }

            push @{$self->{fragments}}, $payload;

            if(@{$self->{fragments}} > $self->{max_fragments_amount}) {
                die "Too many fragments";
            }

        }
    }

    return;
}

sub to_bytes {
    my $self = shift;

    if (   $self->version eq 'draft-hixie-75'
        || $self->version eq 'draft-ietf-hybi-00')
    {
        if ($self->{type} && $self->{type} eq 'close') {
            return "\xff\x00";
        }

        return "\x00" . $self->{buffer} . "\xff";
    }

    if (length $self->{buffer} > $self->{max_payload_size}) {
        die "Payload is too big. "
          . "Send shorter messages or increase max_payload_size";
    }

    my $string = '';

    my $opcode = $self->opcode;

    $string .= pack 'C', ($opcode + ($self->fin ? 128 : 0));

    my $payload_len = length($self->{buffer});
    if ($payload_len <= 125) {
        $payload_len |= 0b10000000 if $self->masked;
        $string .= pack 'C', $payload_len;
    }
    elsif ($payload_len <= 0xffff) {
        $string .= pack 'C', 126 + ($self->masked ? 128 : 0);
        $string .= pack 'n', $payload_len;
    }
    else {
        $string .= pack 'C', 127 + ($self->masked ? 128 : 0);

        # Shifting by an amount >= to the system wordsize is undefined
        $string .= pack 'N', $Config{ivsize} <= 4 ? 0 : $payload_len >> 32;
        $string .= pack 'N', ($payload_len & 0xffffffff);
    }

    if ($self->masked) {

        my $mask = $self->{mask}
          || (
            MATH_RANDOM_SECURE
            ? Math::Random::Secure::irand(MAX_RAND_INT)
            : int(rand(MAX_RAND_INT))
          );

        $mask = pack 'N', $mask;

        $string .= $mask;
        $string .= $self->_mask($self->{buffer}, $mask);
    }
    else {
        $string .= $self->{buffer};
    }

    return $string;
}

sub to_string {
    my $self = shift;

    die 'DO NOT USE';
}

sub _mask {
    my $self = shift;
    my ($payload, $mask) = @_;

    $mask = $mask x (int(length($payload) / 4) + 1);
    $mask = substr($mask, 0, length($payload));
    $payload = "$payload" ^ $mask;

    return $payload;
}

1;
__END__

=head1 NAME

PageCamel::Helpers::WSockFrame - encode/decode Websocket frames.

=head1 SYNOPSIS

  use PageCamel::Helpers::WSockFrame;

=head1 DESCRIPTION

This is based on the original Protocol::WebSocket module by Viacheslav Tykhanovskyi, but botched to work in PageCamel.

=head2 new

Create a new instance.

=head2 version

Return websocket version.

=head2 append

Append raw data for later decoding.

=head2 next

Get the next decoded frame

=head2 fin

Set fin flag

=head2 rsv

Set RSV flag

=head2 opcode

Get the opcode of the last decoded frame.

=head2 masked

Set the masked flag

=head2 is_ping

Check if decoded frame was a ping.

=head2 is_pong

Check if decoded frame was a pong.

=head2 is_close

Check if decoded frame was a close.

=head2 is_continuation

Check if decoded frame was a continuation.


=head2 is_text

Check if decoded frame was a text.

=head2 is_binary

Check if decoded frame was a binary.

=head2 next_bytes

?

=head2 to_bytes

?

=head2 to_string

?

=head2 _mask

?

=head1 IMPORTANT NOTE

This module is part of the PageCamel framework. Currently, only limited support
and documentation exists outside my DarkPAN repositories. This source is
currently only provided for your reference and usage in other projects (just
copy&paste what you need, see license terms below).

To see PageCamel in action and for news about the project,
visit my blog at L<https://cavac.at>.

=head1 AUTHOR

Rene Schickbauer, E<lt>cavac@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010-2014 by Viacheslav Tykhanovskyi
Copyright (C) 2014-2016 by Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
