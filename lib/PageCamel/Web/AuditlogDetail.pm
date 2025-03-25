package PageCamel::Web::AuditlogDetail;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.7;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::URI qw[decode_uri_path];

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

sub get($self, $ua) {

    my $th = $self->{server}->{modules}->{templates};
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $webpath = $ua->{url};
    my $urlid = $webpath;
    $urlid =~ s/^$self->{webpath}\///;
    if($urlid eq '') {
        return (status => 404);
    }

    $urlid = decode_uri_path($urlid);
    if(!defined($urlid) || $urlid eq '' || (0 + $urlid) == 0) {
        return (status => 404);
    }
    $urlid = 0 + $urlid;

    my $selsth = $dbh->prepare_cached("SELECT * FROM auditlog WHERE logid = ?")
            or croak($dbh->errstr);

    if(!$selsth->execute($urlid)) {
        $dbh->rollback;
        return (status => 500);
    }
    my $line = $selsth->fetchrow_hashref;
    $selsth->finish;
    $dbh->rollback;

    if(!defined($line)) {
        return (status => 404);
    }

    my @extralines;
    foreach my $xl (@{$line->{extrainfo}}) {
        next unless(defined($xl));

        my ($key, $val) = split /\ \=\ /, $xl, 2;
        if(!defined($val)) {
            ($key, $val) = split /\:\ /, $xl, 2;
        }

        my %temp = (
            name    => $key,
            value   => $val,
        );
        push @extralines, \%temp;
    }

    $line->{extralines} = \@extralines;

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        Data  => $line,
        showads => $self->{showads},
    );

    my $template = $self->{server}->{modules}->{templates}->get('auditlogdetail', 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

1;
__END__

=head1 NAME

PageCamel::Web::AccesslogDetail - Detailview of single auditlog entry

=head1 SYNOPSIS

  use PageCamel::Web::AccesslogDetail;

=head1 DESCRIPTION

Mask to show a detail view of a single auditlog entry

=head2 new

Create a new instance.

=head2 register

Register the webpath.

=head2 get

Get the webmask.

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
