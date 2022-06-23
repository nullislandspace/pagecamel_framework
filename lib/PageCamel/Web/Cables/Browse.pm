package PageCamel::Web::Cables::Browse;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
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

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        webpath    =>  $self->{webpath},
        showads => $self->{showads},
    );

    my $webpath = $ua->{url};
    my $offset = 0;
    if($webpath =~ /\/([0-9]+)$/) {
        $offset = $1;
    }
    $offset = 0 + $offset;
    my $limit = $self->{pagesize};

    my @cables;
    my $sth = $dbh->prepare_cached("SELECT cable_id, logtime, origin_name, security_level
                                   FROM cables
                                   ORDER BY logtime
                                   LIMIT ?
                                   OFFSET ?")
                    or croak($dbh->errstr);

    $sth->execute($limit, $offset) or croak($dbh->errstr);
    my $linecount = 0;
    while((my $cable = $sth->fetchrow_hashref)) {
        $cable->{viewlink} = $self->{viewlink} . "/" . $cable->{cable_id};
        push @cables, $cable;
        $linecount++;
    }
    $sth->finish;

    $webdata{cables} = \@cables;

    if($offset >= $limit) {
        $webdata{backlink} = $self->{webpath} . "/" . ($offset - $limit);
    }

    if($linecount == $limit) {
        $webdata{nextlink} = $self->{webpath} . "/" . ($offset + $limit);
    }

    my $template = $self->{server}->{modules}->{templates}->get("cables/browse", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}


1;
__END__

=head1 NAME

PageCamel::Web::Cables::Browse -

=head1 SYNOPSIS

  use PageCamel::Web::Cables::Browse;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



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
