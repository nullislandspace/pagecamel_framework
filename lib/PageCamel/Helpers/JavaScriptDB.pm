package PageCamel::Helpers::JavaScriptDB;
#---AUTOPRAGMASTART---
use 5.032;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.0;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
use feature 'signatures';
no warnings qw(experimental::signatures);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Helpers::JavaScript);

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    foreach my $key (qw[dbh table]) {
        if(!defined($self->{dbh})) {
            croak('PageCamel::Helpers::JavaScriptDB needs $key');
        }
    }
    $self->{loaded} = 0;

    return $self;
}

sub init($self, $code) {
    my $dbh = $self->{dbh};

    my $insth = $dbh->prepare_cached("INSERT TO " . $self->{table} . " (javascript, memory) VALUES
                                        (?, ?) RETURNING script_id")
            or croak($dbh->errstr);

    $self->loadCode($code);
    $self->initMemory();

    my $memory = $self->getMemory();

    if(!$insth->execute($code, $memory)) {
        return;
    }
    my $idline = $insth->fetchrow_hashref;
    $insth->finish;
    if(!defined($idline) || !defined($idline->{script_id})) {
        return;
    }

    $self->{id} = $idline->{script_id};

    return $idline->{script_id};
}

sub load($self) {
    my $dbh = $self->{dbh};

    if(!defined($self->{id})) {
        croak("ID not defined for load()");
    }
    if($self->{loaded}) {
        croak("load() called when script already loaded");
    }

    my $selsth = $dbh->prepare_cached("SELECT javascript, memory FROM " . $self->{table} . "
                                        WHERE script_id = ?")
            or croak($dbh->errstr);

    if(!$selsth->execute($self->{id})) {
        return 0;
    }
    my $line = $selsth->fetchrow_hashref;
    $selsth->finish;
    if(!defined($line) || !defined($line->{javascript}) || !defined($line->{memory})) {
        return;
    }

    $self->loadCode($line->{javascript});
    $self->setMemory($line->{memory});

    return 1;
}

sub save($self) {
    my $dbh = $self->{dbh};

    if(!defined($self->{id})) {
        croak("ID not defined for load()");
    }
    if(!$self->{loaded}) {
        croak("save() called when script not loaded");
    }

    my $upsth = $dbh->prepare_cached("UPDATE " . $self->{table} . " SET memory = ?
                                        WHERE script_id = ?")
            or croak($dbh->errstr);

    my $memory = $self->getMemory();

    if(!$upsth->execute($memory, $self->{id})) {
        return 0;
    }

    return 1;
}
    
# WARNING: This is experimental, since we are loading new javascript functions with the same name over the existing ones
# Default is NOT to call any memory initialization/memory update functions. You can either specifiy a function name or use INIT
# to call the default memory init function
sub update($self, $newcode, $memoryupdatefunction = '') {
    if(!defined($self->{id})) {
        croak("ID not defined for update()");
    }

    if(!$self->{loaded}) {
        croak("update() called when script not loaded");
    }

    if($memoryupdatefunction eq 'INIT') {
        $memoryupdatefunction = 'initMemory';
    }

    $self->loadCode($newcode);
    if($memoryupdatefunction ne '') {
        $self->call($memoryupdatefunction);
    }

    my $upsth = $dbh->prepare_cached("UPDATE " . $self->{table} . " SET javascript = ?, memory = ?
                                        WHERE script_id = ?")
            or croak($dbh->errstr);

    my $memory = $self->getMemory();

    if(!$upsth->execute($newcode, $memory, $self->{id})) {
        return 0;
    }

    return 1;

}

1;
