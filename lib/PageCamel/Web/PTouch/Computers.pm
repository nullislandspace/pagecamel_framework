package PageCamel::Web::PTouch::Computers;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.7;
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
    return;
}

sub get {
    my ($self, $ua) = @_;

    my $webpath = $ua->{url};
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my @computers;
    {
        my $selsth = $dbh->prepare_cached("SELECT * FROM computers
                                          ORDER BY computer_name")
                or croak($dbh->errstr);
        $selsth->execute or croak($dbh->errstr);
        while((my $computer = $selsth->fetchrow_hashref)) {
            push @computers, $computer;
        }
        $selsth->finish;
        $dbh->rollback;
    }

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{pagetitle},
        webpath         =>  $self->{webpath},
        computers       => \@computers,
        showads => $self->{showads},
    );

    { # Printers and pagecount
        my $selsth = $dbh->prepare_cached("SELECT * FROM ptouch_printers
                                          ORDER BY printer_name")
                or croak($dbh->errstr);
        $selsth->execute or croak($dbh->errstr);
        my @availprinters;
        while((my $availprinter = $selsth->fetchrow_hashref)) {
            push @availprinters, $availprinter;
        }
        $selsth->finish;
        my @availpagecount = 1..10;

        $webdata{AvailPrinters} = \@availprinters;
        $webdata{AvailPageCounts} = \@availpagecount;
    }

    my $mode = $ua->{postparams}->{'mode'} || 'view';
    if($mode eq 'print') {
        my @comps = $ua->{postparams}->{'computer_name'};
        my $printername = $ua->{postparams}->{'print_printername'} || '';
        my $pagecount = $ua->{postparams}->{'print_pagecount'} || '';
        if(@comps && $printername ne '' && $pagecount ne '') {
            foreach my $computer (@computers) {
                if(!contains($computer->{computer_name}, \@comps)) {
                    next;
                }
                my $pristh = $dbh->prepare_cached("INSERT INTO ptouch_queue (printer_name, label_type, labeldata)
                                                  VALUES (?, 'COMPUTER', ?)")
                        or croak($dbh->errstr);
                my @labeldata;
                foreach my $key (qw[computer_name account_user account_password account_domain line_id description net_prod_ip net_line_ip]) {
                    push @labeldata, $computer->{$key};
                }
                my $ok = 1;
                for(1..$pagecount) {
                    if(!$pristh->execute($printername, \@labeldata)) {
                        $ok = 0;
                        last;
                    }
                }
                if(!$ok) {
                    $dbh->rollback;
                } else {
                    $dbh->commit;
                }
            }
        }
    }

    my $template = $self->{server}->{modules}->{templates}->get("ptouch/computers", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}


1;
__END__

=head1 NAME

PageCamel::Web::PTouch::Computers -

=head1 SYNOPSIS

  use PageCamel::Web::PTouch::Computers;



=head1 DESCRIPTION



=head2 new



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
