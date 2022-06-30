package PageCamel::Web::SessionSettings;
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
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::DBSerialize;
use Time::HiRes qw(time);
use Readonly;

Readonly::Scalar my $RETRY_COUNT  => 10;
Readonly::Scalar my $RETRY_WAIT   => 0.05;



sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{lastClean} = time;

    return $self;
}

sub reload($self) {
    # Nothing to do.. in here, we only use the template and database module
    return;
}

sub register($self) {
    $self->register_logoutitem("on_logout");
    return;
}

# NOTE: We have TWO sets of data for each session:
# The first data set is the used keys within a session (a hash),
# the second set of data are the actual entries.
# We don't actually have to manage something like "last access"
# right now, we depend on beeing onLogout() called by the
# login module for timed-out sessions

sub get($self, $settingname) {

    my $settingref;

    my $loginh = $self->{server}->{modules}->{$self->{login}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $sessionid = $loginh->get_sessionid;
    return 0 if(!defined($sessionid));

    my $keyname = "SessionSettings::" . $sessionid . "::" . $settingname;

    $settingref = $memh->get($keyname);
    if(defined($settingref)) {
        return (1, $settingref);
    }

    # Ok, try DB
    my $sth = $dbh->prepare_cached("SELECT yamldata FROM session_settings WHERE sid = ? AND skey = ?")
          or croak($dbh->errstr);
    $sth->execute($sessionid, $settingname) or croak($dbh->errstr);
    while((my @line = $sth->fetchrow_array)) {
       $settingref = $line[0];
       last;
    }
    $sth->finish;
    $dbh->rollback;

    # Ok, now also store data in memcached
    if(defined($settingref)) {
       $settingref = dbderef(dbthaw($settingref));
       $memh->set($keyname, $settingref);
        return (1, $settingref);
    }

    return 0;
}

sub set($self, $settingname, $settingref) {

    my $loginh = $self->{server}->{modules}->{$self->{login}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $sessionid = $loginh->get_sessionid;
    return 0 if(!defined($sessionid));

    my $keyname = "SessionSettings::" . $sessionid . "::" . $settingname;

    $memh->set($keyname, $settingref);
    
    my $yamldata = dbfreeze($settingref);

    my $sth = $dbh->prepare_cached("SELECT merge_sessionsettings(?, ?, ?)")
            or return;

    my $count = 0;
    my $ok = 0;
    while($count < $RETRY_COUNT) {
        # print STDERR "SESSION: ($count) Merge $sessionid / $settingname\n";
        if(!$sth->execute($sessionid, $settingname, $yamldata)) {
            $sth->finish;
            $dbh->rollback;
            $count++;
            if($count < $RETRY_COUNT) {
                sleep($RETRY_WAIT); # sleep for a short time and try again
            }
         } else {
            $sth->finish;
            $dbh->commit;
            $ok = 1;
            last;
         }
    }
    if(!$ok) {
        return 0;
    }

    return 1;
}

sub delete($self, $settingname, $forcedid = undef) {

    my $settingref;

    my $loginh = $self->{server}->{modules}->{$self->{login}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $sessionid = $loginh->get_sessionid;
    if(defined($forcedid)) {
        $sessionid = $forcedid;
    }
    return 0 if(!defined($sessionid));

    my $keyname = "SessionSettings::" . $sessionid . "::" . $settingname;


    $memh->delete($keyname);

    my $sth = $dbh->prepare_cached("DELETE FROM session_settings WHERE sid = ? AND skey = ?")
         or croak($dbh->errstr);

    my $count = 0;
    my $ok = 0;
    while($count < $RETRY_COUNT) {
        # print STDERR "SESSION: Delete ($count) $sessionid / $settingname\n";
        if(!$sth->execute($sessionid, $settingname)) {
            $sth->finish;
            $dbh->rollback;
            $count++;
            if($count < $RETRY_COUNT) {
                sleep($RETRY_WAIT);
            }
        } else {
            $sth->finish;
            $dbh->commit;
            $ok = 1;
            last;
        }
    }

    if(!$ok) {
        croak($dbh->errstr);
    }

    return 1;
}

sub list($self, $forcedid = undef) {

    my @settingnames = ();

    my $loginh = $self->{server}->{modules}->{$self->{login}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $sessionid = $loginh->get_sessionid;

    if(defined($forcedid)) {
        $sessionid = $forcedid;
    }

    return 0 if(!defined($sessionid));

    my $sth = $dbh->prepare_cached("SELECT skey FROM session_settings WHERE sid = ?")
        or croak($dbh->errstr);
    $sth->execute($sessionid) or croak($dbh->errstr);
    while((my @line = $sth->fetchrow_array)) {
        push @settingnames, $line[0];
    }
    $sth->finish;
    $dbh->rollback;

    return (1, @settingnames);
}

sub on_logout($self, $sessionid) {

    my ($status, @keys) = $self->list($sessionid);
    if($status != 0) {
        foreach my $key (@keys) {
            $self->delete($key, $sessionid);
        }
    }
    return;
}

1;
__END__

=head1 NAME

PageCamel::Web::SessionSettings -

=head1 SYNOPSIS

  use PageCamel::Web::SessionSettings;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 get



=head2 set



=head2 delete



=head2 list



=head2 on_logout



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
