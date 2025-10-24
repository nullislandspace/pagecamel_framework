package PageCamel::Helpers::Userlevels;
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

sub getPermissionForUser($self, $username) {
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my @restricted;
    if(defined($self->{userlevels}->{userlevel})) {
        foreach my $level (@{$self->{userlevels}->{userlevel}}) {
            next unless(defined($level->{restrict}));

            if(!contains($username, $level->{restrict})) {
                push @restricted, $level->{db};
            }
        }
    }

    my @permissions;

    my $selsth = $dbh->prepare_cached("SELECT pe.* FROM pagecamel.permissiongroupentries pe
                                        INNER JOIN pagecamel.users_permissiongroups up ON pe.groupname = up.groupname
                                        WHERE up.username = ?
                                        ORDER BY pe.permission_name")
            or croak($dbh->errstr);
    
    if(!$selsth->execute($username)) {
        $reph->debuglog($dbh->errstr);
        croak("Failed to read user permissions");
    }

    my @subpermissions;
    my @selectives;
    while((my $line = $selsth->fetchrow_hashref)) {
        if(contains($line->{permission_name}, \@restricted)) {
            # Ignore permissions that user has been restricted from, regardless of values in the database
            next;
        }

        if($line->{permission_name} =~ /\//) {
            push @subpermissions, $line;
            next;
        }

        if($line->{subpermissions} eq 'NONE') {
            next;
        }

        if($line->{subpermissions} eq 'SELECTIVE') {
            push @selectives, $line->{permission_name};
            next;
        }

        if(!contains($line->{permission_name}, \@permissions)) {
            push @permissions, $line->{permission_name};
        }
    }

    $selsth->finish;

    foreach my $subpermission (@subpermissions) {
        my ($rootname, $pname) = split/\//, $subpermission->{permission_name}, 2;

        # Permissions where the master is "ALL" ignore their own settings
        if(contains($rootname, \@permissions)) {
            push @permissions, $subpermission->{permission_name};
        }

        # Now handle permissions where the master is "SELECTIVE", these need to check first if they are themselves enabled
        if($subpermission->{subpermissions} ne 'ALL') {
            next;
        }

        if(contains($rootname, \@selectives) && !contains($subpermission->{permission_name}, \@permissions)) {
            push @permissions, $subpermission->{permission_name};
        }
    }

    foreach my $selective (@selectives) {
        if(!contains($selective, \@permissions)) {
            push @permissions, $selective;
        }
    }

    #print STDERR Dumper(\@permissions);

    return \@permissions;

}

sub getUsersForPermission($self, $permission, $negate = 0, $allowdevelopers = 0) {
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    $negate = !!$negate;

    my @usernames;

    my $extrawhere = '';
    if(!$allowdevelopers) {
        $extrawhere = 'WHERE is_internal = false';
    }

    my @users;
    my $selsth = $dbh->prepare_cached("SELECT username FROM users $extrawhere")
            or croak($dbh->errstr);
    if(!$selsth->execute) {
        $reph->debuglog($dbh->errstr);
        croak("Failed to read users");
    }

    while((my $line = $selsth->fetchrow_hashref)) {
        push @users, $line->{username};
    }
    $selsth->finish;

    foreach my $user (@users) {
        my $permissions = $self->getPermissionForUser($user);
        if(!defined($permissions)) {
            return;
        }
        my $has = !!contains($permission, $permissions);
        if($has != $negate) {
            push @usernames, $user;
        }
    }

    return \@usernames;
}

1;
