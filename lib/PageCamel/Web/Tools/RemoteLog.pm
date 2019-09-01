package PageCamel::Web::Tools::RemoteLog;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.2;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);

use IO::Socket::INET;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub register {
    my $self = shift;
    $self->register_remotelog("log");

    return;
}

sub log { ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my ($self, $logdata) = @_;

    if(!defined($self->{socket})) {
        $self->{socket} = IO::Socket::INET->new(
            PeerAddr    => $self->{host},
            PeerPort    => $self->{port},
            Proto       => 'udp',
        ) or croak("Can't create UDP socket for logging: $ERRNO\n");
    }

    my $webpath = $logdata->{webpath} . '';
    if(length($webpath) > 30) {
        $webpath = substr($webpath, 0, 27) . '...';
    }

    my $data = $logdata->{result} . "\t" .
                $logdata->{method} . "\t" .
                $logdata->{client} . "\t" .
                $webpath . "\t" .
                $logdata->{timetaken} . "\n";
    $self->{socket}->send($data);

    return;

}

sub DESTROY {
    my ($self) = @_;

    if(defined($self->{socket})) {
        $self->{socket}->close();
        delete $self->{socket};
    }

    return;
}

1;
__END__

=head1 NAME

PageCamel::Web::Tools::RemoteLog -

=head1 SYNOPSIS

  use PageCamel::Web::Tools::RemoteLog;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 log



=head2 DESTROY



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
