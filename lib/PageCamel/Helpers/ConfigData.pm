package PageCamel::Helpers::ConfigData;
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


sub get {
    my ($self, $key) = @_;

    return unless(defined($key));

    return unless(defined($self->{$key}));

    return $self->{$key};
}

1;
