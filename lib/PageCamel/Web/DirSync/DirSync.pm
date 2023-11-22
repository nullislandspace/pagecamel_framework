package PageCamel::Web::DirSync::DirSync;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.3;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);

use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::Padding qw(doFPad);
use PDF::Report;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub reload($self) {
    # Nothing to do
    return;
}

sub register($self) {
    $self->register_webpath($self->{diredit}->{webpath}, "get_edit");
    $self->register_webpath($self->{dirselect}->{webpath}, "get_select");
    return;
}

# "get_select" actually only displays the available card list, POST
# is done to the main mask to have a smoother workflow without redirects
sub get_select($self, $ua) {

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $mode = $ua->{postparams}->{'mode'} || 'view';

    if($mode eq "view") {
        my $sth = $dbh->prepare_cached("SELECT ds.*, date_trunc('second', last_sync) as last_sync_trunc,
                            ss.description AS sync_server_longname
                            FROM dirsync ds, enum_dirsyncserver ss
                            WHERE ds.sync_server = ss.enumvalue
                            ORDER BY sync_name")
                    or croak($dbh->errstr);
        my @dirs;

        if($sth->execute) {
            while((my $line = $sth->fetchrow_hashref)) {
                push @dirs, $line;
            }
        }

        my %webdata =
        (
            $self->{server}->get_defaultwebdata(),
            PageTitle   =>  $self->{dirselect}->{pagetitle},
            webpath     =>  $self->{dirselect}->{webpath},
            dirs        =>  \@dirs,
            showads => $self->{showads},
        );

        my $template = $self->{server}->{modules}->{templates}->get("dirsync/dirsync_select", 1, %webdata);
        return (status  =>  404) unless $template;
        return (status  =>  200,
                type    => "text/html",
                data    => $template);
    } else {
        return $self->get_edit($ua);
    }
}

# "get_select" actually only displays the available card list, POST
# is done to the main mask to have a smoother workflow without redirects
sub get_edit($self, $ua) {

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $old_sync_name = $ua->{postparams}->{'old_sync_name'} || '';

    my %defaultdir = (
        sync_name   => '',
        old_sync_name   => $old_sync_name,
        source_dir      => '',
        destination_dir => '',
        sync_time       => '',
        max_age_days    => '',
        sync_server    => 'PAGECAMEL',
    );

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{diredit}->{pagetitle},
        webpath     =>  $self->{diredit}->{webpath},
        dir        =>  \%defaultdir,
        showads => $self->{showads},
    );

    my $mode = $ua->{postparams}->{'mode'} || 'new';

    if($mode eq 'edit') {
        my $upsth = $dbh->prepare_cached("UPDATE dirsync
                            SET sync_name = ?,
                            source_dir = ?,
                            destination_dir = ?,
                            sync_time = ?,
                            max_age_days = ?,
                            sync_server = ?
                            WHERE sync_name = ?")
                or croak($dbh->errstr);

        my $ok = 1;
        my @upargs;
        foreach my $arg (qw[sync_name source_dir destination_dir sync_time max_age_days sync_server old_sync_name]) {
            my $val = $ua->{postparams}->{$arg} || '';
            if($arg eq 'max_age_days' && $val eq '') {
                $val = 0;
            }
            $webdata{dir}->{$arg} = $val;
            push @upargs, $val;
            if($val eq '') {
                $ok = 0;
            }
        }

        if($ok) {
            if(!$upsth->execute(@upargs)) {
                $ok = 0;
                $dbh->rollback;
            } else {
                $dbh->commit;
            }
        }

        if(!$ok) {
            $webdata{statustext} = "Update failed";
            $webdata{statuscolor} = "errortext";
        } else {
            $webdata{statustext} = "DirSync updated";
            $webdata{statuscolor} = "oktext";

            # Re-read from database
            $webdata{dir}->{old_sync_name} = $webdata{dir}->{sync_name};
            $mode = "select";
        }
    } elsif($mode eq 'create') {
        my $insth = $dbh->prepare_cached("INSERT INTO dirsync
                            (sync_name, source_dir, destination_dir, sync_time, max_age_days, sync_server)
                            VALUES (?,?,?,?,?,?)")
                or croak($dbh->errstr);

        my $ok = 1;
        my @inargs;
        foreach my $arg (qw[sync_name source_dir destination_dir sync_time max_age_days sync_server]) {
            my $val = $ua->{postparams}->{$arg} || '';
            $webdata{dir}->{$arg} = $val;
            push @inargs, $val;
            if($val eq '') {
                $ok = 0;
            }
        }

        if($ok) {
            if(!$insth->execute(@inargs)) {
                $ok = 0;
                $dbh->rollback;
            } else {
                $dbh->commit;
            }
        }

        if(!$ok) {
            $webdata{statustext} = "Creation failed";
            $webdata{statuscolor} = "errortext";
        } else {
            $webdata{statustext} = "DirSync created";
            $webdata{statuscolor} = "oktext";

            # Re-read from database
            $webdata{dir}->{old_sync_name} = $webdata{dir}->{sync_name};
            $mode = "select";
        }
    } elsif($mode eq 'delete') {
        my $ok = 1;
        my $delsth = $dbh->prepare_cached("DELETE FROM dirsync
                                          WHERE sync_name = ?")
                or croak($dbh->errstr);

        if($webdata{dir}->{old_sync_name} eq '') {
            $ok = 0;
        }

        if($ok) {
            if(!$delsth->execute($webdata{dir}->{old_sync_name})) {
                $ok = 0;
                $dbh->rollback;
            } else {
                $dbh->commit;

            }
        }

        if(!$ok) {
            $webdata{statustext} = "Deletion failed";
            $webdata{statuscolor} = "errortext";
        } else {
            $webdata{statustext} = "DirSync deleted";
            $webdata{statuscolor} = "oktext";

            # Open new empty mask
            $webdata{dir}->{old_sync_name} = '';
            $mode = 'new';
        }
    }

    # Must be AFTER above code because $mode gets updated
    if($mode eq 'select') {
        my $selsth = $dbh->prepare_cached("SELECT * FROM dirsync WHERE sync_name = ?")
                or croak($dbh->errstr);
        if(!$selsth->execute($webdata{dir}->{old_sync_name})) {
            $webdata{statustext} = "Internal error";
            $webdata{statuscolor} = "errortext";
            $dbh->rollback;
        } else {
            while((my $line = $selsth->fetchrow_hashref)) {
                $line->{old_sync_name} = $line->{sync_name};
                $webdata{dir} = $line;
            }
            $selsth->finish;
            $dbh->rollback;
            $mode = "edit";
        }
    }

    if($mode eq "new") {
        $mode = "create";
        %{$webdata{dir}} = (
            sync_name   => '',
            old_sync_name   => '',
            source_dir      => '',
            destination_dir => '',
            sync_time       => '',
            max_age_days    => '',
            sync_server     => 'PAGECAMEL',
        );
    }
    $webdata{mode} = $mode;

    my $servsth = $dbh->prepare_cached("SELECT * FROM enum_dirsyncserver
                                       ORDER BY description")
                or croak($dbh->errstr);
    $servsth->execute or croak($dbh->errstr);
    my @servers;
    while((my $server = $servsth->fetchrow_hashref)) {
        push @servers, $server;
    }
    $servsth->finish;
    $dbh->rollback;
    $webdata{servers} = \@servers;

    my $template = $self->{server}->{modules}->{templates}->get("dirsync/dirsync_edit", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);

}



1;
__END__

=head1 NAME

PageCamel::Web::DirSync::DirSync -

=head1 SYNOPSIS

  use PageCamel::Web::DirSync::DirSync;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 get_select



=head2 get_edit



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
