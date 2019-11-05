package PageCamel::SVC::Settings;
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
# PAGECAMEL  (C) 2008-2018 Rene Schickbauer
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
