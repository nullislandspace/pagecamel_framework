package PageCamel::SVC::Settings;
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
# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license

use base qw(PageCamel::Helpers::SystemSettings);
use PageCamel::Helpers::ClacksCache;

sub new {
    my ($proto, $dbh, $clacks) = @_;
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
        
    return $self;
}


1;
