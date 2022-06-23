package PageCamel::Web::PostgresDB;
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

use base qw(PageCamel::Helpers::PostgresDB PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->updateConfig();

    return $self;
}
sub handle_child_start {
    my ($self) = @_;

    # Make sure we get a database handle directly after forking in PreFork mode. With a properly
    # set *SpareServers config, this should minimize the slow start problem when the number
    # of connections spiked
    # Set the $hasforked flag as well
    $self->checkDBH(1);

    return;
}

sub endconfig {
    my ($self) = @_;

    if($self->{forking}) {
        # forking server: disconnect from database, generate new connection
        # after the fork on demand
        #print "   *** Will fork, disconnect PostgreSQL server...\n";
        $self->rollback;
        $self->{mdbh}->disconnect;
        delete $self->{mdbh};
    }
    return;
}

1;
__END__
