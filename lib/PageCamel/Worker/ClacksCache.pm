package PageCamel::Worker::ClacksCache;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Helpers::ClacksCache PageCamel::Worker::BaseModule);

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    # Copy clacks config from external config module *before* new() on SUPER
    my $clconf = $config{server}->{modules}->{$config{clacksconfig}};
    $config{socketpath} = $clconf->get('socket');
    if(!defined($config{socketpath}) && $config{socketpath} eq '') {
        $config{host} = $clconf->get('host');
        $config{port} = $clconf->get('port');
    }
    $config{user} = $clconf->get('user');
    $config{password} = $clconf->get('password');

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub register($self) {
    $self->register_worker("refresh_lifetick");
    return;
}

1;
__END__
