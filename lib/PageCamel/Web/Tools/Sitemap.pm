package PageCamel::Web::Tools::Sitemap;
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
use PageCamel::Helpers::DBSerialize;
use PageCamel::Helpers::FileSlurp qw[slurpBinFile];

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub register($self) {
    $self->register_webpath($self->{webpath}, "get", qw[GET HEAD]);
    return;
}

sub get($self, $ua) {
    my $th = $self->{server}->{modules}->{templates};

    my $baseurl = 'http://';
    if($self->{usessl}) {
        $baseurl = 'https://';
    }

    if(defined($ua->{headers}->{Host}) && $ua->{headers}->{Host} ne '') {
        $baseurl .= $ua->{headers}->{Host};
    } else {
        $baseurl .= $self->{defaulthost};
    }

    my $urls = $self->{server}->get_sitemap;
    push @{$urls}, @{$self->{extraurls}->{item}};

    my %webdata = (
        URLS    => $urls,
        BaseURL => $baseurl,
    );

    my $urlcount = scalar @{$urls};
    print STDERR "URLCOUNT: $urlcount\n";

    my $template = $th->get("tools/sitemap", 0, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/xml",
            data    => $template,
            expires         => $self->{expires},
            cache_control   =>  $self->{cache_control},
    );
}


1;
__END__

=head1 NAME

PageCamel::Web::Tools::Sitemap -

=head1 SYNOPSIS

  use PageCamel::Web::Tools::Sitemap;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 get_frame



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
