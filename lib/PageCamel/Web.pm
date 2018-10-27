package PageCamel::Web;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 1;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use PageCamel::WebSingle;
use PageCamel::WebPreFork;

sub new {
    my ($proto, $isForking) = @_;

    croak("isForking not defined") unless defined($isForking);

    my $webserver;
    if(!$isForking) {
        $webserver = PageCamel::WebSingle->new();
    } else {
        $webserver = PageCamel::WebPreFork->new();
    }

    return $webserver;
}
1;
__END__

=head1 NAME

PageCamel::Web - Webserver "factory"

=head1 SYNOPSIS

  use PageCamel::Web;

=head1 DESCRIPTION

Depending on the $isForking variable, either returns a single threaded webserver (one request at a time) or a multiforked one.

=head2 new

Make a new webserver instance

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

Copyright (C) 2008-2016 by Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
