package PageCamel::Helpers::ConfigData;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.3;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---


sub get {
    my ($self, $key) = @_;

    return unless(defined($key));

    return unless(defined($self->{$key}));

    return $self->{$key};
}

1;
