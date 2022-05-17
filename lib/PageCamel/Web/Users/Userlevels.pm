package PageCamel::Web::Users::Userlevels;
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

use base qw(PageCamel::Web::BaseModule);

use PageCamel::Helpers::Padding qw[doSpacePad];
use PageCamel::Helpers::Strings qw[stripString];

use Readonly;


Readonly my $TESTRANGE => 1_000_000;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub finalcheck {
    my ($self) = @_;

    # Check which webpaths are under restricted paths and print some stats
    my %levelpaths;
    my %levelcount;
    foreach my $level (@{$self->{userlevels}->{userlevel}}) {
        if(!defined($level->{db})) {
            croak("Userlevels: undefined DB for " . $level->{display});
        }
        if(defined($level->{internal}) && $level->{internal} == 1) {
            # internal user permission does not need a path
        } else {
            if(!defined($level->{path})) {
                croak("Userlevels: undefined PATH for " . $level->{display});
            }
            $levelpaths{$level->{path}} = $level->{db};
        }
        $levelcount{$level->{db}} = 0;
        
        if(defined($level->{restrict})) {
            my @parts = split/\,/, $level->{restrict};
            my @allowed;
            foreach my $part (@parts) {
                push @allowed, stripString($part);
            }
            $level->{restrict} = \@allowed;
        }
        
        
    }
    $levelcount{UNKNOWN} = 0;

    print "** Normal webpaths:\n";
    my $paths = $self->{server}->get_webpaths;
    foreach my $path (sort keys %{$paths}) {
        my $dbpath = 'UNKNOWN';
        foreach my $lp (keys %levelpaths) {
            if($path =~ /^$lp/) {
                $dbpath = $levelpaths{$lp};
                last;
            }
        }
        $levelcount{$dbpath}++;
        print '      ', doSpacePad($dbpath, 10), ' ', "$path\n";
    }

    print "** Override webpaths:\n";
    my $opaths = $self->{server}->get_overridewebpaths;
    foreach my $path (sort keys %{$opaths}) {
        my $dbpath = 'UNKNOWN';
        foreach my $lp (keys %levelpaths) {
            if($path =~ /^$lp/) {
                $dbpath = $levelpaths{$lp};
                last;
            }
        }
        $levelcount{$dbpath}++;
        print '      ', doSpacePad($dbpath, 10), ' ', "$path\n";
    }

    print "    --- path statistics START ---\n";
    foreach my $key (sort keys %levelcount) {
        print "     $key: $levelcount{$key}\n";
    }

    print "    ---  path statistics END  ---\n";

    return;
}


1;
__END__

=head1 NAME

PageCamel::Web::Users::Userlevels -

=head1 SYNOPSIS

  use PageCamel::Web::Users::Userlevels;



=head1 DESCRIPTION



=head2 new



=head2 finalcheck



=head1 IMPORTANT NOTE

This module is part of the PageCamel framework. Currently, only limited support
and documentation exists outside my DarkPAN repositories. This source is
currently only provided for your reference and usage in other projects (just
copy&paste what you need, see license terms below).

To see PageCamel in action and for news about the project,
visit my blog at L<https://cavac.at>.

=head1 AUTHOR

Rene Schickbauer, E<lt>pagecamel@cavac.atE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
