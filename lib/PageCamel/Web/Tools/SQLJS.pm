package PageCamel::Web::Tools::SQLJS;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub reload($self) {
    # Nothing to do.. in here, we only use the template and database module
    return;
}

sub register($self) {
    $self->register_webpath($self->{webpath}, "get");

    return;
}

sub get($self, $ua) {
    my $th = $self->{server}->{modules}->{templates};

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        showads => $self->{showads},
        EnableDB => 1,
    );
    
    my $template;
    my $templateok = 0;

    eval {
        $template = $self->{server}->{modules}->{templates}->get('tools/sqljs', 1, %webdata);
        $templateok = 1;
    };
    if(!$templateok) {
        print STDERR "EVAL FAIL: ", $EVAL_ERROR, "\n";
    }
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => 'text/html',
            data    => $template,
            );
}

sub sitemap($self, $sitemap) {
    push @{$sitemap}, $self->{webpath};

    return;
}

1;
__END__

=head1 NAME

PageCamel::Web::StaticPage -

=head1 SYNOPSIS

  use PageCamel::Web::StaticPage;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 get



=head2 sitemap



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
