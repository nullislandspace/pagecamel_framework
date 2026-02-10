package PageCamel::Web::Users::GroupEdit;
#---AUTOPRAGMASTART---
use v5.42;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 5.0;
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);

sub register($self) {
    my $ok = 1;
    # Required settings
    foreach my $key (qw[db reporting userlevels]) {
        if(!defined($self->{$key})) {
            print STDERR "GroupEdit.pm: Setting $key is required but not set!\n";
            $ok = 0;
        }
    }

    if(!$ok) {
        croak("Failed to load " . $self->{modname} . " due to config errors!");
    }

    $self->register_webpath($self->{list}->{webpath}, "get_list");
    $self->register_webpath($self->{edit}->{webpath}, "get_edit");
    return;
}

sub reload($self) {
    return;
}

sub get_list($self, $ua) {
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $th = $self->{server}->{modules}->{templates};

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{list}->{pagetitle},
        webpath     =>  $self->{list}->{webpath},
        PostLink    =>  $self->{edit}->{webpath},
        showads => $self->{showads},
    );
    $webdata{userData}->{keyfob_softlogout} = '1'; # Do NOT logout if keyfob is removed, since we may need to "program" new keyfobs here

    my $extrawhere = '';
    if(!contains('has_developer', $webdata{userData}->{rights})) {
        if($extrawhere eq '') {
            $extrawhere = ' WHERE ';
        } else {
            $extrawhere .= ' AND ';
        }
        $extrawhere .= 'is_internal = false';
    }
    
    my $selsth = $dbh->prepare_cached("SELECT * FROM pagecamel.permissiongroups $extrawhere ORDER BY groupname")
            or croak($dbh->errstr);
    $selsth->execute or croak($dbh->errstr);
    my @groups;
    while((my $group = $selsth->fetchrow_hashref)) {
        push @groups, $group;
    }
    $selsth->finish;
    $webdata{Groups} = \@groups;

    my $template = $th->get("users/grouplist", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);

}

