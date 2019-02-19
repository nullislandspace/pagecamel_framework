package PageCamel::Web::Cables::View;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.1;
use Fatal qw( close );
use Array::Contains;
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
    $self->register_webpath($self->{webpath}, "get");
    return;
}


sub get {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        webpath    =>  $self->{webpath},
    );

    my $webpath = $ua->{url};
    my $cableid = 0;
    if($webpath =~ /\/([0-9]+)$/) {
        $cableid = $1;
    } else {
        return (status  =>  404);
    }
    $cableid = 0 + $cableid;

    my $sth = $dbh->prepare_cached("SELECT *
                                   FROM cables
                                   where cable_id = ?")
                    or croak($dbh->errstr);

    $sth->execute($cableid) or croak($dbh->errstr);
    my $linecount = 0;
    while((my $cable = $sth->fetchrow_hashref)) {
        $webdata{cable} = $cable;
        $linecount++;
    }
    $sth->finish;

    if($linecount == 0) {
        # Cable not found
        return (status  =>  404);
    }

    my $template = $self->{server}->{modules}->{templates}->get("cables/view", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}


1;
__END__

=head1 NAME

PageCamel::Web::Cables::View -

=head1 SYNOPSIS

  use PageCamel::Web::Cables::View;



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

Copyright (C) 2008-2016 by Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
