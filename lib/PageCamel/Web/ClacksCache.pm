package PageCamel::Web::ClacksCache;
#---AUTOPRAGMASTART---
use v5.40;
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

use base qw(PageCamel::Helpers::ClacksCache PageCamel::Web::BaseModule);

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

    my $self = $class->SUPER::new(%config); # Call parent NEW for tcp/ip mode
    bless $self, $class; # Re-bless with our class

    return $self;
}

1;
__END__
