package PageCamel::Helpers::Logging::Graphs;
#---AUTOPRAGMASTART---
use 5.032;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
use feature 'signatures';
no warnings qw(experimental::signatures);
#---AUTOPRAGMAEND---

use GD;
use GD::Simple;
use GD::Graph;
use GD::Graph::area;
use GD::Graph::lines;
use GD::Graph::bars;
use GD::Graph::hbars;
use GD::Graph::linespoints;
use GD::Graph::colour qw(:lists);
use PageCamel::Helpers::DateStrings;
use MIME::Base64;


my ($graphWidth, $graphHeight, $graphHBarHeight) = (900, 400, 650);
my ($smallgraphWidth, $smallgraphHeight) = (200, 100);
my $slidingWindowSize = 4;

my %plugins;
my @paintcolors;
my $colorinit = 0;
my $defaultimagedata;

sub initColors {
    # Make a list of static colors
    my @tempcolors = colour_list(1000);

    @paintcolors = qw[lred dgreen yellow blue purple cyan lgray lgreen gold marine orange pink lbue gray];
    while(scalar @paintcolors < 200) {
        @paintcolors = (@paintcolors, @paintcolors);
    }

    $colorinit = 1;
    return;
}


sub registerPlugin {
    my ($devicetype, $funcref) = @_;

    $plugins{$devicetype} = $funcref;
    return;
}

sub simpleGraph {
    my ($dbh, $devicetype, $graphname, $hostname, $ctime, $starttime) = @_;

    if($starttime eq '-- ::') {
        # Compensate for datetimepicker mask when field is empty
        $starttime = '';
    }


    if(defined($plugins{$devicetype})) {
        return $plugins{$devicetype}->($dbh, $devicetype, $graphname, $hostname, $ctime, $starttime);
    }

    my $selstmt = "SELECT * FROM logging_reportgraphs
                    WHERE device_type = ?
                    AND graph_name = ?";
    my $selsth = $dbh->prepare_cached($selstmt)
            or croak($dbh->errstr);
    $selsth->execute($devicetype, $graphname) or croak($dbh->errstr);
    my $graph = $selsth->fetchrow_hashref;
    $selsth->finish;


    if(!defined($graph)) {
        return;
    }

    my $table = 'logging_log_' . lc($devicetype);

    return genGraph($dbh, $graph, $table, $hostname, $ctime, $starttime);
}

sub genGraph {
    my ($dbh, $graph, $table, $host, $ctime, $starttime) = @_;

    # Starttime is the time defining when the graph starts. If it is not defined, and endtime of
    # now() is presumed and starttime is now() - $timeframe
    # starttime is an ISO timestring, as accepted my PostgreSQL.

    my ($timeframe, $precision, $numElements) = parseCTime($ctime);

    my $fastQuery = 0;
    if(!defined($starttime) || $starttime eq '') {
        $starttime = offsetISODate(getISODate(), 0 - $timeframe);
    }
    my $endtime = offsetISODate($starttime, $timeframe);

    # Prepare various dynamic data storages
    my @cols;
    my @pgcols = ("displaydate");
    my @tmp1;
    my %stor = (displaydate => \@tmp1);
    foreach my $column (@{$graph->{columnnames}}) {
        my @tmp2;
        $stor{"sum_" . $column} = \@tmp2;
        if($column =~ /_ok$/) {
            push @cols, "sum(((" . $column . "::integer)*100))/count(*) as sum_" . $column;
        } else {
            push @cols, "sum($column)/count(*) as sum_" . $column;
        }
        push @pgcols, "sum_" . $column;
    }

    # Read data from database
    my ($stmt, $sth);

    # if starttime is empty (of the last datasets counting back from now() are used), which is the default use,
    # we use a simple statement and use prepare_cached for speed. If we use a specific starttime, we have to do some
    # extra math to get the right data. This is also usually a one-of calculation for each specific starttime, so
    # we do *not* cache the statement to save some precious server resources in the long run

    $stmt = "SELECT displaydate_" . $ctime . " AS displaydate,
        " . join(',', @cols) . "
        FROM $table
        WHERE hostname = ?
        AND logtime >= ?
        AND logtime < ?
        group by  displaydate_" . $ctime . "
        order by displaydate_" . $ctime;

    $sth = $dbh->prepare_cached($stmt) or croak($dbh->errstr);

    #print "** $stmt **\n";
    $sth->execute($host, $starttime, $endtime) or croak($dbh->errstr);
    my %datarows;
    my $coredate = '';
    while((my $row = $sth->fetchrow_hashref)) {
        my $nicedate = $row->{displaydate};
        $nicedate =~ s/\+\d\d$//o;
        $row->{displaydate} = $nicedate;
        $datarows{$nicedate} = $row;
        # Make core date always the last date and add to the back (incl. filling in missing pieces)
        if($coredate eq '') {
            $coredate = $nicedate;
        }
       }
    $sth->finish;

    return calcGraph($dbh, $graph, $table, $host, $ctime, $starttime, $coredate, \%datarows);
}


