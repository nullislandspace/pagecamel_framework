package PageCamel::Web::Tools::Adsense;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.3;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
use Data::Dumper;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);

use MIME::Base64;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub register {
    my $self = shift;
    $self->register_fastredirect("prefilter");
    $self->register_prerender("prerender");
    return;
}

sub prefilter {
    my ($self, $ua) = @_;

    # Remember host for prerender call (no access to $ua there)
    if(defined($self->{domain})) {
        delete $self->{domain};
    }
    if(defined($ua->{headers}->{Host})) {
        $self->{domain} = $ua->{headers}->{Host};
    }
    # Remember host for prerender call (no access to $ua there)
    

    if($ua->{url} !~ /ads\.txt$/) {
        return;
    }
    if(!defined($ua->{headers}->{Host})) {
        return (status => 404);
    }

    if($ua->{method} ne 'GET' && $ua->{method} ne 'HEAD') {
        return (status => 405);
    }

    my $domain = $ua->{headers}->{Host};
    $self->{domain} = $domain;
    print STDERR "Ad Domain: ", $domain, "\n";

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $selsth = $dbh->prepare_cached("SELECT * FROM adverts
                                        WHERE domain_name = ?
                                        AND is_enabled = true")
            or croak($dbh->errstr);
    if(!$selsth->execute($domain)) {
        print STDERR $dbh->errstr, "\n";
        $dbh->rollback;
        return (status => 500);
    }

    my $line = $selsth->fetchrow_hashref;
    $selsth->finish;
    $dbh->commit;

    if(!defined($line)) {
        return (status => 404);
    }

    return (status => 200,
            type => 'text/plain',
            data => $line->{ads_txt},
        );
}

sub prerender {
    my ($self, $webdata) = @_;

    if(!defined($webdata->{showads})) {
        $webdata->{showads} = 0;
    }

    return unless($webdata->{showads});

    return unless defined($self->{domain});

    my $domain = $self->{domain};

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $selsth = $dbh->prepare_cached("SELECT * FROM adverts
                                        WHERE domain_name = ?
                                        AND is_enabled = true")
            or croak($dbh->errstr);
    if(!$selsth->execute($domain)) {
        print STDERR $dbh->errstr, "\n";
        $dbh->rollback;
        return; # No fatal error, just don't show ads
    }

    my $line = $selsth->fetchrow_hashref;
    $selsth->finish;
    $dbh->commit;

    return unless(defined($line));

    $webdata->{AdsHeaderCode} = $line->{header_code};
    $webdata->{AdsSidebarCode} = $line->{sidebar_code};

    return;
}

1;
__END__

=head1 NAME

PageCamel::Web::WebApps -

=head1 SYNOPSIS

  use PageCamel::Web::WebApps;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 crossregister



=head2 get_settings



=head2 prerender



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
