package PageCamel::Helpers::ConfigData;
#---AUTOPRAGMASTART---
use v5.42;
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


sub get($self, $key) {
    return unless(defined($key));

    return unless(defined($self->{$key}));

    return $self->{$key};
}

1;
