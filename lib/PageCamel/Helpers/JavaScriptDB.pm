package PageCamel::Helpers::JavaScriptDB;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.7;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Helpers::JavaScript);
use SUPER;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    if(!defined($config{timeout})) {
        $config{timeout} = 0; # Disable timeout when not set
    }

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    foreach my $key (qw[dbh reph table scriptname]) {
        if(!defined($self->{$key})) {
            croak("PageCamel::Helpers::JavaScriptDB needs $key");
        }
    }
    $self->{loaded} = 0;

    if(!defined($self->{logerror})) {
        $self->{logerror} = 0;
    }

    if($self->{logerror}) {
        foreach my $key (qw[errordbh errortextcolumn errorcountcolumn]) {
            if(!defined($self->{$key})) {
                croak("PageCamel::Helpers::JavaScriptDB needs $key");
            }
        }
    }

    if(defined($self->{moduletable}) && $self->{moduletable} ne '') {
        my $modulecode = <<~ENDJSMODULECODE;
            Duktape.modSearch = function (id) {
                var jscode = _loadJSModule(id);
                if(jscode != '') {
                    return jscode;
                } else {
                    throw new Error('module not found: ' + id);
                }
            };
            ENDJSMODULECODE

        $self->{js}->eval($modulecode);
        $self->{js}->set('_loadJSModule' => sub {
            return $self->_loadJSModule($_[0]);
        });
    } else {
        my $modulecode = <<~ENDJSNOMODULECODE;
            Duktape.modSearch = function (id) {
                throw new Error('Module loading not implemented');
            };
            ENDJSNOMODULECODE

        $self->{js}->eval($modulecode);
    }

    return $self;
}

sub init($self, $usercode, $systemcode) {
    if($self->{loaded}) {
        croak("init() called when script already loaded");
    }

    my $insth = $self->{dbh}->prepare_cached("INSERT INTO " . $self->{table} . " (scriptname, usercode, systemcode, memory) VALUES
                                        (?, ?, ?, ?)")
            or croak($self->{dbh}->errstr);

    my $loadok = 0;
    my $memory;
    eval {
        if($systemcode ne '') {
            $systemcode = "// START systemcode (JavaScriptDB.pm)\n" . $systemcode . "//END systemcode (JavaScriptDB.pm)\n";
            if(!$self->loadCode($systemcode)) {
                $self->saveLastError();
                return 0;
            }
        }
        $usercode = "// START usercode (JavaScriptDB.pm)\n" . $usercode . "//END usercode (JavaScriptDB.pm)\n";
        if(!$self->loadCode($usercode)) {
            $self->saveLastError();
            return 0;
        }
        if(!$self->initMemory()) {
            $self->saveLastError();
            return 0;
        }

        $memory = $self->getMemory();
        if(!defined($memory)) {
            $self->saveLastError();
            return 0;
        }

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
        if(!$self->loadCode($line->{systemcode})) {
            $self->saveLastError();
            return 0;
        }
    }
    if(!$self->loadCode($line->{usercode})) {
        $self->saveLastError();
        return 0;
    }

    if(!$self->setMemory($line->{memory})) {
        $self->saveLastError();
        return 0;
    }

    $self->{loaded} = 1;

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

    if(!defined($memory)) {
        $self->saveLastError();
        return 0;
    }

    if(!$upsth->execute($memory, $self->{scriptname})) {
        return 0;
    }

    return 1;
}

sub call($self, $name, @arguments) {

    my $retval = $self->SUPER($name, @arguments);

    if($self->{logerror} && $self->{hasError}) {
        $self->saveLastError();
    }

    return $retval;
}

sub _loadJSModule($self, $id) {

    $self->{reph}->debuglog("   Loading JS module $id");
    my $selsth = $self->{dbh}->prepare_cached("SELECT usercode FROM " . $self->{moduletable} . " " .
                                              "WHERE scriptname = ?")
            or croak($self->{dbh}->errstr);

    if(!$selsth->execute($id)) {
        $self->{reph}->debuglog($self->{dbh}->errstr);
        $self->{dbh}->rollback;
        return '';
    }

    my $line = $selsth->fetchrow_hashref;
    $selsth->finish;
    $self->{dbh}->commit;

    if(defined($line) && defined($line->{usercode}) && $line->{usercode} ne '') {
        $self->{reph}->debuglog("   Loaded module $id for ", $self->{scriptname});
        return $line->{usercode};
    }
    $self->{reph}->debuglog("   Module $id not found for ", $self->{scriptname});

    return '';
}

sub saveLastError($self) {
    #print STDERR "LOGERROR ", $self->{logerror}, " HASERROR ", $self->{hasError}, " LASTERROR", $self->{lastError}, "\n";
    if(!$self->{logerror} || !$self->{hasError}) {
        return;
    }

    my $upsth = $self->{errordbh}->prepare_cached("UPDATE " . $self->{table} .
                                                  " SET " . $self->{errortextcolumn} . " = ?," . 
                                                  " " . $self->{errorcountcolumn} . ' = ' . $self->{errorcountcolumn} . " + 1" .
                                                  " WHERE scriptname = ?"
                                              )
            or croak($self->{errordbh}->errstr);


    if(!$upsth->execute($self->{lastError}, $self->{scriptname})) {
        $self->{reph}->debuglog($self->{errordbh}->errstr);
        $self->{errordbh}->rollback;
        return;
    }

    $self->{errordbh}->commit;

    return;
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
