package PageCamel::Worker::Logging::PluginBase;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.6;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub register_plugin($self, $funcname, $type, $subtype) {

    print "  $self->{modname} will handle logging for $type / $subtype\n";

    $self->{server}->{modules}->{$self->{scheduler}}->add_plugin($type, $subtype, $self, $funcname);
    return;
}


1;
__END__

=head1 NAME

PageCamel::Worker::Logging::PluginBase - Base module for all logging plugins

=head1 SYNOPSIS

  use PageCamel::Worker::Logging::PluginBase;

=head1 DESCRIPTION

This module is never run directly, but all logging plugins have it as a base.

=head2 new

Create a new instance.

=head2 register_plugin

Function to register a plugin callback in the scheduler

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
