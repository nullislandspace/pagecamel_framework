package PageCamel::Helpers::PostgresDB;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 2.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

use PageCamel::Helpers::DateStrings;
use Pg::hstore;
use DBI;
use XML::Simple;

use Readonly;
Readonly::Scalar my $BLOBMODE => 0x00020000; ## no critic (ValuesAndExpressions::RequireNumberSeparators)

sub updateConfig {
    my ($self) = @_;
    
    # This must be done *AFTER* new in SUPER (to handle host specific cases)
    if(defined($self->{include})) {
        if(!-f $self->{include} ) {
            croak("Can't find include config " . $self->{include});
        }
        print "    Loading PostgreSQL connection info from ", $self->{include}, "\n";
        my $include = XMLin($self->{include});
        foreach my $key (qw[dburl dbuser dbpassword hosts]) {
            if(defined($include->{$key})) {
                $self->{$key} = $include->{$key};
            }
        }
    }

    $self->{disconnectIsFatal} = 0;
    $self->{firstConnect} = 1;

    $self->{nextping} = 0;

    return;
}

sub checkDBH {
    my ($self, $hasforked) = @_;

    if(!defined($hasforked)) {
        $hasforked = 0;
    }
    
    if($hasforked && defined($self->{mdbh})) {
        $self->{firstConnect} = 1;
        $self->{mdbh}->disconnect;
        delete $self->{mdbh};
    }
    
    my $now = time;

    # Check every 60 seconds if connection is still working correctly
    if(defined($self->{mdbh})) {
        if($self->{nextping} > $now) {
            return;
        } else {
            if($self->{mdbh}->ping) {
                $self->{nextping} = $now + 60;
                return;
            } else {
                $self->{mdbh}->disconnect;
                delete $self->{mdbh};
            }
        }
    }


    if($self->{disconnectIsFatal} && !$self->{firstConnect}) {
        print STDERR "Disconnect detected and flag disconnectIsFatal is set!\n";
        exit(1);
    }
    $self->{firstConnect} = 0;

    my $dbh = DBI->connect($self->{dburl}, $self->{dbuser}, $self->{dbpassword},
                               {AutoCommit => 0, RaiseError => 0}) or croak($EVAL_ERROR);
    $self->{mdbh} = $dbh;
    #$dbh->{pg_enable_utf8} = 1;

    my $appname = $self->{APPNAME} . "/" . $self->{modname} . " $PID";
    if($dbh->do("SET application_name = '$appname'; ")) {
        $dbh->commit;
    }

    return;
}

sub DESTROY {
    my ($self) = @_;

    if(!defined($self->{mdbh})) {
        return;
    }

    $self->{mdbh}->rollback;
    $self->{mdbh}->disconnect;
    delete $self->{mdbh};
    return;
}

sub reload {
    my ($self) = shift;
    # Nothing to do..
    return;
}

sub register {
    my $self = shift;

    $self->register_cleanup("cleanup");

    return;
}

sub cleanup {
    my ($self) = @_;

    $self->checkDBH();
    $self->{mdbh}->rollback;

    return;
}

sub dbd_options {
    my ($self, $key, $value) = @_;
    
    $self->checkDBH();
    if(defined($value)) {
        $self->{mdbh}->{$key} = $value;
    }
    my $newvalue = $self->{mdbh}->{$key};
    return $newvalue;
}

BEGIN {
    # Auto-magically generate a number of similar functions without actually
    # writing them down one-by-one. This makes changes much easier, but
    # you need perl wizardry level +10 to understand how it works...
    my @stdFuncs = qw(prepare prepare_cached do quote pg_savepoint pg_rollback_to pg_release);
    my @simpleFuncs = qw(commit rollback errstr);
    my @varSetFuncs = qw(AutoCommit RaiseError);
    my @varGetFuncs = qw();

    for my $a (@simpleFuncs){
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
        *{__PACKAGE__ . "::$a"} = sub { $_[0]->checkDBH(); return $_[0]->{mdbh}->$a(); };
    }

    for my $a (@stdFuncs){
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
        *{__PACKAGE__ . "::$a"} = sub { $_[0]->checkDBH(); if(0 && $_[0]->{isDebugging}) {print STDERR $_[0]->{modname}, " ", $_[1], "\n";}; return $_[0]->{mdbh}->$a($_[1]); };
    }
    
    for my $a (@varSetFuncs){
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
        *{__PACKAGE__ . "::$a"} = sub { $_[0]->checkDBH(); return $_[0]->{mdbh}->{$a} = $_[1]; };
    }

    for my $a (@varGetFuncs){
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
        *{__PACKAGE__ . "::$a"} = sub { $_[0]->checkDBH(); return $_[0]->{mdbh}->{$a}; };
    }



    ### BLOB handling primitives ###
    my @blobFuncs = qw(write read lseek tell close unlink import export);
    {
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)

        *{__PACKAGE__ . "::pg_lo_creat"} = sub {
            $_[0]->checkDBH();
            return $_[0]->{mdbh}->pg_lo_creat($BLOBMODE);
        };

        *{__PACKAGE__ . "::pg_lo_open"} = sub {
            $_[0]->checkDBH();
            return $_[0]->{mdbh}->pg_lo_open($_[1], $BLOBMODE);
        };

    }

    for my $x (@blobFuncs){
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
        $x = "pg_lo_$x";
        *{__PACKAGE__ . "::$x"} = sub {
            my ($self, @args) = @_;
            $self->checkDBH();
            return $self->{mdbh}->$x(@args);
        };
    }
}

sub decode_hstore {
    my ($self, $val) = @_;

    # return hashref
    return Pg::hstore::decode($val);
}

sub encode_hstore {
    my ($self, $hashref) = @_;

    # return string
    return Pg::hstore::encode($hashref);
}

sub pg_notifies {
    my ($self) = @_;

    $self->checkDBH();
    my $notify = $self->{mdbh}->pg_notifies;
    return $notify;
}

# Sample of autogenerated function
#sub prepare {
#    my ($self, $arg) = @_;
#
#    return $self->{mdbh}->prepare($arg);
#}

1;
__END__
