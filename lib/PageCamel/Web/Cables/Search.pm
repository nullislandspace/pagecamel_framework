package PageCamel::Web::Cables::Search;
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
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::Strings qw[normalizeString];



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
    my $offset = $ua->{postparams}->{'offset'} || 0;
    $offset = 0 + $offset;
    my $limit = $self->{pagesize};
    my $searchterm = $ua->{postparams}->{'searchterm'} || '';
    $searchterm = normalizeString(lc $searchterm);

    if($searchterm ne '') {
        my @cables;

        my $keywords = join(' & ', split(/\W/, $searchterm));

        my $sth = $dbh->prepare_cached("SELECT cable_id, logtime, origin_name, security_level,
                                            ts_headline('english', message, query) AS snippet
                                            FROM cables, to_tsquery(?) query
                                            WHERE english_tsearch \@\@ query
                                            ORDER BY logtime
                                            LIMIT ?
                                            OFFSET ?"
                                        )
            or croak($dbh->errstr);

        $sth->execute($keywords, $limit, $offset) or croak($dbh->errstr);
        my $linecount = 0;
        while((my $cable = $sth->fetchrow_hashref)) {
            $cable->{viewlink} = $self->{viewlink} . "/" . $cable->{cable_id};
            push @cables, $cable;
            $linecount++;
        }
        $sth->finish;

        $webdata{cables} = \@cables;

        if($offset >= $limit) {
            $webdata{backoffset} = $offset - $limit;
        } else {
            $webdata{backoffset} = -1;
        }

        if($linecount == $limit) {
            $webdata{nextoffset} = $offset + $limit;
        } else {
            $webdata{nextoffset} = -1;
        }

        $webdata{hasresults} = 1;
        $webdata{searchterm} = $searchterm;
    }

    my $template = $self->{server}->{modules}->{templates}->get("cables/search", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}


1;
__END__

=head1 NAME

PageCamel::Web::Cables::Search -

=head1 SYNOPSIS

  use PageCamel::Web::Cables::Search;



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
