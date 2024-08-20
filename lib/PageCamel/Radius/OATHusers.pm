package PageCamel::Radius::OATHusers;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.5;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use PageCamel::Helpers::Passwords;
use DBI;

sub new($class) {
    my $self = bless {}, $class;

    croak("This module needs a rewrite for new Passwords handling code (see Helpers::Passwords)");

    return $self;
}

sub validate($self, $database, $username, $password, $service) {

    # Missing fields
    if(!defined($username) || !defined($password) || !defined($service) ||
       $username eq '' || $password eq '' || $service eq '') {
        return 0;
    }

    print STDERR "Connecting to DB...\n";
    my $dbh = DBI->connect($database->{dburl},
                           $database->{dbuser},
                           $database->{dbpassword},
                           {AutoCommit => 0})
            or return 0;
    #print STDERR "$username / $password\n";

    # For the easy part: Check length of password
    my $valid = 0;
    my $permission_name = 'has_' . $service;
    if(verify_password($dbh, $username, $password)) {
        my $selsth = $dbh->prepare("SELECT * FROM users_permissions
                                   WHERE username = ?
                                   and permission_name = ?")
                or croak($dbh->errstr);
        $selsth->execute($username, $permission_name)
                or croak($dbh->errstr);
        while((my $line = $selsth->fetchrow_hashref)) {
            if($line->{has_access}) {
                $valid = 1;
            }
        }
        $selsth->finish;
    }

    $dbh->rollback;
    $dbh->disconnect;

    return $valid;
}

1;
__END__

=head1 NAME

PageCamel::Radius::OATHusers - experimental module for using the PageCamel user managment for RADIUS authentication.

=head1 SYNOPSIS

  use PageCamel::Radius::OATHusers;

=head1 DESCRIPTION

Experimental module for using the PageCamel user managment for RADIUS authentication.

=head2 new

Create a new instance.

=head2 validate

Validate a login attempt.

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
