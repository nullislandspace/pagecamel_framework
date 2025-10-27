package PageCamel::Web::Users::UserEdit;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::Strings qw(elemNameQuote);
use PageCamel::Helpers::Passwords;
use PageCamel::Helpers::Strings qw(stripString);
use PageCamel::Helpers::URI qw(encode_uri_path);
use PageCamel::Helpers::APPQRCode;

sub register($self) {
    my $ok = 1;
    # Required settings
    foreach my $key (qw[systemsettings db reporting]) {
        if(!defined($self->{$key})) {
            print STDERR "UserEdit.pm: Setting $key is required but not set!\n";
            $ok = 0;
        }
    }

    if(!defined($self->{forcelowercase})) {
        $self->{forcelowercase} = 1;
    }

    if(!defined($self->{switchtouser})) {
        $self->{switchtouser} = '';
    }

    if(!defined($self->{textpermissions}->{item})) {
        $self->{textpermissions}->{item} = [];
    } else {
        foreach my $textpermission (@{$self->{textpermissions}->{item}}) {
            if(!defined($textpermission->{column})) {
                print STDERR "Textpermission has no column name\n";
                $ok = 0;
                next;
            }
            foreach my $key (qw[displaytext table enumcolumn]) {
                if(!defined($textpermission->{$key})) {
                    print STDERR "Textpermission for column ", $textpermission->{column}, " has no setting for ", $key, "\n";
                    $ok = 0;
                }
            }
        }
    }

    if(!$ok) {
        croak("Failed to load " . $self->{modname} . " due to config errors!");
    }

    $self->{qrcode} = PageCamel::Helpers::APPQRCode->new(scale => 5);

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
    if($webdata{userData}->{user} ne 'admin') {
        $extrawhere = " WHERE username != 'admin'";
    }

    if(!contains('has_developer', $webdata{userData}->{rights})) {
        if($extrawhere eq '') {
            $extrawhere = ' WHERE ';
        } else {
            $extrawhere .= ' AND ';
        }
        $extrawhere .= "(is_internal = false OR username = 'applogin') ";
    }

    my $selsth = $dbh->prepare_cached("SELECT * FROM users $extrawhere ORDER BY username")
            or croak($dbh->errstr);
    $selsth->execute or croak($dbh->errstr);
    my @users;
    while((my $user = $selsth->fetchrow_hashref)) {
        if($self->{switchtouser} ne '') {
            $user->{switchtouser} = $self->{switchtouser} . '/' . encode_uri_path($user->{username});
        } else {
            $user->{switchtouser} = '';
        }
        push @users, $user;
    }
    $selsth->finish;
    $webdata{Users} = \@users;

    my $template = $th->get("users/userlist", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);

}

