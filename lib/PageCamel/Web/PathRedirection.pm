package PageCamel::Web::PathRedirection;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.2;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
use Data::Dumper;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);




sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my %paths;

    # pre-parse the options for faster response
    foreach my $path (@{$self->{redirect}}) {
        my %tmp = (status       => $path->{statuscode},
                   statustext   => $path->{statustext},
                   location     => $path->{destination},
                   data         => "<html><body>If you are not automatically redirected, click " .
                                    "<a href=\"" . $path->{destination} . "\">here</a>.</body></html>",
                   type         => "text/html",
                  );
        $paths{$path->{source}} = \%tmp;
    }

    $self->{paths} = \%paths;

    return $self;
}

sub reload {
    # Nothing to do
    return;
}

sub register {
    my $self = shift;
    $self->register_prefilter("prefilter");
    return;
}

sub prefilter {
    my ($self, $ua) = @_;

    my $webpath = $ua->{url};

    # if there is a redirect for the current path, just return the
    # pre-parsed response
    if(defined($self->{paths}->{$webpath})) {
        return %{$self->{paths}->{$webpath}};
    }

    return; # No redirection
}

1;
__END__

=head1 NAME

PageCamel::Web::PathRedirection -

=head1 SYNOPSIS

  use PageCamel::Web::PathRedirection;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 prefilter



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
