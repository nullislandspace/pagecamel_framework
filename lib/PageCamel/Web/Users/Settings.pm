package PageCamel::Web::Users::Settings;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::DBSerialize;



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
    #nothing to register
    return;
}

sub get {
    my ($self, $username, $settingname) = @_;

    if(!defined($username) || !defined($settingname)) {
        return 0;
    }

    my $settingref;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $memhname = "UserSettings::" . $username . "::" . $settingname;

    $settingref = $memh->get($memhname);
    if(defined($settingref)) {
        return (1, $settingref);
    }

    my $sth = $dbh->prepare_cached("SELECT yamldata FROM users_settings " .
                            "WHERE username = ? AND settingname = ?")
                    or return 0;

    if(!$sth->execute($username, $settingname)) {
        return 0;
    }

    if((my @row = $sth->fetchrow_array)) {
        $settingref = dbderef(dbthaw($row[0]));
        $memh->set($memhname, $settingref);
    }
    $sth->finish;

    if(defined($settingref)) {
        return (1, $settingref);
    } else {
        return 0;
    }
}

sub set { ## no critic (NamingConventions::ProhibitAmbiguousNames)
    my ($self, $username, $settingname, $settingref) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $memhname = "UserSettings::" . $username . "::" . $settingname;

    my $sth = $dbh->prepare_cached("SELECT merge_users_settings(?, ?, ?)")
            or return;
    if(!$sth->execute($username, $settingname, dbfreeze($settingref))) {
        return;
    }
    $sth->finish;
    $memh->set($memhname, $settingref);

    return 1;
}

sub delete {## no critic(BuiltinHomonyms)
    my ($self, $username, $settingname) = @_;

    my $settingref;
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $memhname = "UserSettings::" . $username . "::" . $settingname;

    $memh->delete($memhname);

    my $sth = $dbh->prepare_cached("DELETE FROM users_settings " .
                            "WHERE username = ? AND settingname = ?")
            or return;
    if(!$sth->execute($username, $settingname)) {
        return;
    }

    $sth->finish;

    return 1;
}

sub list {
    my ($self, $username) = @_;

    my @settingnames;
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $sth = $dbh->prepare_cached("SELECT settingname FROM users_settings " .
                            "WHERE username = ? " .
                            "ORDER BY settingname")
                or return 0;
    if(!$sth->execute($username)) {
        return 0;
    }
    while((my @row = $sth->fetchrow_array)) {
        push @settingnames, $row[0];
    }
    $sth->finish;

    return (1, @settingnames);
}

1;
__END__

=head1 NAME

PageCamel::Web::Users::Settings -

=head1 SYNOPSIS

  use PageCamel::Web::Users::Settings;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 get



=head2 set



=head2 delete



=head2 list



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
