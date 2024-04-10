package PageCamel::Web::Users::Userlevels;
#---AUTOPRAGMASTART---
use v5.38;
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

use base qw(PageCamel::Web::BaseModule PageCamel::Helpers::Userlevels);

use PageCamel::Helpers::Padding qw[doSpacePad];
use PageCamel::Helpers::Strings qw[stripString];

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my $ok = 1;
    foreach my $required (qw[db memcache reporting views]) {
        if(!defined($self->{$required})) {
            print STDERR $self->{modname} . " requires config option " . $required . "\n";
            $ok = 0;
        }
    }

    foreach my $level (@{$self->{userlevels}->{userlevel}}) {
        if(defined($level->{path})) {
            push @{$level->{webpaths}}, $level->{path};
        }
    }

    if(!$ok) {
        croak("Configuration errors in ", $self->{modname});
    }

    return $self;
}

sub register_userlevel($self, $userlevel, $display) {
    foreach my $level (@{$self->{userlevels}->{userlevel}}) {
        if($level->{db} eq $userlevel) {
            croak("Userlevel $userlevel is already registered");
        }
    }

    my %ul = (
        display => $display,
        db => $userlevel,
        internal => "1",
    );

    # check if the root level of this userlevel has a "restrict" section and copy it to the sublevel
    if($userlevel =~ /\//) {
        my ($rootlevel, undef) = split/\//, $userlevel, 2;
        foreach my $level (@{$self->{userlevels}->{userlevel}}) {
            if($level->{db} eq $rootlevel && defined($level->{restrict})) {
                #print STDERR "Copy restrict ", $level->{restrict}, " from $rootlevel to $userlevel\n";
                $ul{restrict} = $level->{restrict};
                last;
            }
        }
    }

    push @{$self->{userlevels}->{userlevel}}, \%ul;

    return;
}

sub register_webpath($self, $userlevel, $webpath) {
    my $ok = 0;
    foreach my $level (@{$self->{userlevels}->{userlevel}}) {
        if($level->{db} eq $userlevel) {
            push @{$level->{webpaths}}, $webpath;
            $ok = 1;
            last;
        }
    }

    if(!$ok) {
        croak("Tried to register webpath $webpath but userlevel $userlevel is not registered");
    }

    return;
}

sub checkAccess($self, $uri, $permissions) {
    foreach my $level (@{$self->{userlevels}->{userlevel}}) {
        next unless(defined($level->{db}));
        next unless(defined($level->{webpaths}));

        foreach my $webpath (@{$level->{webpaths}}) {
            my $subpath = substr $uri, 0, length($webpath);
            if($subpath eq $webpath) {
                if(!contains($level->{db}, $permissions)) {
                    return 0;
                }
            }
        }
    }

    return 1;
}

sub checkAccessForUser($self, $uri, $username) {
    my $permissions = getPermissionForUser($username);
    return $self->checkAccess($uri, $permissions);
}


sub finalcheck($self) {

    # Check which webpaths are under restricted paths and print some stats
    my %levelpaths;
    my %levelcount;
    foreach my $level (@{$self->{userlevels}->{userlevel}}) {
        if(!defined($level->{db})) {
            croak("Userlevels: undefined DB for " . $level->{display});
        }
        if(defined($level->{internal}) && $level->{internal} == 1) {
            # internal user permission does not need a path
        } else {
            if(!defined($level->{path})) {
                croak("Userlevels: undefined PATH for " . $level->{display});
            }
            $levelpaths{$level->{path}} = $level->{db};
        }
        $levelcount{$level->{db}} = 0;
        
        if(defined($level->{restrict})) {
            my @parts = split/\,/, $level->{restrict};
            my @allowed;
            foreach my $part (@parts) {
                push @allowed, stripString($part);
            }
            $level->{restrict} = \@allowed;
        }
        
        
    }
    $levelcount{UNKNOWN} = 0;

    $self->updateDBPermissions();

    #print "** Normal webpaths:\n";
    my $paths = $self->{server}->get_webpaths;
    foreach my $path (sort keys %{$paths}) {
        my $dbpath = 'UNKNOWN';
        foreach my $lp (keys %levelpaths) {
            if($path =~ /^$lp/) {
                $dbpath = $levelpaths{$lp};
                last;
            }
        }
        $levelcount{$dbpath}++;
        #print '      ', doSpacePad($dbpath, 10), ' ', "$path\n";
    }

    #print "** Override webpaths:\n";
    my $opaths = $self->{server}->get_overridewebpaths;
    foreach my $path (sort keys %{$opaths}) {
        my $dbpath = 'UNKNOWN';
        foreach my $lp (keys %levelpaths) {
            if($path =~ /^$lp/) {
                $dbpath = $levelpaths{$lp};
                last;
            }
        }
        $levelcount{$dbpath}++;
        #print '      ', doSpacePad($dbpath, 10), ' ', "$path\n";
    }

    #print "    --- path statistics START ---\n";
    foreach my $key (sort keys %levelcount) {
        #print "     $key: $levelcount{$key}\n";
    }

    #print "    ---  path statistics END  ---\n";

    return;
}