sub get_edit($self, $ua) {
    my $ulh = $self->{server}->{modules}->{$self->{userlevels}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $th = $self->{server}->{modules}->{templates};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $mode = $ua->{postparams}->{'mode'} || 'view';

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{edit}->{pagetitle},
        webpath     =>  $self->{edit}->{webpath},
        PostLink    =>  $self->{edit}->{webpath},
        showads => $self->{showads},
    );
    $webdata{userData}->{keyfob_softlogout} = '1'; # Do NOT logout if keyfob is removed, since we may need to "program" new keyfobs here
    
    # Prepare empty user structure
    foreach my $fieldname (qw[groupname oldgroupname description]) {
        $webdata{$fieldname} = "";
    }

    my $entries = $ulh->getPermissionTree();
    foreach my $entry (@{$entries}) {
        $entry->{level} = 'NONE';
        if(!$entry->{standalone}) {
            foreach my $subperm (@{$entry->{subpermissions}}) {
                $subperm->{level} = 'NONE';
            }
        }
    }

    $webdata{Entries} = $entries;

    # First, try for the special "delete" checkbox when called from List
    my $groupname = $ua->{postparams}->{'groupname'} || '';
    if($groupname eq 'NEW') {
        $groupname = '';
        $mode = 'view';
    }

    my %flattened;
    if($mode ne 'view') {
        foreach my $entry (@{$entries}) {
            my $permval = 'NONE';
            if(defined($ua->{postparams}->{$entry->{db}})) {
                $permval = $ua->{postparams}->{$entry->{db}};
            }
            $flattened{$entry->{db}} = $permval;

            if(!$entry->{standalone}) {
                foreach my $subperm (@{$entry->{subpermissions}}) {
                    my $subpermval = 'NONE';
                    if(defined($ua->{postparams}->{$subperm->{db}})) {
                        $subpermval = $ua->{postparams}->{$subperm->{db}};
                    }
                    $flattened{$subperm->{db}} = $subpermval;
                }
            }
        }
    }

    if($mode eq "delete") {
        $groupname = $ua->{postparams}->{'oldgroupname'} || '';
        my $delsth = $dbh->prepare("DELETE FROM pagecamel.permissiongroups
                                   WHERE groupname = ?")
                or croak($dbh->errstr);
        if(!$delsth->execute($groupname)) {
            $reph->debuglog($dbh->errstr);
            $dbh->rollback;
            $mode = 'select';
            $webdata{statustext} = "Can't delete group!";
            $webdata{statuscolor} = "errortext";
        } else {
            $dbh->commit;
            $reph->auditlog($self->{modname}, "Permission group $groupname deleted", $webdata{userData}->{user});
            return $self->get_list($ua);
        }
    } elsif($mode eq "edit") {
        my @auditdata;
        $groupname = $ua->{postparams}->{'oldgroupname'} || '';
        my $newgroupname = $ua->{postparams}->{'groupname'} || '';

        goto reloaddata if($groupname eq '' || $newgroupname eq '');
        if($groupname ne $newgroupname) {
            push @auditdata, "old groupname: $groupname";
            push @auditdata, "new groupname: $newgroupname";
            my $upnamesth = $dbh->prepare_cached("UPDATE pagecamel.permissiongroups
                                                 SET groupname = ?
                                                 WHERE groupname = ?")
                    or croak($dbh->errstr);
            if(!$upnamesth->execute($newgroupname, $groupname)) {
                $reph->debuglog($dbh->errstr);
                $dbh->rollback;
                $webdata{statustext} = "Can't update groupname!";
                $webdata{statuscolor} = "errortext";
                goto reloaddata 
            }
            # For easier handling
            $groupname = $newgroupname;
        }
        my $password = $ua->{postparams}->{'password'} || '';

        foreach my $fieldname (qw[description]) {
            my $upsth = $dbh->prepare_cached("UPDATE pagecamel.permissiongroups
                                             SET $fieldname = ?
                                             WHERE groupname = ?")
                    or croak($dbh->errstr);
            my $fielddata = $ua->{postparams}->{$fieldname} || '';
            if(!$upsth->execute($fielddata, $groupname)) {
                $reph->debuglog($dbh->errstr);
                $dbh->rollback;
                $webdata{statustext} = "Can't update $fieldname!";
                $webdata{statuscolor} = "errortext";
                goto reloaddata 
            }
            push @auditdata, "$fieldname: $fielddata";
        }

        my $upsth = $dbh->prepare_cached("UPDATE pagecamel.permissiongroupentries
                                          SET subpermissions = ?
                                          WHERE groupname = ?
                                          AND permission_name = ?")
                or croak($dbh->errstr);

        foreach my $key (sort keys %flattened) {
            push @auditdata, $key . ': ' . $flattened{$key};
            if(!$upsth->execute($flattened{$key}, $groupname, $key)) {
                $reph->debuglog($dbh->errstr);
                $dbh->rollback;
                $webdata{statustext} = "Can't update permission $key!";
                $webdata{statuscolor} = "errortext";
                goto reloaddata 
            }
        }

        $dbh->commit;
        if(!defined($webdata{statuscolor})) {
            $webdata{statustext} = "User updated!";
            $webdata{statuscolor} = "oktext";
            $reph->auditlog($self->{modname}, "User $groupname updated", $webdata{userData}->{user}, @auditdata);
        }
    } elsif($mode eq "create") {
        my @auditdata;
        $groupname = $ua->{postparams}->{'groupname'} || '';
        my $description = $ua->{postparams}->{'description'} || '';

        push @auditdata, "Description: $description";

        goto reloaddata if($groupname eq '');
        my $innamesth = $dbh->prepare_cached("INSERT INTO pagecamel.permissiongroups
                                             (groupname, description)
                                             VALUES(?, ?)")
                or croak($dbh->errstr);
        if(!$innamesth->execute($groupname, $description)) {
            $dbh->rollback;
            $webdata{statustext} = "Can't insert groupname!";
            $webdata{statuscolor} = "errortext";
            goto reloaddata 
        }

        my $inssth = $dbh->prepare_cached("INSERT INTO pagecamel.permissiongroupentries (groupname, permission_name, subpermissions)
                                           VALUES (?, ?, ?)")
                or croak($dbh->errstr);

        foreach my $key (sort keys %flattened) {
            push @auditdata, $key . ': ' . $flattened{$key};
            if(!$inssth->execute($groupname, $key, $flattened{$key})) {
                $reph->debuglog($dbh->errstr);
                $dbh->rollback;
                $webdata{statustext} = "Can't insert permission $key!";
                $webdata{statuscolor} = "errortext";
                goto reloaddata 
            }
        }


        $dbh->commit;
        if(!defined($webdata{statuscolor})) {
            $webdata{statustext} = "Group created!";
            $webdata{statuscolor} = "oktext";
            $reph->auditlog($self->{modname}, "Group $groupname created", $webdata{userData}->{user}, @auditdata);
        }
        $mode = "edit";
    }

reloaddata:


    # handle "select": Turn it into "edit" after skipping updating data in database
    if($mode eq "select") {
        $groupname = $ua->{postparams}->{'groupname'} || '';
        if($groupname eq '') {
            # Shouldn't happen
            $mode = "create";
        } else {
            $mode = "edit";
        }
    }

    # When in edit mode, reload data from database
    if($mode eq "edit") {
        my $selsth = $dbh->prepare_cached("SELECT * FROM pagecamel.permissiongroups
                                           WHERE groupname = ?")
                or croak($dbh->errstr);
        $selsth->execute($groupname) or croak($dbh->errstr);
        while((my $line = $selsth->fetchrow_hashref)) {
            foreach my $fieldname (qw[groupname description]) {
                $webdata{$fieldname} = $line->{$fieldname};
            }


        }
        $selsth->finish;
        $webdata{oldgroupname} = $webdata{groupname};

        my $eselsth = $dbh->prepare_cached("SELECT * FROM pagecamel.permissiongroupentries
                                            WHERE groupname = ?")
                or croak($dbh->errstr);
        $eselsth->execute($groupname) or croak($dbh->errstr);
        while((my $line = $eselsth->fetchrow_hashref)) {
            foreach my $entry (@{$entries}) {
                if($line->{permission_name} eq $entry->{db}) {
                    $entry->{level} = $line->{subpermissions};
                }
                if(!$entry->{standalone}) {
                    foreach my $subperm (@{$entry->{subpermissions}}) {
                        if($line->{permission_name} eq $subperm->{db}) {
                            $subperm->{level} = $line->{subpermissions};
                        }
                    }
                }
            }
        }
        $eselsth->finish;
    }

    $dbh->commit;;

    if($mode eq "view") {
        $mode = "create";
    }

    $webdata{mode} = $mode;

    my $template = $th->get("users/groupedit", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);

}

1;
__END__

=head1 NAME

PageCamel::Web::Users::Edit -

=head1 SYNOPSIS

  use PageCamel::Web::Users::Edit;



=head1 DESCRIPTION



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

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
