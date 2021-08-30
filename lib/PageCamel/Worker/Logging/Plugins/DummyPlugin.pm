package PageCamel::Worker::Logging::Plugins::DummyPlugin;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.8;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::Logging::PluginBase);

# -----------------------------------------------------------
# Some Logging "devices" are generating data differently.   #
# Due to current logging design, they still needs to have   #
# a plugin designated. So, this is a dummy plugin with      #
# a dummy work() function to handle multiple "device" types #
# -----------------------------------------------------------

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub crossregister {
    my $self = shift;
    
    foreach my $item (@{$self->{item}}) {
        $self->register_plugin('work', $item->{device}, $item->{subtype});
    }

    return;
}

sub work {
    my ($self, $device, $dbh, $reph, $memh) = @_;

    my $workCount = 0;

    # Nothing to do here by design

    return $workCount;
}

1;
__END__