sub calcGraph { ## no critic (Subroutines::ProhibitManyArgs)
    my ($dbh, $graph, $table, $host, $ctime, $starttime, $coredate, $datarows, $disable_legend) = @_;

    if(!$colorinit) {
        initColors();
    }


    if(!defined($disable_legend)) {
        $disable_legend = 0;
    }

    my ($timeframe, $precision, $numElements) = parseCTime($ctime);

    my @pgcols = ("displaydate");
    my @tmp1;
    my %stor = (displaydate => \@tmp1);
    foreach my $column (@{$graph->{columnnames}}) {
        push @pgcols, "sum_" . $column;
    }

    my $datecount = 1;
    if(!defined($coredate) || $coredate eq '') {
        $coredate = getISODate();
    }

    my @alldates = ($coredate);
    while($datecount < $numElements) {
        $coredate = offsetISODate($coredate, $precision);
        push @alldates, $coredate;
        $datecount++;
    }

    my $calcslider = 0;
    if($graph->{graph_type} =~ /lines/ && $graph->{cummulate}) {
        # Special case: If the graph type is lines or linespoints and cummulate is set
        # (which is normally not possible), we assume that there are only two data
        # sets: The "real" value and a sliding average we calculate in THIS function.
        # We assume that both sets are defined in graph, as "data" and "slider". The
        # slider does not need to hold values, we calculate them here.

        $graph->{cummulate} = 0;
        $calcslider = 1;
    }

    my ($ymin, $ymax);
    my @slider;
    foreach my $rowdate (@alldates) {
        my $nicedate = $rowdate;
        $nicedate =~ s/\+\d\d$//o;

        if(defined($datarows->{$rowdate})) {
            my $row = $datarows->{$rowdate};

            if($calcslider) {
                push @slider, $row->{sum_data};
                if((scalar @slider) > $slidingWindowSize) {
                    shift @slider;
                }
                my $avg = 0;
                foreach my $slid (@slider) {
                    $avg += $slid;
                }
                $avg = $avg / (scalar @slider);
                $row->{sum_slider} = $avg;
            }

            my $sum = 0;
            foreach my $pgcol (@pgcols) {
                if($pgcol eq 'displaydate') {
                    push @{$stor{$pgcol}}, $nicedate;
                } else {
                    if($graph->{cummulate}) {
                        push @{$stor{$pgcol}}, abs($row->{$pgcol});
                        $sum += abs($row->{$pgcol});
                    } else {
                        push @{$stor{$pgcol}}, $row->{$pgcol};
                    }
                }
                next if($pgcol !~ /^sum_/);
                    my $val = $row->{$pgcol};
                    if(!defined($ymin)) {
                        $ymin = $val;
                        $ymax = $val;
                    } elsif($ymin > $val) {
                        $ymin = $val;
                    } elsif($ymax < $val) {
                        $ymax = $val;
                    }
            }

            # For cummulated graphs, we need the SUM of all columns to work out ymin/ymax
            if($graph->{cummulate}) {
                if(!defined($ymin)) {
                    $ymin = $sum;
                    $ymax = $sum;
                } elsif($ymin > $sum) {
                    $ymin = $sum;
                } elsif($ymax < $sum) {
                    $ymax = $sum;
                }
            }
        } else {
            # Push a dummy row, fix min/max stuff

            # The expeption here is if we calculate a sliding average
            # and usezero is set. In this case, we need to consider unavailable
            # data within our average.
            if($calcslider) {
                push @{$stor{displaydate}}, $nicedate;
                push @{$stor{sum_data}}, 0;
                push @slider, 0;
                if((scalar @slider) > $slidingWindowSize) {
                    shift @slider;
                }
                my $avg = 0;
                foreach my $slid (@slider) {
                    $avg += $slid;
                }
                $avg = $avg / (scalar @slider);
                push @{$stor{sum_slider}}, $avg;
                if($ymin > $avg) {
                    $ymin = $avg;
                }
                if($ymax < $avg) {
                    $ymax = $avg;
                }
            } else {
                foreach my $pgcol (@pgcols) {
                    if($pgcol eq "displaydate") {
                        push @{$stor{$pgcol}}, $nicedate;
                    } else {
                        if(defined($graph->{usezero}) && $graph->{usezero}) {
                            push @{$stor{$pgcol}}, 0;
                            if($ymin > 0) {
                                $ymin = 0;
                            }
                            if($ymax < 0) {
                                $ymax = 0;
                            }
                        } else {
                            push @{$stor{$pgcol}}, undef;
                        }
                    }
                }
            }
        }
    }

    # Sanitize ymin/ymax -> we ALWAYS want y==0 to show up
    if(!defined($ymin)) {
        return defaultImage();
    } elsif($ymin > 0) {
        #$ymin = 0;
    }

    if(!defined($ymax)) {
        return defaultImage();
    } elsif($ymax < 0) {
        #$ymax = 0;
    }

    if($ymin == $ymax) {
        if($ymax == 0) {
            $ymax = 1;
        } elsif($ymax < 0) {
            $ymax = 0;
        } else {
            $ymin = 0;
        }
    } elsif($ymin > 0 && $ymax > 0) {
        $ymin = 0;
    } elsif($ymin < 0 && $ymax < 0) {
        $ymax = 0;
    }

    # Prepare data for painting
    my @graphdata;
    foreach my $pgcol (@pgcols) {
        push @graphdata, $stor{$pgcol};
    }
    my @legend = @{$graph->{columnlabels}};
    my $classname = $graph->{graph_type};

    # Get correct class and set some default values
    my $paint;

    if($classname eq 'lines') {
        $paint = GD::Graph::lines->new($graphWidth, $graphHeight);
    } elsif($classname eq 'linespoints') {
        $paint = GD::Graph::linespoints->new($graphWidth, $graphHeight);
    } elsif($classname eq 'area') {
        $paint = GD::Graph::area->new($graphWidth, $graphHeight);
    } elsif($classname eq 'bars') {
        $paint = GD::Graph::bars->new($graphWidth, $graphHeight);
    } elsif($classname eq 'hbars') {
        $paint = GD::Graph::hbars->new($graphWidth, $graphHBarHeight);
    }

    if(!$disable_legend) {
        $paint->set_legend(@legend);
    } else {
        $paint->set_legend();
    }


    $paint->set(
        #'dclrs' => [ qw(lgreen blue red purple orange lred green pink dyellow) ],
        'dclrs' => [@paintcolors],
        'title' => $graph->{title} . " / $ctime / $host",
        'x_label' => 'Time',
        'y_label' => $graph->{ylabel},
        'long_ticks' => 1,
        'tick_length' => 0,
        'x_ticks' => 0,
        'x_label_position' => .5,
        'y_label_position' => .5,

        'bgclr' => 'white',
        'transparent' => 0,

        'y_tick_number' => 10,
        'y_number_format' => '%d',
        'y_max_value' => $ymax,
        'y_min_value' => $ymin,
        #'y_plot_values' => 1,
        'x_plot_values' => 1,

        'zero_axis' => 1,
        'lg_cols' => 7,
        'accent_treshold' => 100_000,
    );

    if($graph->{cummulate}) {
        $paint->set(
            'cumulate' => 2,
        );
    }

    if($classname ne "hbars") {
        $paint->set(
            'x_labels_vertical'=> 1,
        );
    }

    if($classname eq "lines") {
        if($calcslider) {
            $paint->set(
                'line_width'=> 5,
            );
        } else {
            $paint->set(
                'line_width'=> 2,
            );
        }
    }

    $paint->plot(\@graphdata);

    my $img = $paint->gd->png();

    return $img;
}

