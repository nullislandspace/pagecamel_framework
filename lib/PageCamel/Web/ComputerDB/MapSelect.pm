package PageCamel::Web::ComputerDB::MapSelect;
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

use PageCamel::Helpers::DBSerialize;
use PageCamel::Helpers::Padding qw(doFPad);
use PageCamel::Helpers::Strings qw(stripString);
use PageCamel::Helpers::URI qw(encode_uri_path);
use JSON::XS;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}



sub register {
    my $self = shift;
    $self->register_webpath($self->{webpath}, "get_select");
    $self->register_webpath($self->{ajaxpath}, "get_points");
    return;
}

# "get_select" actually only displays the available card list, POST
# is done to the main mask to have a smoother workflow without redirects
sub get_select {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $sesh = $self->{server}->{modules}->{$self->{session}};

    my ($getok, $filter) = $sesh->get("MapSelectFilter");
    if($getok || defined($filter)) {
        $filter = dbderef($filter);
        if(!defined($filter)) {
            $filter = '';
        }
    } else {
        $filter = '';
    }

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        webpath        =>  $self->{webpath},
        ajaxpath        =>  $self->{ajaxpath},
        filter      => $filter,
    );

    # Openlayers Map
    foreach my $key (qw[tiles imagepath]) {
        $webdata{$key} = $self->{$key};
    }
    if($webdata{IsAprilFoolsDay}) {
        $webdata{tiles} = $self->{aprilfoolstiles};
    }

    if(!defined($webdata{HeadExtraScripts})) {
        my @tmp;
        $webdata{HeadExtraScripts} = \@tmp;
    }
    if(!defined($webdata{HeadExtraCSS})) {
        my @tmp;
        $webdata{HeadExtraCSS} = \@tmp;
    }
    push @{$webdata{HeadExtraScripts}}, $self->{jspath};
    push @{$webdata{HeadExtraCSS}}, $self->{csspath};


    my $template = $self->{server}->{modules}->{templates}->get("computerdb/mapselect", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);

}

sub get_points {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $sesh = $self->{server}->{modules}->{$self->{session}};

    my $filter = $ua->{postparams}->{'filter'} || '';
    $sesh->set("MapSelectFilter", $filter);

    my $where = '';

    my @columns = qw[computer_name description line_id];

    if($filter ne '') {
        $filter = stripString($filter);
        my @searchparts = split/ /,$filter;

        foreach my $sp (@searchparts)  {
            $sp = stripString($sp);
            my $negate = 0;
            if($sp =~ /^\!/) {
                $negate = 1;
                $sp =~ s/^\!//;
            }
            $sp = stripString($sp);
            next if($sp eq '');

            $sp = $dbh->quote($sp);
            # Insert the percent signs
            $sp =~ s/^\'/\'%/;
            $sp =~ s/\'$/%\'/;

            if($where ne '') {
                $where .= ' AND ';
            }

            my @subclauses;

            if(!$negate) {
                foreach my $col (@columns) {
                    my $subclause = $col . "::text ILIKE $sp";
                    push @subclauses, $subclause;
                }
                $where .= ' ( ' . join(' OR ', @subclauses) . ' ) ';
            } else {
                foreach my $col (@columns) {
                    my $subclause = $col . "::text NOT ILIKE $sp";
                    push @subclauses, $subclause;
                }
                $where .= ' ' . join(' AND ', @subclauses) . ' ';
            }
        }
        if($where ne '') {
            $where = "WHERE $where";
        }

        #print STDERR "Filter: $filter CLAUSE $where\n";

    }


    my $selsth = $dbh->prepare("SELECT * FROM computers $where")
            or croak($dbh->errstr);
    $selsth->execute() or croak($dbh->errstr);
    my @computers;
    while((my $computer = $selsth->fetchrow_hashref)) {
        $computer->{url} = $self->{computerpath} . '/' . encode_uri_path($computer->{computer_name});
        push @computers, $computer;
    }
    $selsth->finish;
    $dbh->rollback;

    my $jsondata = encode_json \@computers;
    return (status => 200,
            type => 'application/json',
            data => $jsondata);

}

1;
__END__

=head1 NAME

PageCamel::Web::ComputerDB::MapSelect -

=head1 SYNOPSIS

  use PageCamel::Web::ComputerDB::MapSelect;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 get_select



=head2 get_points



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
