package PageCamel::Helpers::ClacksCachePg;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 1;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::DBSerialize;
use Time::HiRes qw(sleep);
use Readonly;


Readonly::Scalar my $RETRY_COUNT  => 10;
Readonly::Scalar my $RETRY_WAIT   => 0.05;


sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = bless \%config, $class;

    # Add version information about our to the memcached storage
    # for the rare cases we need that for other programs to run
    # a compatibility API or something
    $self->set("VERSION::" . $self->{APPNAME}, $VERSION);

    $self->{oldtime} = 0;

    return $self;
}


sub get {
    my ($self, $key) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

   # Try memcached first
    my $dataref = $memh->get($key);
    if(defined($dataref)) {
        return $dataref;
        #return PageCamel::Helpers::DBSerialize::dbthaw($dataref);
    }

   # Ok, try DB
   my $sth = $dbh->prepare_cached("SELECT yamldata FROM memcachedb WHERE mckey = ?")
         or croak($dbh->errstr);
   $sth->execute($key) or croak($dbh->errstr);
   while((my @line = $sth->fetchrow_array)) {
      $dataref = $line[0];
      last;
   }
   $sth->finish;
   $dbh->rollback;

   # Ok, now also store data in memcached
   if(defined($dataref)) {
      $dataref = PageCamel::Helpers::DBSerialize::dbthaw($dataref);
      $memh->set($key, $dataref);
      return $dataref;
   }

   return;
}

sub set { ## no critic (NamingConventions::ProhibitAmbiguousNames)
    my ($self, $key, $data) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $yamldata = PageCamel::Helpers::DBSerialize::dbfreeze($data);

    # Check if it already matches the key we have
    #my $olddata = $memh->get($key);
    #if(defined($olddata) && $olddata eq $yamldata) {
    #    return 1;
    #}

    # Let ClacksCache do it's own encoding
    $memh->set($key, $data);


    my $sth = $dbh->prepare_cached("SELECT merge_memcachedb(?, ?)")
            or return;
    my $count = 0;
    my $ok = 0;
    while($count < $RETRY_COUNT) {
        # print STDERR "WEB: Merge ($count) $key\n";
        if($sth->execute($key, $yamldata)) {
            $ok = 1;
            $sth->finish;
            $dbh->commit;
            last;
        } else {
            $count++;
            $sth->finish;
            $dbh->rollback;
            if($count < $RETRY_COUNT) {
                sleep($RETRY_WAIT); # try again in a short time
            }
        }
    }
    if(!$ok) {
        croak($dbh->errstr);
    }

    return 1;
}

sub delete {## no critic(BuiltinHomonyms)
    my ($self, $key) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

   $memh->delete($key);

   my $sth = $dbh->prepare_cached("DELETE FROM memcachedb WHERE mckey = ?")
         or croak($dbh->errstr);


    my $count = 0;
    my $ok = 0;
    while($count < $RETRY_COUNT) {
        #print STDERR "WEB: Delete ($count) $key\n";
        if($sth->execute($key)) {
            $sth->finish;
            $dbh->commit;
            $ok = 1;
            last;
        } else {
            $sth->finish;
            $dbh->rollback;
            $count++;
            if($count < $RETRY_COUNT) {
                sleep($RETRY_WAIT); # try again in a short time
            }
        }
    }

    if(!$ok) {
        croak($dbh->errstr);
    }

    return 1;
}

sub refresh_lifetick {
    my ($self) = @_;

    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    return $memh->refresh_lifetick();
}

sub disable_lifetick {
    my ($self) = @_;

    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    return $memh->disable_lifetick();
}

sub clacks_set {
    my ($self, $key, $data) = @_;

    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    return $memh->clacks_set($key, $data);
}

sub clacks_notify {
    my ($self, $key) = @_;

    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    return $memh->clacks_notify($key);
}

sub clacks_keylist {
    my ($self) = @_;

    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    return $memh->clacks_keylist();
}

1;
