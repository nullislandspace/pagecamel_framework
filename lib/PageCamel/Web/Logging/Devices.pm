package PageCamel::Web::Logging::Devices;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.0;
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

    $self->register_webpath($self->{list}->{webpath}, "get_list");
    $self->register_webpath($self->{edit}->{webpath}, "get_edit");

    return;
}

sub get_list {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{list}->{pagetitle},
        webpath     =>  $self->{list}->{webpath},
        PostLink    =>  $self->{edit}->{webpath},
        mode        =>  "select",
        showads => $self->{showads},
    );

    my $sth = $dbh->prepare_cached("SELECT * FROM logging_devices
                                   ORDER BY hostname")
            or croak($dbh->errstr);

    my @devices;
    $sth->execute or croak($dbh->errstr);
    while((my $device = $sth->fetchrow_hashref)) {
        push @devices, $device;
    }
    $webdata{devices} = \@devices;

    my $template = $self->{server}->{modules}->{templates}->get("logging/devices_list", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub get_edit {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{edit}->{pagetitle},
        webpath    =>  $self->{edit}->{webpath},
        showads => $self->{showads},
    );

    my $mode = $ua->{postparams}->{"mode"} || "new";
    my %vals;
    foreach my $key (qw[old_hostname hostname device_type description ip_addr is_active device_username device_password scanspeed computerdb_hostname]) {
        $vals{$key} = $ua->{postparams}->{$key} || '';
    }

    if($vals{is_active} eq 'on' || $vals{is_active} eq '1') {
        $vals{is_active} = 'true';
    } else {
        $vals{is_active} = 'false';
    }

    my $needNULLupdate = 0;
    if($mode eq "delete") {
        my $delsth = $dbh->prepare_cached("DELETE FROM logging_devices
                                          WHERE hostname = ?")
                or croak($dbh->errstr);
        if($delsth->execute($vals{hostname})) {
            $mode = "new";
            $webdata{statuscolor} = "oktext";
            $webdata{statustext} = "Device deleted";
            $dbh->commit;
        } else {
            $webdata{statuscolor} = "errortext";
            $webdata{statustext} = "Delete failed";
            $dbh->rollback;
        }
    } elsif($mode eq "create") {
        my $insth = $dbh->prepare_cached("INSERT INTO logging_devices
                                          (hostname, device_type, description, is_active,
                                          device_username, device_password, scanspeed)
                                          VALUES (?,?,?,?,?,?,?)")
                or croak($dbh->errstr);
        if($insth->execute($vals{hostname}, $vals{device_type}, $vals{description}, $vals{is_active},
                           $vals{device_username}, $vals{device_password}, $vals{scanspeed})) {
            $mode = "edit";
            $webdata{statuscolor} = "oktext";
            $webdata{statustext} = "Device created";
            $dbh->commit;
        } else {
            $webdata{statuscolor} = "errortext";
            $webdata{statustext} = "Creation failed";
            $dbh->rollback;
        }
    } elsif($mode eq "edit") {
        my $upsth = $dbh->prepare_cached("UPDATE logging_devices
                                          SET hostname = ?,
                                          device_type = ?,
                                          description = ?,
                                          is_active = ?,
                                          device_username = ?,
                                          device_password = ?,
                                          scanspeed = ?
                                          WHERE hostname = ?")
                or croak($dbh->errstr);
        if($upsth->execute($vals{hostname}, $vals{device_type}, $vals{description}, $vals{is_active},
                           $vals{device_username}, $vals{device_password}, $vals{scanspeed}, $vals{old_hostname})) {
            $webdata{statuscolor} = "oktext";
            $webdata{statustext} = "Device updated";
            $dbh->commit;
        } else {
            $webdata{statuscolor} = "errortext";
            $webdata{statustext} = "Update failed";
            $dbh->rollback;
        }
        $vals{hostname} = $vals{old_hostname};
    }

    if($mode eq "edit") {
        # NULL columns
        foreach my $key (qw[ip_addr computerdb_hostname]) {
            if($vals{$key} eq '') {
                my $sth = $dbh->prepare_cached("UPDATE logging_devices
                                               SET $key = NULL
                                               WHERE hostname = ?")
                        or croak($dbh->errstr);
                if(!$sth->execute($vals{hostname})) {
                    $webdata{statuscolor} = "errortext";
                    $webdata{statustext} .= " Can't set $key to NULL!";
                    $dbh->rollback;
                } else {
                    $dbh->commit;
                }
            } else {
                my $sth = $dbh->prepare_cached("UPDATE logging_devices
                                               SET $key = ?
                                               WHERE hostname = ?")
                        or croak($dbh->errstr);
                if(!$sth->execute($vals{$key}, $vals{hostname})) {
                    $webdata{statuscolor} = "errortext";
                    $webdata{statustext} .= " Can't set $key!";
                    $dbh->rollback;
                } else {
                    $dbh->commit;
                }
            }
        }
    }

    if($mode eq "new") {
        foreach my $key (qw[old_hostname hostname device_type description ip_addr is_active username password scanspeed computerdb_hostname]) {
            $vals{$key} ='';
        }
        $webdata{device} = \%vals;
        $mode = "create";
    } else {
        my $sth = $dbh->prepare_cached("SELECT * FROM logging_devices
                                       WHERE hostname = ?")
                or croak($dbh->errstr);
        $sth->execute($vals{hostname})
                or croak($dbh->errstr);

        while((my $device = $sth->fetchrow_hashref)) {
            if(!defined($device->{ip_addr})) {
                $device->{ip_addr} = '';
            }
            if(!defined($device->{computerdb_hostname})) {
                $device->{computerdb_hostname} = '';
            }
            $webdata{device} = $device;;
        }
        $sth->finish;
        $mode = "edit";
    }

    my @devtypes;
    my $dsth = $dbh->prepare_cached("SELECT * FROM enum_logging ORDER BY enumvalue")
            or croak($dbh->errstr);
    $dsth->execute or croak($dbh->errstr);
    while((my $devtype = $dsth->fetchrow_hashref)) {
        push @devtypes, $devtype;
    }
    $dsth->finish;
    $webdata{devtypes} = \@devtypes;

    my @computers;
    my $csth = $dbh->prepare_cached("SELECT * FROM computers ORDER BY computer_name")
            or croak($dbh->errstr);
    $csth->execute or croak($dbh->errstr);
    while((my $computer = $csth->fetchrow_hashref)) {
        push @computers, $computer;
    }
    $csth->finish;
    $webdata{Computers} = \@computers;

    $dbh->rollback;

    $webdata{mode} = $mode;

    my $template = $self->{server}->{modules}->{templates}->get("logging/devices_edit", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}
1;
__END__

=head1 NAME

PageCamel::Web::Logging::Devices -

=head1 SYNOPSIS

  use PageCamel::Web::Logging::Devices;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 get_list



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

Copyright (C) 2008-2019 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
