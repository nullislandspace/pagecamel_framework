package PageCamel::Worker::ClacksCache;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp;
our $VERSION = 2.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Helpers::ClacksCache PageCamel::Worker::BaseModule);

sub new {
    my ($proto, %config) = @_;
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

sub register {
    my $self = shift;
    $self->register_worker("refresh_lifetick");
    return;
}

1;
__END__
