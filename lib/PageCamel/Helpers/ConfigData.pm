package PageCamel::Helpers::ConfigData;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 2.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---


sub get {
    my ($self, $key) = @_;

    return unless(defined($key));

    return unless(defined($self->{$key}));

    return $self->{$key};
}

1;
