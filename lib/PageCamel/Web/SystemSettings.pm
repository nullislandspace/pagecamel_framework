package PageCamel::Web::SystemSettings;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule PageCamel::Helpers::SystemSettings);
use PageCamel::Helpers::DateStrings;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub register($self) {
    if(defined($self->{webpath})) {
        $self->register_webpath($self->{webpath}, "getEdit");
    }
    return;
}

sub reload($self) {

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    $self->initDB();

    my $sth = $dbh->prepare_cached("SELECT * FROM system_settings")
                    or croak($dbh->errstr);

    $sth->execute()
            or croak($dbh->errstr);

    while((my $row = $sth->fetchrow_hashref)) {
        my $memhname = "SystemSettings::" . $row->{modulename} . "::" . $row->{settingname};
        $memh->set($memhname, $row);
    }

    $sth->finish;
    $dbh->rollback;

    $memh->set("SystemSettings::lastUpdate", time);

    return;
}

# After configuration, switch to soft updates (e.g. only update database when clacks cached value differs from new value)
sub endconfig($self) {

    $self->set_softupdates(1);
    
    return;
}


sub getEdit($self, $ua) {

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $mode = $ua->{postparams}->{"mode"} || "view";
    if($mode eq "change") {
        my $selsth = $dbh->prepare_cached("SELECT * FROM system_settings WHERE is_hidden = false")
                    or croak($dbh->errstr);
        $selsth->execute or croak($dbh->errstr);
        my @sets;
        while((my $dataset = $selsth->fetchrow_hashref)) {
            push @sets, $dataset;
        }
        $selsth->finish;

        my $upsth = $dbh->prepare_cached("UPDATE system_settings
                                         SET settingvalue = ?,
                                         description = ?
                                         WHERE modulename = ?
                                         AND settingname = ?")
                or croak($dbh->errstr);

        foreach my $dataset (@sets) {
            my $basename = $dataset->{modulename} . '::' . $dataset->{settingname};
            my $newvalue = $ua->{postparams}->{$basename . "::settingvalue"};
            my $oldvalue = $ua->{postparams}->{$basename . "::oldsettingvalue"};
            my $newdesc = $ua->{postparams}->{$basename . "::description"};
            my $olddesc = $ua->{postparams}->{$basename . "::olddescription"};
            my $displaytype = $ua->{postparams}->{$basename . "::displaytype"};

            if(!defined($oldvalue) || !defined($newdesc) || !defined($olddesc)) {
                next;
            }

            if($dataset->{fieldtype} eq "bool") {
                if($newvalue eq "1" || $newvalue eq "on") {
                    $newvalue = "1";
                } else {
                    $newvalue = "0";
                }
            }

            if($dataset->{fieldtype} eq "number") {
                $newvalue =~ s/\,//g; # remove thousand-comma inserted by autonumeric
            }

            if($displaytype eq 'textarea') {
                $newvalue =~ s/\r//g;
            }

            if($newvalue ne $oldvalue || $newdesc ne $olddesc) {
                $upsth->execute($newvalue, $newdesc, $dataset->{modulename}, $dataset->{settingname})
                        or croak($dbh->errstr);

                $dataset->{settingvalue} = $newvalue;
                $dataset->{description} = $newdesc;
                my $memhname = "SystemSettings::" . $dataset->{modulename} . "::" . $dataset->{settingname};
                print STDERR "Updating $memhname\n";

                $memh->set($memhname, $dataset);
            }

        }
        $dbh->commit;
        $memh->set("SystemSettings::lastUpdate", time);

    }


    # Read defaultwebdata *AFTER* Updating
    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        webpath    =>  $self->{webpath},
        showads => $self->{showads},
    );

    my $stmt = "SELECT * " .
                "FROM system_settings " .
                "WHERE is_hidden = false " .
                "ORDER BY modulename, settingname";

    my @settings;
    my $sth = $dbh->prepare_cached($stmt) or croak($dbh->errstr);

    $sth->execute or croak($dbh->errstr);
    while((my $setting = $sth->fetchrow_hashref)) {
        my $displaytype = $setting->{fieldtype};
        my %hints;
        if(defined($setting->{processinghints})) {
            foreach my $line (@{$setting->{processinghints}}) {
                if($line =~ /^type\=(.*)/o) {
                    $displaytype = $1;
                }
                if($line =~ /(.*)\=(.*)/) {
                    $hints{$1} = $2;
                }
            }
            $setting->{hints} = \%hints;
            if(defined($setting->{value_min})) {
                $setting->{value_min_display} = 0 + $setting->{value_min};
            }
            if(defined($setting->{value_max})) {
                $setting->{value_max_display} = 0 + $setting->{value_max};
            }
        }
        $setting->{displaytype} = $displaytype;
        push @settings, $setting;
    }
    $sth->finish;
    $dbh->rollback;

    $webdata{settings} = \@settings;

    my $template = $self->{server}->{modules}->{templates}->get("systemsettings", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}


1;
__END__

=head1 NAME

PageCamel::Web::SystemSettings -

=head1 SYNOPSIS

  use PageCamel::Web::SystemSettings;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 reload



=head2 getEdit



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
