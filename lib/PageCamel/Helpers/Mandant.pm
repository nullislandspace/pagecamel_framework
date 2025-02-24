package PageCamel::Helpers::Mandant;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.5;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use XML::Simple;

sub new($proto) {
    my $class = ref($proto) || $proto;

    my %config = (
        active => 0,
    );

    my $self = bless \%config, $class;

    if(defined($ENV{PC_MANDANT}) && defined($ENV{PC_MANDANTCONFIG}) && $ENV{PC_MANDANT} ne '' && $ENV{PC_MANDANTCONFIG} ne '') {
        my $xml;
        my $fname = $ENV{PC_MANDANTCONFIG};
        if(!-f $fname) {
            print STDERR "Mandantconfig ", $fname, " not found!\n";
            return $self;
        }

        eval {
            $xml = XMLin($fname, ForceArray => ['mandant']);
        };

        if(!defined($xml)) {
            croak("Failed to load $fname: ", $EVAL_ERROR);
        }

        #print STDERR Dumper($xml);

        $self->{this_mandant} = $ENV{PC_MANDANT};
        $self->{xml} = $xml;
        my $found = 0;
        my $error = 0;
        foreach my $mandant (@{$self->{xml}->{mandant}}) {
            # Check for required keys
            foreach my $key (qw[shortname backend clacks]) {
                if(!defined($mandant->{$key})) {
                    print STDERR "Mandant config is missing key $key\n";
                    $error = 1;
                }
            }
            last if($error);

            if($mandant->{shortname} eq $self->{this_mandant}) {
                $found = 1;
            }
        }

        if($error) {
            croak("Incomplete mandant config");
        }

        if(!$found) {
            croak("Specified mandant " . $self->{this_mandant} . " is not in mandant config");
        }

        $self->{active} = 1;

        $self->{isDefault} = 0;
        if($ENV{PC_MANDANT} eq $self->{xml}->{default}) {
            $self->{isDefault} = 1;
        }

        #print STDERR "Mandant subsystem active\n";
    }

    return $self;
}

sub isActive($self) {
    return $self->{active};
}

sub isDefault($self) {
    if(!$self->{active}) {
        croak("Can't call getName() without loaded mandant config");
    }

    return $self->{isDefault};
}

sub getDefaultMandant($self) {
    if(!$self->{active}) {
        croak("Can't call getName() without loaded mandant config");
    }

    return $self->{xml}->{default};
}

sub getName($self) {
    if(!$self->{active}) {
        croak("Can't call getName() without loaded mandant config");
    }

    return $self->{this_mandant};
}

sub getList($self) {
    if(!$self->{active}) {
        croak("Can't call getList() without loaded mandant config");
    }

    my @mandants;
    foreach my $mandant (@{$self->{xml}->{mandant}}) {
        push @mandants, $mandant->{shortname};
    }

    @mandants = sort @mandants;

    return @mandants;
}

sub getBackend($self, $shortname) {
    if(!$self->{active}) {
        croak("Can't call getBackend() without loaded mandant config");
    }

    my $backend;

    foreach my $mandant (@{$self->{xml}->{mandant}}) {
        if($mandant->{shortname} eq $shortname) {
            $backend = $mandant->{backend};
            last;
        }
    }

    return $backend;
}

sub getClacks($self, $shortname) {
    if(!$self->{active}) {
        croak("Can't call getClacks() without loaded mandant config");
    }

    my $clacks;

    foreach my $mandant (@{$self->{xml}->{mandant}}) {
        if($mandant->{shortname} eq $shortname) {
            $clacks = $mandant->{clacks};
            last;
        }
    }

    return $clacks;
}
