package PageCamel::Web::Logging::Graphs;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 2.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
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

    $self->register_webpath($self->{admin}->{webpath}, "get_admin");
    return;
}

sub get_admin {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{admin}->{pagetitle},
        webpath    =>  $self->{admin}->{webpath},
    );

    my $mustupdate = $ua->{postparams}->{"submitform"} || "0";
    if($mustupdate eq "1") {
        my @graph_ids = @{$ua->{postparams}->{"graph_id"}};
        my $upstmt = "UPDATE logging_reportgraphs SET graph_name=?, title=?, ylabel=?,
                      graph_type=?, cummulate=?, columnnames=?, columnlabels=? WHERE graph_name=? AND device_type=?";
        my $upsth = $dbh->prepare_cached($upstmt) or croak($dbh->errstr);
        my $delstmt = "DELETE FROM logging_reportgraphs WHERE graph_name=? AND device_type=?";
        my $delsth = $dbh->prepare_cached($delstmt) or croak($dbh->errstr);
        my $instmt = "INSERT INTO logging_reportgraphs
                        (graph_name, device_type, title, ylabel, graph_type, cummulate, columnnames, columnlabels)
                        VALUES
                        (?,?,?,?,?,?,?,?)";
        my $insth = $dbh->prepare_cached($instmt) or croak($dbh->errstr);

        foreach my $graph_id (@graph_ids) {
            my $graph_name = $ua->{postparams}->{"graph_name_" . $graph_id} || "";
            my $newname = $ua->{postparams}->{"new_graph_name_" . $graph_id} || "";
            my $devtype = $ua->{postparams}->{"devicetype_" . $graph_id} || "";
            my $title = $ua->{postparams}->{"title_" . $graph_id} || "";
            my $ylabel = $ua->{postparams}->{"ylabel_" . $graph_id} || "";
            my $type = $ua->{postparams}->{"type_" . $graph_id} || "";
            my $cummulate = $ua->{postparams}->{"cummulate_" . $graph_id} || "";
            if($cummulate eq "") {
                $cummulate = 'false';
            } else {
                $cummulate = 'true';
            }
            my $colnames = $ua->{postparams}->{"colnames_" . $graph_id} || "";
            my @columnnames = split /\,/, $colnames;
            my $collabels = $ua->{postparams}->{"collabels_" . $graph_id} || "";
            my @columnlabels = split /\,/, $collabels;

            my $delete = $ua->{postparams}->{"delete_" . $graph_id} || "";

            if($graph_id eq "__NEW__") {
                if($newname ne "") {
                    if($insth->execute($newname, $devtype, $title, $ylabel, $type, $cummulate, \@columnnames, \@columnlabels)) {
                        $dbh->commit;
                    } else {
                        $dbh->rollback;
                    }
                }
            } elsif($delete eq "") {
                if($upsth->execute($newname, $title, $ylabel, $type, $cummulate, \@columnnames, \@columnlabels, $graph_name, $devtype)) {
                    $dbh->commit;
                } else {
                    $dbh->rollback;
                }
            } else {
                if($delsth->execute($graph_name, $devtype)) {
                    $dbh->commit;
                } else {
                    $dbh->rollback;
                }
            }

        }
        $upsth->finish;
        $delsth->finish;
        $insth->finish;
        $dbh->rollback;
    }

    my $stmt = "SELECT * " .
                "FROM logging_reportgraphs " .
                "ORDER BY graph_name, device_type";

    my @graphs;
    my $graphcnt = 0;
    my $sth = $dbh->prepare_cached($stmt) or croak($dbh->errstr);
    $sth->execute or croak($dbh->errstr);

    while((my $graph = $sth->fetchrow_hashref)) {
        $graphcnt++;

        $graph->{id} = $graph->{graph_name} . "__" . $graph->{device_type};
        $graph->{graphcnt} = $graphcnt;

        $graph->{colnames} = join(',', @{$graph->{columnnames}});
        $graph->{collabels} = join(',', @{$graph->{columnlabels}});

        push @graphs, $graph;
    }
    $sth->finish;
    $webdata{graphs} = \@graphs;

    my @devtypes;
    my $dsth = $dbh->prepare_cached("SELECT * FROM enum_logging ORDER BY enumvalue")
            or croak($dbh->errstr);
    $dsth->execute or croak($dbh->errstr);
    while((my $devtype = $dsth->fetchrow_hashref)) {
        push @devtypes, $devtype;
    }
    $dsth->finish;
    $webdata{devtypes} = \@devtypes;

    $dbh->rollback;



    my %graphtypes = (
        lines        => 'Connected lines',
        linespoints    => 'Discrete points',
        area        => 'Filled areas',
        bars        => 'Vertical bars',
        hbars        => 'Horizontal bars',
    );

    my @gtypes;
    foreach my $gkey (sort keys %graphtypes) {
        my %tmp = (
            type    => $gkey,
            label    => $graphtypes{$gkey},
        );
        push @gtypes, \%tmp;
    }
    $webdata{graphtypes} = \@gtypes;

    my $template = $self->{server}->{modules}->{templates}->get("logging/graphs_admin", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

1;
__END__

=head1 NAME

PageCamel::Web::Logging::Graphs -

=head1 SYNOPSIS

  use PageCamel::Web::Logging::Graphs;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 get_admin



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
