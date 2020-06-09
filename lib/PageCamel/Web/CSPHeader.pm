package PageCamel::Web::CSPHeader;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::FileSlurp qw(slurpBinFile);
use Crypt::Digest::SHA256 qw(sha256_b64);

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub register {
    my $self = shift;
    $self->register_postfilter("postfilter");
    return;
}

sub reload {
    my ($self) = @_;

    my @headerparts;
    my %defaultheaders;
    foreach my $header (@{$self->{headers}->{header}}) {
        my $hpart = $header->{type} . ' ' . $header->{value};
        $defaultheaders{$header->{type}} = $hpart;
        
        push @headerparts, $hpart;
    }
    my $csp = join('; ', @headerparts);
    $self->{csp}->{DEFAULT} = $csp;

    foreach my $exception (@{$self->{exceptions}->{item}}) {
        my $url = $exception->{url};
        my %urlheaders;
        foreach my $key (keys %defaultheaders) {
            $urlheaders{$key} = $defaultheaders{$key};
        }
        foreach my $header (@{$exception->{header}}) {
            my $hpart = $header->{type} . ' ' . $header->{value};
            $urlheaders{$header->{type}} = $hpart;
        }
        my @exparts;
        foreach my $key (keys %urlheaders) {
            push @exparts, $urlheaders{$key};
        }
        my $excsp = join('; ', @exparts);
        $self->{csp}->{$url} = $excsp;
    }

    return;
}

sub postfilter {
    my ($self, $ua, $header, $result) = @_;
    
    my $cspname = 'DEFAULT';
    if(defined($self->{csp}->{$ua->{url}})) {
        $cspname = $ua->{url};
    } elsif(defined($ua->{UseUnsafeCVCEditor}) && $ua->{UseUnsafeCVCEditor} && defined($self->{csp}->{UseUnsafeCVCEditor})) {
        $cspname = $ua->{UseUnsafeCVCEditor};
    } elsif(defined($ua->{UseUnsafeMercurialProxy}) && $ua->{UseUnsafeMercurialProxy} && defined($self->{csp}->{UseUnsafeMercurialProxy})) {
        $cspname = $ua->{UseUnsafeMercurialProxy};
    } elsif(defined($ua->{UseUnsafeDataTablesInline}) && $ua->{UseUnsafeDataTablesInline} && defined($self->{csp}->{UseUnsafeDataTablesInline})) {
        $cspname = $ua->{UseUnsafeDataTablesInline};
    }

    $header->{'-Content-Security-Policy'} = $self->{csp}->{$cspname};

    return;
}

1;
__END__

=head1 NAME

PageCamel::Web::ExtraHTTPHeaders -

=head1 SYNOPSIS

  use PageCamel::Web::CSPHeader;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 postfilter



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
