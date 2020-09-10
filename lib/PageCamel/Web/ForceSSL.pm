package PageCamel::Web::ForceSSL;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.3;
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

    return $self;
}

sub register {
    my $self = shift;
    $self->register_prefilter("prefilter");
    return;
}

sub prefilter {
    my ($self, $ua, $header, $result) = @_;

    if($ua->{frontend}->{ssl}) {
        # Nothing to do
        return;
    }

    my $webpath = $ua->{url};
    my $hostprefix;
    if(defined($ua->{headers}->{Host})) {
        $hostprefix = $ua->{headers}->{Host};
    } else {
        $hostprefix = $self->{urlprefix};
    }

    my $fullpath = $hostprefix . $webpath;
    if($fullpath !~ /^https/) {
        $fullpath = 'https://' . $fullpath;
    }

    return (
        status => 301,
        location => $fullpath,
        type => 'text/html',
        data => "<html><body>If you are not automatically redirected, click " .
                           "<a href=\"" . $fullpath . "\">here</a>.</body></html>",
    );
}

1;
__END__

=head1 NAME

PageCamel::Web::ForceSSL -

=head1 SYNOPSIS

  use PageCamel::Web::ForceSSL;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 postfilter



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
