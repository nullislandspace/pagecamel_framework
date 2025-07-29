package PageCamel::Radius::Rader;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.7;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Net::Server::Single);

use RADIUS::Dictionary;
use RADIUS::Packet;
use PageCamel::Radius::OATHusers;

sub setConfig($self, $secret, $database) {
    $self->{secret} = $secret;
    $self->{database} = $database;

    return;
}

sub process_request($self) {
    my $prop = $self->{'server'};

    # This is a VERY simple RADIUS authentication server which responds
    # to Access-Request packets with Access-Accept.  This allows anyone
    # to log in.

    # Parse the RADIUS dictionary file (must have dictionary in current dir)
    my $dict = RADIUS::Dictionary->new("dictionary")
      or croak("Couldn't read dictionary: $ERRNO");

    my $um = PageCamel::Radius::OATHusers->new();

    # Get the data
    my $rec = $prop->{udp_data};
    # Unpack it
    my $p = RADIUS::Packet->new($dict, $rec);
    if ($p->code eq 'Access-Request') {
      # Print some details about the incoming request (try ->dump here)
      #print $p->attr('User-Name'), " logging in with password ",
      #      $p->password($secret), "\n";
      #$p->dump;



      # Create a response packet
      my $rp = RADIUS::Packet->new($dict);

      my $service = $p->attr('NAS-Identifier');

      if($um->validate($self->{database}, $p->attr('User-Name'), $p->password($self->{secret}), $service)) {
        $rp->set_code('Access-Accept');
        print "Password OK\n";
      } else {
        $rp->set_code('Access-Reject');
        print "Password FAIL\n";
      }
      $rp->set_identifier($p->identifier);
      $rp->set_authenticator($p->authenticator);
      # (No attributes are needed.. but you could set IP addr, etc. here)
      # Authenticate with the secret and send to the server.
      my $outpacket = auth_resp($rp->pack, $self->{secret});
      $prop->{'client'}->send($outpacket, 0);
      #$s->sendto(auth_resp($rp->pack, $secret), $whence);
    }
    else {
      # It's not an Access-Request
      print "***** Unexpected packet type recieved. ******";
      $p->dump;
    }

    return;
}

1;
__END__

=head1 NAME

PageCamel::Radius::Rader - experimental module for using the PageCamel user managment for RADIUS authentication.

=head1 SYNOPSIS

  use PageCamel::Radius::Rader;

=head1 DESCRIPTION

Experimental module for using the PageCamel user managment for RADIUS authentication.

=head2 setConfig

Set radius secret and database connection to be used.

=head2 process_request

Process an authentication request.

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
