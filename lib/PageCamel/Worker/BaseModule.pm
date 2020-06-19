package PageCamel::Worker::BaseModule;
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
use Sys::Hostname;



sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $hname = hostname;

    my $self = bless \%config, $class;

    if(defined($self->{hosts}->{$hname})) {
        print "   Host-specific configuration for '$hname'\n";
        foreach my $keyname (keys %{$self->{hosts}->{$hname}}) {
            $self->{$keyname} = $self->{hosts}->{$hname}->{$keyname};
        }
    }

    return $self;
}

sub register {
    # register now optional in modules
    return;
}

sub reload {
    # reload now optional in modules
    return;
}

sub crossregister {
    # crossregister is purely optional
    return;
}

sub register_worker {
    my ($self, $funcname) = @_;

    $self->{server}->add_worker($self, $funcname);
    return;
}

sub register_cleanup {
    my ($self, $funcname) = @_;

    $self->{server}->add_cleanup($self, $funcname);
    return;
}

sub endconfig {
    # Nothing to do by default
    return;
}

sub newClacksFromConfig {
    my ($self, $clconf) = @_;

    my $socket = $clconf->get('socket');
    my $clacks;
    if(defined($socket) && $socket ne '') {
        $clacks = Net::Clacks::Client->newSocket($socket, $clconf->get('user'), $clconf->get('password'), $self->{PSAPPNAME} . ':' . $self->{modname});
    } else {
        $clacks = Net::Clacks::Client->new($clconf->get('host'), $clconf->get('port'), $clconf->get('user'), $clconf->get('password'), $self->{PSAPPNAME} . ':' . $self->{modname});
    }

    return $clacks;
}

1;
__END__

=head1 NAME

PageCamel::Worker::BaseModule -

=head1 SYNOPSIS

  use PageCamel::Worker::BaseModule;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 reload



=head2 crossregister



=head2 register_worker



=head2 register_cleanup



=head2 endconfig



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
