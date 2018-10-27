package PageCamel::Worker::ClacksCache;
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

use base qw(PageCamel::Helpers::ClacksCache PageCamel::Worker::BaseModule);

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    # Copy clacks config from external config module *before* new() on SUPER
    my $clconf = $config{server}->{modules}->{$config{clacksconfig}};
    $config{host} = $clconf->get('host');
    $config{port} = $clconf->get('port');
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
