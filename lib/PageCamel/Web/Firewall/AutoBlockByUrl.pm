package PageCamel::Web::Firewall::AutoBlockByUrl;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.2;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub register($self) {
    $self->register_fastredirect("checkpath");
    return;
}

sub checkpath($self, $ua) {

    my $webpath = $ua->{url} || '--unknown--';
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    if(contains($webpath, $self->{block}->{item})) {
        $memh->clacks_set('Firewall::ExternalProject', $ua->{frontend}->{peerhost} . '|AutoBlockByUrl ' . $webpath);
        return (
            status => 418,
            type => 'text/plain',
            data => "Error 418: I'm a teapot",
        );
    }

    return;
}


1;
__END__

=head1 NAME

PageCamel::Web::Firewall::AutoBlockByUrl -

=head1 SYNOPSIS

  use PageCamel::Web::Firewall::AutoBlockByUrl;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 logend



=head2 getBlockedUrls



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
