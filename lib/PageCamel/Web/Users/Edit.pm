package PageCamel::Web::Users::Edit;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::Strings qw(elemNameQuote);
use PageCamel::Helpers::Passwords;
use PageCamel::Helpers::Strings qw(stripString);
use PageCamel::Helpers::URI qw(encode_uri_path);

sub register($self) {
    
    my $ok = 1;
    # Required settings
    foreach my $key (qw[systemsettings]) {
        if(!defined($self->{$key})) {
            print STDERR "Edit.pm: Setting $key is required but not set!\n";
            $ok = 0;
        }
    }

    if(!$ok) {
        croak("Failed to load " . $self->{modname} . " due to config errors!");
    }

    if(!defined($self->{forcelowercase})) {
        $self->{forcelowercase} = 1;
    }

    if(!defined($self->{switchtouser})) {
        $self->{switchtouser} = '';
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
    my $th = $self->{server}->{modules}->{templates};

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{list}->{pagetitle},
        webpath     =>  $self->{list}->{webpath},
        PostLink    =>  $self->{edit}->{webpath},
        showads => $self->{showads},
    );
    
    my $extrawhere = '';
    if($webdata{userData}->{user} ne 'admin') {
        $extrawhere = " WHERE username != 'admin'";
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
    my $ulh = $self->{server}->{modules}->{userlevels};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    my $pwh = PageCamel::Helpers::Passwords->new({dbh => $dbh, reph => $reph, sysh => $sysh});

    my $mode = $ua->{postparams}->{'mode'} || 'view';

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
        CompanyLabel => "Company",
        showads => $self->{showads},
    );
    
    if(defined($self->{usegroupsinsteadcompanies}) && $self->{usegroupsinsteadcompanies}) {
        $webdata{CompanyLabel} = "Group";
    }
    
    # Prepare empty user structure
    foreach my $fieldname (qw[username oldusername email_addr account_locked account_lock_reason first_name last_name company_name hardware_fob]) {
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

    my @rights;
    my @rightcols;
    foreach my $ur (@{$ulh->{userlevels}->{userlevel}}) {
        if(defined($ur->{restrict})) {
            next;
        }
        my %right; ## no critic (NamingConventions::ProhibitAmbiguousNames)
        $right{display} = $ur->{display};
        $right{db} = $ur->{db};
        $right{val} = 0;
        push @rightcols, $ur->{db};
        push @rights, \%right;
    }
    $webdata{UserLevels} = \@rights;

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

        foreach my $fieldname (qw[email_addr account_locked account_lock_reason first_name last_name company_name password_can_expire hardware_fob]) {
            my $upsth = $dbh->prepare_cached("UPDATE users
                                             SET $fieldname = ?
                                             WHERE username = ?")
                    or croak($dbh->errstr);
            my $fielddata = $ua->{postparams}->{$fieldname} || '';
            if($fieldname eq 'account_locked' || $fieldname eq 'password_can_expire') {
                if($fielddata =~ /(on|1)/i) {
                    $fielddata = 'true';
                } else {
                    $fielddata = 'false';
                }
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
            push @auditdata, "$fieldname: $fielddata";
        }

        {
            my $fielddata = $ua->{postparams}->{force_password_change} || '';
            if($fielddata =~ /(on|1)/i) {
                my $upsth = $dbh->prepare_cached("UPDATE users
                                             SET next_password_change = now(),
                                             password_can_expire = true
                                             WHERE username = ?")
                        or croak($dbh->errstr);
                if(!$upsth->execute($username)) {
                    $dbh->rollback;
                    $webdata{statustext} = "Can't set user to forced password change!";
                    $webdata{statuscolor} = "errortext";
                    goto reloaddata 
                }
            }
        }

        my $rdelsth = $dbh->prepare_cached("DELETE FROM users_permissions
                                           WHERE username = ?")
                or croak($dbh->errstr);
        $rdelsth->execute($username) or croak($dbh->errstr);

        foreach my $fieldname (@{$ulh->{userlevels}->{userlevel}}) {
            if(defined($fieldname->{restrict})) {
                next;
            }
            my $insth = $dbh->prepare_cached("INSERT INTO users_permissions (username, permission_name, has_access)
                                             VALUES (?,?,?)")
                    or croak($dbh->errstr);
            my $fielddata = $ua->{postparams}->{"right_" . $fieldname->{db}} || '0';
            if($fielddata eq "1" || $fielddata eq "on") {
                $fielddata = "true";
            } else {
                $fielddata = "false";
            }
            if(!$insth->execute($username, $fieldname->{db}, $fielddata)) {
                $dbh->rollback;
                $webdata{statustext} = "Can't update $fieldname!";
                $webdata{statuscolor} = "errortext";
                goto reloaddata 
            }
            push @auditdata, "Permission " . $fieldname->{db} . ": $fielddata";
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
        my $company = $ua->{postparams}->{'company_name'} || '';

        push @auditdata, "Company: $company";

        goto reloaddata if($username eq '');
        my $upnamesth = $dbh->prepare_cached("INSERT INTO users
                                             (username, company_name)
                                             VALUES(?, ?)")
                or croak($dbh->errstr);
        if(!$upnamesth->execute($username, $company)) {
            $dbh->rollback;
            $webdata{statustext} = "Can't update username!";
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

        foreach my $fieldname (qw[email_addr account_locked account_lock_reason first_name last_name password_can_expire hardware_fob]) {
            my $upsth = $dbh->prepare_cached("UPDATE users
                                             SET $fieldname = ?
                                             WHERE username = ?")
                    or croak($dbh->errstr);
            my $fielddata = $ua->{postparams}->{$fieldname} || '';
            if($fieldname eq 'account_locked' || $fieldname eq 'password_can_expire') {
                if($fielddata =~ /(on|1)/i) {
                    $fielddata = 'true';
                } else {
                    $fielddata = 'false';
                }
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
            push @auditdata, "$fieldname: $fielddata";
        }

        foreach my $fieldname (@{$ulh->{userlevels}->{userlevel}}) {
            if(defined($fieldname->{restrict})) {
                next;
            }
            my $insth = $dbh->prepare_cached("INSERT INTO users_permissions (username, permission_name, has_access)
                                             VALUES (?,?,?)")
                    or croak($dbh->errstr);
            my $fielddata = $ua->{postparams}->{"right_" . $fieldname->{db}} || '0';
            if($fielddata eq "1" || $fielddata eq "on") {
                $fielddata = "true";
            } else {
                $fielddata = "false";
            }
            if(!$insth->execute($username, $fieldname->{db}, $fielddata)) {
                $dbh->rollback;
                $webdata{statustext} = "Can't update $fieldname!";
                $webdata{statuscolor} = "errortext";
                goto reloaddata 
            }
            push @auditdata, "Permission " . $fieldname->{db} . ": $fielddata";
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
        my $selsth = $dbh->prepare_cached("SELECT *, (next_password_change <= now() AND password_can_expire = true) AS force_password_change FROM users
                                          WHERE username = ?")
                or croak($dbh->errstr);
        $selsth->execute($username) or croak($dbh->errstr);
        while((my $user = $selsth->fetchrow_hashref)) {
            foreach my $fieldname (qw[username email_addr account_locked account_lock_reason first_name last_name company_name password_can_expire force_password_change hardware_fob]) {
                $webdata{$fieldname} = $user->{$fieldname};
            }

            my $rightssth = $dbh->prepare_cached("SELECT * FROM users_permissions
                                                 WHERE username = ?")
                    or croak($dbh->errstr);
            my %dbrights;
            $rightssth->execute($username) or corak($dbh->errstr);
            while((my $rline = $rightssth->fetchrow_hashref)) {
                $dbrights{$rline->{permission_name}} = $rline->{has_access};
            }
            $rightssth->finish;

            @rights = ();
            foreach my $ur (@{$ulh->{userlevels}->{userlevel}}) {
                if(defined($ur->{restrict})) {
                    next;
                }
                my %right;  ## no critic (NamingConventions::ProhibitAmbiguousNames)
                $right{display} = $ur->{display};
                $right{db} = $ur->{db};
                if(defined($dbrights{$ur->{db}})) {
                    $right{val} = $dbrights{$ur->{db}};
                } else {
                    $right{val} = 0;
                }
                push @rightcols, $ur->{db};
                push @rights, \%right;
            }

            last;
        }
        $selsth->finish;
        $webdata{oldusername} = $webdata{username};
    }

    my $compsth = $dbh->prepare_cached("SELECT * FROM company
                                       ORDER BY company_name")
            or croak($dbh->errstr);
    my @companies;
    $compsth->execute or croak($dbh->errstr);
    while((my $company = $compsth->fetchrow_hashref)) {
        push @companies,  $company;
    }
    $compsth->finish;
    $webdata{companies} = \@companies;

    $dbh->rollback;

    if($mode eq "view") {
        $mode = "create";
        $webdata{password_can_expire} = 1; # Default to expiring passwords
        $webdata{force_password_change} = 1; # Default to expiring passwords
        if(defined($self->{default_company})) {
            $webdata{company_name} = $self->{default_company};
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
