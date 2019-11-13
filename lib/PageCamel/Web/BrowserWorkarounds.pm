package PageCamel::Web::BrowserWorkarounds;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp;
our $VERSION = 2.4;
use autodie qw( close );
use Array::Contains;
use utf8;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub reload {
    my ($self) = shift;
    # Nothing to do.. in here, we only use the template and database module
    return;
}

sub register {
    my $self = shift;

    $self->register_prefilter("prefilter");
    $self->register_postfilter("postfilter");
    $self->register_defaultwebdata("get_defaultwebdata");
    return;
}


sub prefilter {
    my ($self, $ua) = @_;

    my $webpath = $ua->{url};
    my $userAgent = $ua->{headers}->{'User-Agent'} || "Unknown";

    my $browser = "Unknown";
    if($userAgent =~ /Firefox/) {
        $browser = "Firefox";
    }

    my %browserData = (
        Browser        =>    $browser,
        UserAgent    =>    $userAgent,
    );

    $self->{BrowserData} = \%browserData;

    return;

}
sub postfilter {
    my ($self, $ua, $header, $result) = @_;

    if(!defined($self->{BrowserData}->{Browser})) {
        return;
    } elsif($self->{BrowserData}->{Browser} eq "Firefox") {
        # *** Workarounds for Firefox ***
        if($result->{status} eq "307") {
            # some versions of Firefox make troubles with a 307 resulting
            # from a POST (for example viewselect), it pops
            # up a completly stupid extra YES/NO box.
            # Soo... rewrite to a 303 and also add a HTML-redirect the page
            # instead
            # Of course, in case of POST and then redirecting, the correct return code
            # *IS* a 303, *not* the 307. But strangely enough, only Firefox shows this
            # very annoying behavior.

            my $location = $result->{location};
            $result->{status} = 303;
            $result->{statustext} = "Using HTML redirect for Firefox";

            my %webdata = (
                $self->{server}->get_defaultwebdata(),
                PageTitle           =>  "Redirect",
                ExtraHEADElements    => "<meta HTTP-EQUIV=\"REFRESH\" content=\"3; url=$location\">",
                NextLocation        => $location,
            );

            my $template = $self->{server}->{modules}->{templates}->get("browserworkarounds_redirect", 1, %webdata);
            $result->{data} = $template;
        }
    }

    return;
}

sub get_defaultwebdata {
    my ($self, $webdata) = @_;

    $webdata->{BrowserData} = $self->{BrowserData};
    return;
}

1;
__END__

=head1 NAME

PageCamel::Web::BrowserWorkarounds -

=head1 SYNOPSIS

  use PageCamel::Web::BrowserWorkarounds;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 prefilter



=head2 postfilter



=head2 get_defaultwebdata



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
