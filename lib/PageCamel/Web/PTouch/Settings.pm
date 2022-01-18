package PageCamel::Web::PTouch::Settings;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.0;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::DBSerialize;



sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub register {
    my $self = shift;
    $self->register_webpath($self->{webpath}, "get");
    $self->register_defaultwebdata("get_defaultwebdata");
    return;
}

sub get {
    my ($self, $ua) = @_;

    my $webpath = $ua->{url};
    my $seth = $self->{server}->{modules}->{$self->{usersettings}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $selsth = $dbh->prepare_cached("SELECT * FROM ptouch_printers
                                      ORDER BY printer_name")
            or croak($dbh->errstr);
    $selsth->execute or croak($dbh->errstr);
    my @availprinters;
    while((my $availprinter = $selsth->fetchrow_hashref)) {
        push @availprinters, $availprinter;
    }
    $selsth->finish;
    $dbh->rollback;
    my @availpagecount = 1..10;

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{pagetitle},
        webpath         =>  $self->{webpath},
        AvailPrinters   => \@availprinters,
        AvailPageCounts  => \@availpagecount,
        showads => $self->{showads},
    );

    # We don't actually set the Theme into webdata here, this is done during the prerender stage.
    # Also, we don't handle the "select a default theme if non set" case, TemplateCache falls back to
    # its own default theme anyway
    my $mode = $ua->{postparams}->{'mode'} || 'view';
    if($mode eq "setvalue") {
        my $printer = $ua->{postparams}->{'printername'} || '';
        $seth->set($webdata{userData}->{user}, "PTouch::Printer", \$printer);

        my $pagecount = $ua->{postparams}->{'pagecount'} || '';
        $seth->set($webdata{userData}->{user}, "PTouch::PageCount", \$pagecount);

        $webdata{PTouchDefaultPrinter} = $printer;
        $webdata{PTouchDefaultPageCount} = $pagecount;
    }

    my $template = $self->{server}->{modules}->{templates}->get("ptouch/settings", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub get_defaultwebdata {
    my ($self, $webdata) = @_;

    if(!defined($webdata->{userData}) ||
              !defined($webdata->{userData}->{user}) ||
              $webdata->{userData}->{user} eq "") {
        return;
    }

    my $seth = $self->{server}->{modules}->{$self->{usersettings}};

    my (undef, $printer) = $seth->get($webdata->{userData}->{user}, "PTouch::Printer");
    my (undef, $pagecount) = $seth->get($webdata->{userData}->{user}, "PTouch::PageCount");

    if(defined($printer)) {
        $printer = dbderef($printer);
    } else {
        $printer = '';
    }

    if(defined($pagecount)) {
        $pagecount = dbderef($pagecount);
    } else {
        $pagecount = '1';
    }

    $webdata->{PTouchDefaultPrinter} = $printer;
    $webdata->{PTouchDefaultPageCount} = $pagecount;

    return;
}



1;
__END__

=head1 NAME

PageCamel::Web::PTouch::Settings -

=head1 SYNOPSIS

  use PageCamel::Web::PTouch::Settings;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 get



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

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
