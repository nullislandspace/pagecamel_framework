package PageCamel::Web::ClacksCache;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.4;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Helpers::ClacksCache PageCamel::Web::BaseModule);

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

    my $self = $class->SUPER::new(%config); # Call parent NEW for tcp/ip mode
    bless $self, $class; # Re-bless with our class

    return $self;
}

1;
__END__
