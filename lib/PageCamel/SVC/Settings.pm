package PageCamel::SVC::Settings;
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
# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license

use base qw(PageCamel::Helpers::SystemSettings);
use PageCamel::Helpers::ClacksCache;

sub new($proto, $dbh, $clacks) {
    my $class = ref($proto) || $proto;
    
    my %tmp;
    my $self = \%tmp;
    
    #my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my $clackscache = PageCamel::Helpers::ClacksCache->newFromHandle($clacks);
    
    $self->{db} = 'maindb';
    $self->{memcache} = 'memcache';
    $self->{server}->{modules}->{maindb} = $dbh;
    $self->{server}->{modules}->{memcache} = $clackscache;

    $self->initDB();

    return $self;
}


1;
