package PageCamel::Helpers::WebCommandQueue;
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


use WWW::Mechanize::GZip;
use XML::Simple;

sub new {
    my ($proto, $baseurl) = @_;
    my $class = ref($proto) || $proto;

    my %config = (
        url   => $baseurl,
        mech  => WWW::Mechanize::GZip->new(agent => 'WebCMD Bot'),
    );

    my $self = bless \%config, $class;

    return $self;
}

sub nextcommand {
    my ($self, $command) = @_;

    my $result = $self->{mech}->get($self->{url} . "/getnext/$command");
    if(!$result->is_success) {
        return;
    }

    my $xmldata = $result->content;

    my $cmd = XMLin($xmldata, ForceArray => [ 'argument' ] );

    if(!defined($cmd->{id}) || $cmd->{id} == 0) {
        return;
    } else {
        return $cmd;
    }
}

sub finished {
    my ($self, $commandid, $status) = @_;

    my $result = $self->{mech}->get($self->{url} . "/markdone/$commandid/status");
    if(!$result->is_success) {
        return 0;
    }

    my $xmldata = $result->content;

    my $cmd = XMLin($xmldata);

    if(defined($cmd->{status}) && $cmd->{status} eq "OK") {
        return 1;
    } else {
        return 0;
    }
}

1;
__END__

=head1 NAME

PageCamel::Helpers::WebCommandQueue - client helper for accessing the commandqueue via web.

=head1 SYNOPSIS

  use PageCamel::Helpers::WebCommandQueue;

=head1 DESCRIPTION

Helper to access the commandqueue via a webapi.

=head2 new

Create a new instance.

=head2 nextcommand

Get the next command/job.

=head2 finished

Mark the command/job as finished.

=head1 IMPORTANT NOTE

This module is part of the PageCamel framework. Currently, only limited support
and documentation exists outside my DarkPAN repositories. This source is
currently only provided for your reference and usage in other projects (just
copy&paste what you need, see license terms below).

To see PageCamel in action and for news about the project,
visit my blog at L<https://cavac.at>.

=head1 AUTHOR

Rene Schickbauer, E<lt>cavac@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2016 by Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
