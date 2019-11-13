package PageCamel::Web::Lists::DNSBlocks;
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

sub register {
    my ($self) = @_;
    $self->register_webpath($self->{webpath}, "get");

    if(defined($self->{sitemap}) && $self->{sitemap}) {
        $self->register_sitemap('sitemap');
    }

    return;
}

sub get {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my @lines = ('# ' . $self->{prefixline});
    my $selsth = $dbh->prepare_cached("SELECT domain_match
                                        FROM nameserver_forcenxdomain
                                        WHERE is_regex = false
                                        ORDER BY domain_match")
            or return(status => 500);

    if(!$selsth->execute()) {
        $dbh->rollback;
        return(status => 500);
    }
    while((my $line = $selsth->fetchrow_hashref)) {
        push @lines, '0.0.0.0 ' . $line->{domain_match};
    }
    $selsth->finish;
    $dbh->commit;

    my $list = join("\n", @lines);


    return (status  =>  200,
            type    => 'text/plain',
            data    => $list,
            expires         => $self->{expires},
            cache_control   =>  $self->{cache_control},
            );
}

sub sitemap {
    my ($self, $sitemap) = @_;

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

Copyright (C) 2008-2019 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
