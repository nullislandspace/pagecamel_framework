package PageCamel::Web::Firewall::EC2Attack;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.5;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);

# Detect a specific attack(?) from Amazon servers. It's always IPv6 with a
# useragent_simplified of "curl" accessing the root path

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub register {
    my $self = shift;
    $self->register_prefilter("prefilter");
    return;
}

sub prefilter {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $webpath = $ua->{url};
    my $userAgent = $ua->{headers}->{'User-Agent'};
    my $host = $ua->{remote_addr};

    return unless(defined($userAgent));

    # Must be CURL
    return unless($userAgent =~ /^curl\//i || $userAgent =~ /pycurl/i);

    # Must be IPv6
    return unless($host =~ /\:/);

    # Must call the root path
    return unless ($webpath eq '/');

    my $sth = $dbh->prepare_cached("INSERT INTO firewall_candidates (ip_address, url, useragent, whois_must_match)
                            VALUES (?, ?, ?, ?)")
        or croak($dbh->errstr);
    if($sth->execute($host, $webpath, $userAgent, 'amazon')) {
        $dbh->commit;
    } else {
        $dbh->rollback;
    }


    return (status  => 403,
            type    => 'text/plain',
            data    => "Detected possible attack. Go away, please!",
    );
}

1;
__END__

=head1 NAME

PageCamel::Web::Firewall::EC2Attack -

=head1 SYNOPSIS

  use PageCamel::Web::Firewall::EC2Attack;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 prefilter



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
