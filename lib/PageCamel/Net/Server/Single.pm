# -*- perl -*-
#
#  PageCamel::Net::Server::Single - PageCamel::Net::Server personality
#
#  $Id$
#
#  Original author:
#  Copyright (C) 2001-2012
#
#    Paul Seamons
#    paul@seamons.com
#    http://seamons.com/
#
#  This fork:
#  Copyright (C) 2016-2017
#
#    Rene Schickbauer
#    cavac@cpan.org
#
#  This package may be distributed under the terms of either the
#  GNU General Public License
#    or the
#  Perl Artistic License
#
#  All rights reserved.
#
################################################################

package PageCamel::Net::Server::Single;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 2.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Net::Server);

sub net_server_type { __PACKAGE__ }

### this module is simple a place holder so that
### PageCamel::Net::Server::MultiType can ask for Single as one of
### the fall back methods (which it does any way).
### Essentially all we are doing here is providing parallelism.

1;

__END__

=head1 NAME

PageCamel::Net::Server::Single - PageCamel::Net::Server personality

=head1 SYNOPSIS

    use base qw(PageCamel::Net::Server::Single);

    sub process_request {
        #...code...
    }

=head1 DESCRIPTION

This module offers no functionality beyond the PageCamel::Net::Server
base class.  This modules only purpose is to provide
parallelism for the MultiType personality.

See L<PageCamel::Net::Server>

=cut
