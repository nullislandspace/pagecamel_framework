package PageCamel::Web::ClacksCache;
#---AUTOPRAGMASTART---
use 5.032;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
use feature 'signatures';
no warnings qw(experimental::signatures);
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
