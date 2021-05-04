package PageCamel::Helpers::Mod43Checksum;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

sub new {
    my $class = shift;
    my $self = bless {}, $class;

    my @keycodes = (
        '0',
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
        'A',
        'B',
        'C',
        'D',
        'E',
        'F',
        'G',
        'H',
        'I',
        'J',
        'K',
        'L',
        'M',
        'N',
        'O',
        'P',
        'Q',
        'R',
        'S',
        'T',
        'U',
        'V',
        'W',
        'X',
        'Y',
        'Z',
        '-',
        '.',
        ' ',
        '$',
        '/',
        '+',
        '%',
    );
    
    $self->{keycodes} = \@keycodes;

    return $self;
}

sub keytonum {
    my ($self, $val) = @_;

    $val = lc $val;
    my $num = 0;
    my $count = scalar @{$self->{keycodes}};
    for(my $i = 0; $i < scalar $count; $i++) {
        if($val eq $self->{keycodes}->[$i]) {
            $num = $i;
            last;
        }
    }
    return $num;
}

sub numtokey {
    my ($self, $val) = @_;

    my $key = '';
    my $count = scalar @{$self->{keycodes}};
    if($val < 0 || $val >= $count) {
        croak("Illegal keycode $val!");
    }

    return $self->{keycodes}->[$val];
}

sub genChecksum {
    my ($self, $val) = @_;

    $val = uc $val;
    my $sum = 0;
    my @parts = split//, $val;

    foreach my $part (@parts) {
        $sum += $self->keytonum($part);
    }

    my $key = $self->numtokey($sum % 43);

    return $key;
}


1;