sub get_edit($self, $ua) {
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $th = $self->{server}->{modules}->{templates};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    my $pwh = PageCamel::Helpers::Passwords->new({dbh => $dbh, reph => $reph, sysh => $sysh});

    my $mode = $ua->{postparams}->{'mode'} || 'view';

    if($mode eq 'close') {
        return $self->get_list($ua);
    }

    # Handle calls from external module (select username to edit by url)
    my $forceUsername;
    my $filename = $ua->{url};
    my $remove = $self->{edit}->{webpath};
    $filename =~ s/^$remove//;
    $filename =~ s/^\///;
    $filename =~ s/\/$//;
    $filename = stripString($filename);
    if($filename ne '') {
        $forceUsername = $filename;
        $mode = 'select';
    }


    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{edit}->{pagetitle},
        webpath     =>  $self->{edit}->{webpath},
        PostLink    =>  $self->{edit}->{webpath},
        showads => $self->{showads},
    );
    $webdata{userData}->{keyfob_softlogout} = '1'; # Do NOT logout if keyfob is removed, since we may need to "program" new keyfobs here

    my @textpermissions;
    foreach my $item (@{$self->{textpermissions}->{item}}) {
        push @textpermissions, $item->{column};

        my $aliasname = '';
        if($item->{enumcolumn} ne 'permission_name') {
            $aliasname = ' AS permission_name ';
        }

        my $enumsth = $dbh->prepare("SELECT " . $item->{enumcolumn} . $aliasname . " FROM " . $item->{table} . " ORDER BY " . $item->{enumcolumn})
                or croak($dbh->errstr);
        if(!$enumsth->execute) {
            $reph->debuglog($dbh->errstr);
            $dbh->rollback;
            return (status => 500);
        }
        my @enumvals;
        my %blankline = (
            permission_name => ''
        );
        push @enumvals, \%blankline;
        while((my $line = $enumsth->fetchrow_hashref)) {
            push @enumvals, $line;
        }
        $enumsth->finish;
        my %txtpermission = (
            column => $item->{column},
            displaytext => $item->{displaytext}, 
            data => \@enumvals,
        );
        push @{$webdata{textpermissions}}, \%txtpermission;
    }

    
    # Prepare empty user structure
    my @fieldnames = qw[username oldusername email_addr account_locked account_lock_reason first_name last_name name_initials applogin_usercode organisation_name hardware_fob];
    push @fieldnames, @textpermissions;
    foreach my $fieldname (@fieldnames) {
        $webdata{$fieldname} = "";
    }
    
    
    if($webdata{userData}->{user} ne 'admin') {
        my $olduser = $ua->{postparams}->{'oldusername'} || '';
        my $newuser = $ua->{postparams}->{'username'} || '';
        if($olduser eq 'admin' || $newuser eq 'admin') {
            return (status => 403,
                    type => 'text/plain',
                    data => '403 Forbidden');
        }
    }

    my $gselsth = $dbh->prepare_cached("SELECT * FROM pagecamel.permissiongroups
                                        ORDER BY groupname")
            or croak($dbh->errstr);

    if(!$gselsth->execute) {
        $reph->debuglog($dbh->errstr);
        $dbh->rollback;
        return (status => 500);
    }

    my @groups;
    while((my $line = $gselsth->fetchrow_hashref)) {
        $line->{has_access} = 0;
        push @groups, $line;
    }
    $gselsth->finish;

    $webdata{Groups} = \@groups;

    # First, try for the special "delete" checkbox when called from List
    my $username = $ua->{postparams}->{'username'} || '';
    if($username eq 'NEW') {
        $username = '';
        $mode = 'view';
    }

    my $origcaseusername = $username;
    if($self->{forcelowercase}) {
        $username = lc $username;
    }

    if($mode eq "delete") {
        $username = $ua->{postparams}->{'oldusername'} || '';
        my $delsth = $dbh->prepare("DELETE FROM users
                                   WHERE username = ?")
                or croak($dbh->errstr);
        if(!$delsth->execute($origcaseusername)) {
            $dbh->rollback;
            $mode = 'select';
            $webdata{statustext} = "Can't delete user!";
            $webdata{statuscolor} = "errortext";
        } else {
            $dbh->commit;
            $reph->auditlog($self->{modname}, "User $username deleted", $webdata{userData}->{user}); # $webdata{userData}->{user};
            return $self->get_list($ua);
        }
    } elsif($mode eq "edit") {
        my @auditdata;
        $username = $ua->{postparams}->{'oldusername'} || '';
        my $newusername = $ua->{postparams}->{'username'} || '';
        if($self->{forcelowercase}) {
            $newusername = lc $newusername;
        }

        goto reloaddata if($username eq '' || $newusername eq '');
        if($username ne $newusername) {
            push @auditdata, "old username: $username";
            push @auditdata, "new username: $newusername";
            my $upnamesth = $dbh->prepare_cached("UPDATE users
                                                 SET username = ?
                                                 WHERE username = ?")
                    or croak($dbh->errstr);
            if(!$upnamesth->execute($newusername, $username)) {
                $dbh->rollback;
                $webdata{statustext} = "Can't update username!";
                $webdata{statuscolor} = "errortext";
                goto reloaddata 
            }
            # For easier handling
            $username = $newusername;
        }
        my $password = $ua->{postparams}->{'password'} || '';
        if($password ne '') {
            if(!$pwh->update_password($username, $password)) {
                $dbh->rollback;
                $webdata{statustext} = "Can't update password!";
                $webdata{statuscolor} = "errortext";
                goto reloaddata 
            }
            push @auditdata, "New password set";
        }

        my @upfieldnames = qw[email_addr account_locked account_lock_reason first_name last_name name_initials applogin_usercode organisation_name force_password_change hardware_fob];
        push @upfieldnames, @textpermissions;
        foreach my $fieldname (@upfieldnames) {
            my $dbfield = $fieldname;
            if($dbfield eq 'organisation_name') {
                $dbfield = 'organisation';
            }
            my $upsth = $dbh->prepare_cached("UPDATE users
                                             SET $dbfield = ?
                                             WHERE username = ?")
                    or croak($dbh->errstr);
            my $fielddata = $ua->{postparams}->{$fieldname} || '';
            if($fieldname eq 'account_locked' || $fieldname eq 'force_password_change') {
                if($fielddata =~ /(on|1)/i) {
                    $fielddata = 'true';
                } else {
                    $fielddata = 'false';
                }
            }

            if($fieldname =~ /^textpermission_/ && $fielddata eq '') {
                $fielddata = undef;
            }

            if($fieldname eq 'email_addr') {
                $fielddata = lc $fielddata;
            }
            if(!$upsth->execute($fielddata, $username)) {
                $dbh->rollback;
                $webdata{statustext} = "Can't update $fieldname!";
                $webdata{statuscolor} = "errortext";
                goto reloaddata 
            }
            if(!defined($fielddata)) {
                $fielddata = '';
            }
            push @auditdata, "$fieldname: $fielddata";
        }

        my $rdelsth = $dbh->prepare_cached("DELETE FROM pagecamel.users_permissiongroups
                                           WHERE username = ?")
                or croak($dbh->errstr);
        $rdelsth->execute($username) or croak($dbh->errstr);

        foreach my $group (@groups) {
            my $insth = $dbh->prepare_cached("INSERT INTO pagecamel.users_permissiongroups (username, groupname)
                                             VALUES (?,?)")
                    or croak($dbh->errstr);
            my $fielddata = $ua->{postparams}->{"right_" . $group->{groupname}} || '0';
            if($fielddata eq "1" || $fielddata eq "on") {
                if(!$insth->execute($username, $group->{groupname})) {
                    $dbh->rollback;
                    $webdata{statustext} = "Can't update " . $group->{groupname} . "!";
                    $webdata{statuscolor} = "errortext";
                    goto reloaddata 
                }
            }
            push @auditdata, "Group " . $group->{groupname};
        }

        $dbh->commit;
        if(!defined($webdata{statuscolor})) {
            $webdata{statustext} = "User updated!";
            $webdata{statuscolor} = "oktext";
            $reph->auditlog($self->{modname}, "User $username updated", $webdata{userData}->{user}, @auditdata);
        }
    } elsif($mode eq "create") {
        my @auditdata;
        $username = $ua->{postparams}->{'username'} || '';
        if($self->{forcelowercase}) {
            $username = lc $username;
        }
        my $organisation = $ua->{postparams}->{'organisation_name'} || '';

        push @auditdata, "Organisation: $organisation";

        goto reloaddata if($username eq '');
        my $innamesth = $dbh->prepare_cached("INSERT INTO users
                                             (username, organisation)
                                             VALUES(?, ?)")
                or croak($dbh->errstr);
        if(!$innamesth->execute($username, $organisation)) {
            $dbh->rollback;
            $webdata{statustext} = "Can't insert username!";
            $webdata{statuscolor} = "errortext";
            goto reloaddata 
        }

        my $password = $ua->{postparams}->{'password'} || '';
        if($password ne '') {
            push @auditdata, "New password set";
            if(!$pwh->update_password($username, $password)) {
                $dbh->rollback;
                $webdata{statustext} = "Can't update password!";
                $webdata{statuscolor} = "errortext";
                goto reloaddata 
            }
        }

        my @createfieldnames = qw[email_addr account_locked account_lock_reason first_name last_name name_initials applogin_usercode force_password_change hardware_fob];
        push @createfieldnames, @textpermissions;
        foreach my $fieldname (@createfieldnames) {
            my $upsth = $dbh->prepare_cached("UPDATE users
                                             SET $fieldname = ?
                                             WHERE username = ?")
                    or croak($dbh->errstr);
            my $fielddata = $ua->{postparams}->{$fieldname} || '';
            if($fieldname eq 'account_locked' || $fieldname eq 'force_password_change') {
                if($fielddata =~ /(on|1)/i) {
                    $fielddata = 'true';
                } else {
                    $fielddata = 'false';
                }
            }

            if($fieldname =~ /^textpermission_/ && $fielddata eq '') {
                $fielddata = undef;
            }

            if($fieldname eq 'email_addr') {
                $fielddata = lc $fielddata;
            }
            if(!$upsth->execute($fielddata, $username)) {
                $dbh->rollback;
                $webdata{statustext} = "Can't update $fieldname!";
                $webdata{statuscolor} = "errortext";
                goto reloaddata 
            }
            if(!defined($fielddata)) {
                $fielddata = '';
            }
            push @auditdata, "$fieldname: $fielddata";
        }

        foreach my $group (@groups) {
            my $insth = $dbh->prepare_cached("INSERT INTO pagecamel.users_permissiongroups (username, groupname)
                                             VALUES (?,?)")
                    or croak($dbh->errstr);
            my $fielddata = $ua->{postparams}->{"right_" . $group->{groupname}} || '0';
            if($fielddata eq "1" || $fielddata eq "on") {
                $fielddata = "true";
                if(!$insth->execute($username, $group->{groupname})) {
                    $dbh->rollback;
                    $webdata{statustext} = "Can't update " . $group->{groupname} . "!";
                    $webdata{statuscolor} = "errortext";
                    goto reloaddata 
                }
            }
            push @auditdata, "Permission " . $group->{groupname};
        }

        $dbh->commit;
        if(!defined($webdata{statuscolor})) {
            $webdata{statustext} = "User updated!";
            $webdata{statuscolor} = "oktext";
            $reph->auditlog($self->{modname}, "User $username created", $webdata{userData}->{user}, @auditdata);
        }
        $mode = "edit";
    }

reloaddata:


    # handle "select": Turn it into "edit" after skipping updating data in database
    if($mode eq "select") {
        $username = $ua->{postparams}->{'username'} || '';
        if($self->{forcelowercase}) {
            $username = lc $username;
        }
        if(defined($forceUsername)) {
            $username = $forceUsername;
        }
        if($username eq '') {
            # Shouldn't happen
            $mode = "create";
        } else {
            $mode = "edit";
        }
    }

    # When in edit mode, reload data from database
    if($mode eq "edit") {
        my $selsth = $dbh->prepare_cached("SELECT * FROM users
                                          WHERE username = ?")
                or croak($dbh->errstr);
        $selsth->execute($username) or croak($dbh->errstr);
        my @selectfieldnames = qw[username email_addr account_locked account_lock_reason first_name last_name name_initials applogin_usercode organisation_name force_password_change hardware_fob appkey];
        push @selectfieldnames, @textpermissions;
        while((my $user = $selsth->fetchrow_hashref)) {
            foreach my $fieldname (@selectfieldnames) {
                my $dbfield = $fieldname;
                if($dbfield eq 'organisation_name') {
                    $dbfield = 'organisation';
                }
                $webdata{$fieldname} = $user->{$dbfield};
            }

            my $rightssth = $dbh->prepare_cached("SELECT * FROM pagecamel.users_permissiongroups
                                                 WHERE username = ?")
                    or croak($dbh->errstr);
            $rightssth->execute($username) or corak($dbh->errstr);
            while((my $rline = $rightssth->fetchrow_hashref)) {
                foreach my $group (@groups) {
                    if($group->{groupname} eq $rline->{groupname}) {
                        $group->{has_access} = 1;
                        last;
                    }
                }
            }
            $rightssth->finish;

        }
        $selsth->finish;
        $webdata{oldusername} = $webdata{username};

        my $projectname = 'Demo';
        my ($ok, $sysval) = $sysh->get('defaultwebdata', 'ProjectName');
        if($ok && $sysval->{settingvalue} ne '') {
            $projectname = $sysval->{settingvalue};
        } else {
            #$reph->debuglog("### ", $ok, " / ", Dumper($sysval));
        }

        $webdata{appqrcode} = $self->{qrcode}->generateEmbeddedImage(SERVER => $ua->{headers}->{Host}, USERKEY => $webdata{username} . '+' . $webdata{appkey}, PROJECTNAME => $projectname);
        $webdata{appqrcodeserver} = $ua->{headers}->{Host};
        $webdata{appqrcodekey} = $webdata{username} . '+' . $webdata{appkey};
    }
    $webdata{Groups} = \@groups;

    my $orgasth = $dbh->prepare_cached("SELECT * FROM pagecamel.users_organisation
                                       ORDER BY organisation_name")
            or croak($dbh->errstr);
    my @orgas;
    $orgasth->execute or croak($dbh->errstr);
    while((my $orga = $orgasth->fetchrow_hashref)) {
        push @orgas,  $orga;
    }
    $orgasth->finish;
    $webdata{organisations} = \@orgas;

    $dbh->rollback;

    if($mode eq "view") {
        $mode = "create";
        $webdata{force_password_change} = 0; # Default to NOT expiring passwords
        if(defined($self->{default_organisation})) {
            $webdata{organisation_name} = $self->{default_organisation};
        }
    }
    $webdata{mode} = $mode;
    $webdata{forcelowercase} = $self->{forcelowercase};

    my $template = $th->get("users/useredit", 1, %webdata);
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
