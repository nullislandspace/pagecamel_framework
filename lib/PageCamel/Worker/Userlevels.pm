package PageCamel::Worker::Userlevels;
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

use base qw(PageCamel::Helpers::Userlevels PageCamel::Worker::BaseModule);

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my $ok = 1;
    foreach my $required (qw[db reporting]) {
        if(!defined($self->{$required})) {
            print STDERR $self->{modname} . " requires config option " . $required . "\n";
            $ok = 0;
        }
    }

    if(!$ok) {
        croak("Configuration errors in ", $self->{modname});
    }

    return $self;
}
1;
__END__
