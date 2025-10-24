package PageCamel::Web::ListAndEdit::ASpell;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::URI qw(decode_uri_part);
use Text::Aspell;
use PageCamel::Helpers::Strings qw[normalizeString];

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub register($self) {
    $self->register_webpath($self->{webpath}, "get", 'GET', 'POST');

    return;
}

sub get($self, $ua) {
    my $th = $self->{server}->{modules}->{templates};

    my $rawdata = $ua->{postparams}->{'textinputs[]'};
    my $checker = Text::Aspell->new;
    $checker->set_option('lang', 'en_US');
    $checker->set_option('sug-mode', 'fast');

    my $decoded = decode_uri_part($rawdata);
    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
        my $temp = decode_utf8($decoded);
        $decoded = $temp;
    };
    if($EVAL_ERROR) {
        print STDERR "Warning: $EVAL_ERROR\n";
    }

    # Remove tags
    $decoded =~ s/<[^>]+>/ /g;
    my @declines = split/\n/, $decoded;

    my @results;
    my $idx=0;
    foreach my $decline (@declines) {
        $decline = normalizeString($decline);
        my @parts = split/\ /,$decline;
        foreach my $part (@parts) {
            next if($checker->check($part));

            my @suggestions = $checker->suggest($part);
            my $sugarray = '';
            if(scalar @suggestions) {
                $sugarray = "#" . join("#,#", @suggestions) . "#"; # Use temp quote marks, so we can quote() the false ones
                $sugarray =~ s/\'/\\\'/g;
                $sugarray =~ s/\#/\'/g;
            }
            my %result = (
                idx => $idx,
                word => $part,
                suggestions => $sugarray,
            );
            push @results, \%result;
            $idx++;
        }
    }


    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        PostLink        =>  $self->{webpath},
        rawdata => $rawdata,
        results => \@results,
        showads => $self->{showads},
    );


    my $template = $th->get('listandedit/aspell', 0, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

1;
__END__

=head1 NAME

PageCamel::Web::ASpell - server side module for blog editor spell checking

=head1 SYNOPSIS

  use PageCamel::Web::ASpell;

=head1 DESCRIPTION

Experimental module implementing the server side of the cvceditor spellcheck plugin.

=head2 new

Create a new instance.

=head2 register

Register the "get" callback

=head2 get

Create a page with spellcheck suggestions.

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