sub updateDBPermissions($self) {
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my @perms;
    foreach my $level (@{$self->{userlevels}->{userlevel}}) {
        push @perms, $level->{db};
    }
    @perms = sort @perms;

    my $gselsth = $dbh->prepare("SELECT groupname FROM pagecamel.permissiongroups
                                ORDER BY groupname")
            or croak($dbh->errstr);

    my $eselsth = $dbh->prepare("SELECT permission_name FROM pagecamel.permissiongroupentries
                                 WHERE groupname = ?")
            or croak($dbh->errstr);

    my $inssth = $dbh->prepare("INSERT INTO pagecamel.permissiongroupentries (groupname, permission_name, subpermissions) 
                                VALUES (?, ?, 'NONE')")
            or croak($dbh->errstr);

    my $delsth = $dbh->prepare("DELETE FROM pagecamel.permissiongroupentries
                                WHERE groupname = ? AND permission_name = ?")
            or croak($dbh->errstr);

    if(!$gselsth->execute) {
        croak($dbh->errstr);
    }

    my @groups;
    while((my $line = $gselsth->fetchrow_hashref)) {
        push @groups, $line->{groupname};
    }
    $gselsth->finish;

    foreach my $group (@groups) {
        if(!$eselsth->execute($group)) {
            croak($dbh->errstr);
        }
        my @gperms;
        while((my $line = $eselsth->fetchrow_hashref)) {
            push @gperms, $line->{permission_name};
        }
        $eselsth->finish;

        # Check for missing entries
        foreach my $perm (@perms) {
            if(contains($perm, \@gperms)) {
                next;
            }

            $reph->debuglog("Adding new permission ", $perm, " for permission group ", $group);
            if(!$inssth->execute($group, $perm)) {
                croak($dbh->errstr);
            }
        }

        # Check for stale entries that are no longer in the config
        foreach my $perm (@gperms) {
            if(contains($perm, \@perms)) {
                next;
            }

            $reph->debuglog("Removing stale permission ", $perm, " from permission group ", $group);
            if(!$delsth->execute($group, $perm)) {
                croak($dbh->errstr);
            }
        }
    }

    #croak("BLA");

    $dbh->commit;
    return;
}

sub getPermissionTree($self) {
    my @tree;
    my @subpermissions;

    foreach my $level (@{$self->{userlevels}->{userlevel}}) {
        if($level->{db} =~ /\//) {
            push @subpermissions, $level;
            next;
        }

        my %perm = (
            db => $level->{db},
            display => $level->{display},
            standalone => 1,
        );
        push @tree, \%perm;
    }

    foreach my $level (@subpermissions) {
        my $ok = 1;

        my %perm = (
            db => $level->{db},
            display => $level->{display},
        );

        my ($root, undef) = split/\//, $level->{db}, 2;

        foreach my $branch (@tree) {
            if($branch->{db} eq $root) {
                $branch->{standalone} = 0;
                push @{$branch->{subpermissions}}, \%perm;
            }
        }
    }

    return \@tree;
}



1;
__END__

=head1 NAME

PageCamel::Web::Users::Userlevels -

=head1 SYNOPSIS

  use PageCamel::Web::Users::Userlevels;



=head1 DESCRIPTION



=head2 new



=head2 finalcheck



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