sub defaultImage {

    return $defaultimagedata;

}

sub parseCTime {
    my ($ctime) = @_;

    my $precision; # in seconds
    my $timeframe; # in seconds
    my $numElements; # how many elements do we expect in the graph

    if($ctime eq 'hour') {
        $timeframe = 60*60; # 1 hour
        $precision = 60; # 1 minute
    } elsif($ctime eq 'shift') {
        $timeframe = 60*60*8; # 8 hours
        $precision = 60*10; # 10 minutes
    } elsif($ctime eq 'day') {
        $timeframe = 60*60*24; # 1 day
        $precision = 1800; # 30 minutes
    } elsif($ctime eq 'week') {
        $timeframe = 60*60*24*7; # 7 day 604800
        $precision = 14_400; # 4 hours
    } elsif($ctime eq 'month') {
        $timeframe = 60*60*24*30; # 30 days
        $precision = 43_200; # 12 hours
    } elsif($ctime eq 'year') {
        $timeframe = 60*60*24*365; # 365 days
        $precision = 432_000; # 5 days
    } elsif($ctime eq 'doubleyear') {
        $timeframe = 60*60*24*365*2; # 2 years
        $precision = 864_000; # 10 days
    }

    $numElements = int($timeframe/$precision);
    if(($timeframe % $precision) > 0) {
        $numElements++;
    }
    return ($timeframe, $precision, $numElements);
}

$defaultimagedata = decode_base64('
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
K3mKF9R4/w8lrGvSN7XdvwAAAABJRU5ErkJggg==
');


1;
__END__

=head1 NAME

PageCamel::Helpers::Logging::Graphs - internal module to paint the Graphs in Logging reports.

=head1 SYNOPSIS

  use PageCamel::Helpers::Logging::Graphs;

=head1 DESCRIPTION

This module needs a complete rewrite, because, while quite efficient, it's ugly, unreadable and just bad coding. Sorry about that.

=head2 initColors

Don't ask.

=head2 registerPlugin

Allow sub-plugins to register for actually providing specific data sets.

=head2 simpleGraph

Don't ask.

=head2 genGraph

Don't ask.

=head2 calcGraph

Don't ask.


=head2 defaultImage

Return the default image when rendering failed for some reason.

=head2 parseCTime

Don't ask.

=head1 IMPORTANT NOTE

This module is part of the PageCamel framework. Currently, only limited support
and documentation exists outside my DarkPAN repositories. This source is
currently only provided for your reference and usage in other projects (just
copy&paste what you need, see license terms below).

To see PageCamel in action and for news about the project,
visit my blog at L<https://cavac.at>.

=head1 AUTHOR

Rene Schickbauer, E<lt>cavac@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
