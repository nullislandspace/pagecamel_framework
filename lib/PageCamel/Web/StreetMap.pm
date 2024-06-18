package PageCamel::Web::StreetMap;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
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
    $self->register_webpath($self->{webpath}, "get");

    return;
}

sub crossregister($self) {

    if($self->{public}) {
        $self->register_public_url($self->{webpath});
    }

    return;
}

sub get($self, $ua) {


    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $th = $self->{server}->{modules}->{templates};

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        PostLink    =>  $self->{webpath},
        showads => $self->{showads},
    );

    foreach my $key (qw[tiles minZoomLevel maxZoomLevel bounds center centerzoom imagepath]) {
        $webdata{$key} = $self->{$key};
    }

    if(!defined($webdata{HeadExtraScripts})) {
        my @tmp;
        $webdata{HeadExtraScripts} = \@tmp;
    }
    push @{$webdata{HeadExtraScripts}}, $self->{jspath};

    if(!defined($webdata{HeadExtraCSS})) {
        my @tmp;
        $webdata{HeadExtraCSS} = \@tmp;
    }
    push @{$webdata{HeadExtraCSS}}, $self->{csspath};


    my $template = $self->{server}->{modules}->{templates}->get("streetmap", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

1;
__END__

=head1 NAME

PageCamel::Web::StreetMap -

=head1 SYNOPSIS

  use PageCamel::Web::StreetMap;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 crossregister



=head2 get



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
