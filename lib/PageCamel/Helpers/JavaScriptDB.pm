package PageCamel::Helpers::JavaScriptDB;
#---AUTOPRAGMASTART---
use 5.032;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.1;
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

    foreach my $key (qw[dbh reph table scriptname]) {
        if(!defined($self->{dbh})) {
            croak('PageCamel::Helpers::JavaScriptDB needs $key');
        }
    }
    $self->{loaded} = 0;

    return $self;
}

sub init($self, $usercode, $systemcode) {
    if($self->{loaded}) {
        croak("init() called when script already loaded");
    }

    my $insth = $self->{dbh}->prepare_cached("INSERT TO " . $self->{table} . " (scriptname, usercode, systemcode, memory) VALUES
                                        (?, ?, ?, ?)")
            or croak($self->{dbh}->errstr);

    my $loadok = 0;
    my $memory;
    eval {
        if($systemcode ne '') {
            $self->loadCode($systemcode);
        }
        $self->loadCode($usercode);
        $self->initMemory();

        $memory = $self->getMemory();
        $loadok = 1;
    };

    if(!$loadok) {
        return 0;
    }

    if(!$insth->execute($self->{scriptname}, $usercode, $systemcode, $memory)) {
        $self->{reph}->debuglog($self->{dbh}->errstr);
        return 0;
    }
    $insth->finish;

    $self->{loaded} = 1;

    return 1;
}

sub load($self) {
    if($self->{loaded}) {
        croak("load() called when script already loaded");
    }

    my $selsth = $self->{dbh}->prepare_cached("SELECT usercode, systemcode, memory FROM " . $self->{table} . "
                                        WHERE scriptname = ?")
            or croak($self->{dbh}->errstr);

    if(!$selsth->execute($self->{scriptname})) {
        return 0;
    }
    my $line = $selsth->fetchrow_hashref;
    $selsth->finish;
    if(!defined($line) || !defined($line->{usercode}) || !defined($line->{systemcode}) || !defined($line->{memory})) {
        return;
    }

    if($line->{systemcode} ne '') {
        $self->loadCode($line->{systemcode});
    }
    $self->loadCode($line->{usercode});
    $self->setMemory($line->{memory});

    return 1;
}

sub save($self) {
    if(!$self->{loaded}) {
        croak("save() called when script not loaded");
    }

    my $upsth = $self->{dbh}->prepare_cached("UPDATE " . $self->{table} . " SET memory = ?
                                        WHERE scriptname = ?")
            or croak($self->{dbh}->errstr);

    my $memory = $self->getMemory();

    if(!$upsth->execute($memory, $self->{id})) {
        return 0;
    }

    return 1;
}
    
# WARNING: This is experimental, since we are loading new javascript functions with the same name over the existing ones
# Default is NOT to call any memory initialization/memory update functions. You can either specifiy a function name or use INIT
# to call the default memory init function
sub updateSystemCode($self, $newcode, $memoryupdatefunction = '') {
    if(!$self->{loaded}) {
        croak("updateSystemCode() called when script not loaded");
    }
    return $self->_updateCode($newcode, 'systemcode', '');
}

sub updateUserCode($self, $newcode, $memoryupdatefunction = '') {
    if(!$self->{loaded}) {
        croak("updateUserCode() called when script not loaded");
    }
    return $self->_updateCode($newcode, 'usercode', $memoryupdatefunction);
}

sub _updateCode($self, $newcode, $column, $memoryupdatefunction) {

    if(!$self->{loaded}) {
        croak("_updateCode() called when script not loaded");
    }

    if($memoryupdatefunction eq 'INIT') {
        $memoryupdatefunction = 'initMemory';
    }

    $self->loadCode($newcode);
    if($memoryupdatefunction ne '') {
        $self->call($memoryupdatefunction);
    }

    my $upsth = $self->{dbh}->prepare_cached("UPDATE " . $self->{table} . " SET " . $column . " = ?, memory = ?
                                        WHERE scriptname = ?")
            or croak($self->{dbh}->errstr);

    my $memory = $self->getMemory();

    if(!$upsth->execute($newcode, $memory, $self->{scriptname})) {
        return 0;
    }

    return 1;

}

1;
