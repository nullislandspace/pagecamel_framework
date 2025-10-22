package PageCamel::Helpers::PostgresDB;
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

use PageCamel::Helpers::DateStrings;
use Pg::hstore;
use DBI;
use PageCamel::Helpers::ConfigLoader;

use Readonly;
Readonly::Scalar my $BLOBMODE => 0x00020000; ## no critic (ValuesAndExpressions::RequireNumberSeparators)

sub updateConfig($self) {
    # This must be done *AFTER* new in SUPER (to handle host specific cases)
    if(defined($self->{include})) {
        print "    Using PostgreSQL connection info from ", $self->{include}, "\n";
        my $include = LoadConfig($self->{include});
        foreach my $key (qw[dburl dbuser dbpassword hosts]) {
            if(defined($include->{$key})) {
                $self->{$key} = $include->{$key};
            }
        }
    }

    $self->{disconnectIsFatal} = 0;
    $self->{firstConnect} = 1;

    $self->{nextping} = 0;

    $self->{lastprepare} = '';

    return;
}

sub checkDBH($self, $hasforked = false) {
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
                               {
                                   AutoCommit => 0,
                                   RaiseError => 0,
                                   PrintError => 0,
                                   PrintWarn  => 0,
                                   AutoInactiveDestroy => 1,
                               }) or croak("$EVAL_ERROR");
    $self->{mdbh} = $dbh;
    #$dbh->{pg_enable_utf8} = 1;

    $dbh->{pg_prepare_now} = 1; # prepare() and prepare_cached() run immediately in most standard cases, not on the first execute(). This makes debugging easier.

    my $appname = $self->{APPNAME} . "/" . $self->{modname} . " $PID";
    if($dbh->do("SET application_name = '$appname'; ")) {
        $dbh->commit;
    }

    return;
}

sub getColumnType($self, $xtable, $xcolumn) {
    my $table = '' . $xtable;
    my $column = '' . $xcolumn;

    $self->checkDBH();

    my $xdebug = 0;
    if(0 && $table eq 'pos.workstations' && $column =~ /printerqueue/) {
        $xdebug = 1;
    }

    my $schema = 'public';
    my $subtype;
    if($table =~ /\./) {
        ($schema, $table) = split/\./, $table;
    }

    if($column =~ /\./) {
        ($column, $subtype) = split/\./, $column;
    }

    if($xdebug) {
        print STDERR "###### $schema / $table \n";
    }

    # Normalize array element to the base array
    if($column =~ /\[\d+\]$/) {
        $column =~ s/\[\d+\]$//;
    }

    if($xdebug) {
        print STDERR "###### $schema / $table \n";
    }

    my $type;

    my $sth = $self->{mdbh}->prepare_cached("SELECT pg_catalog.format_type(c.atttypid, NULL) AS data_type
                                                FROM pg_attribute c
                                                  JOIN pg_class t on c.attrelid = t.oid
                                                  JOIN pg_namespace n on t.relnamespace = n.oid
                                                WHERE 
                                                  n.nspname = ?
                                                  AND t.relname = ?
                                                  AND c.attname = ?
                                                  AND c.attnum >= 0")
            or croak($self->{mdbh}->errstr);
    $sth->execute($schema, $table, $column) or croak($self->{mdbh}->errstr);
    while ((my $line = $sth->fetchrow_hashref)) {
        $type = lc $line->{data_type};
        if($type =~ /\[\]$/) {
            $type =~ s/\[\]$//;
        }
        if($xdebug) {
            print STDERR "###### $type \n";
        }
    }
    $sth->finish;

    $self->{mdbh}->commit;

    if(defined($subtype) && defined($type)) {
        if($xdebug) {
            print STDERR "####### Need to solve for subtype $subtype of type $type\n";
        }
        $type = $self->getColumnType($type, $subtype);
        if($xdebug) {
            if(defined($type)) {
                print STDERR "#######   resolved to $type\n";
            } else {
                print STDERR "#######   FAILED TO RESOLVE!!!!\n";
            }
        }
    }


    return $type;
}

sub getDefaultValue($self, $xtable, $xcolumn, $dateexpander=0) {
    my $table = '' . $xtable;
    my $column = '' . $xcolumn;

    $self->checkDBH();

    my $sth = $self->{mdbh}->prepare_cached("SELECT column_name, column_default, data_type
                                                FROM information_schema.columns
                                                WHERE table_schema = ?
                                                AND table_name = ?
                                                AND column_name = ?")
            or croak($self->{mdbh}->errstr);
    
    my $schema = 'pagecamel';
    if($table =~ /\./) {
        ($schema, $table) = split/\./, $table;
    }

    if(!$sth->execute($schema, $table, $column)) {
        croak($self->{mdbh}->errstr);
    }

    my $line = $sth->fetchrow_hashref;
    $sth->finish;
    $self->{mdbh}->commit;

    if(!defined($line) || !defined($line->{column_default}) || $line->{column_default} eq '') {
        return;
    }

    if($dateexpander && $line->{data_type} =~ /(date|time)/ && $line->{column_default} =~ /now\(\)/) {
        return 'XXAUTOEXPANDXX_' . $line->{column_default};
    }

    if($line->{column_default} =~ /^nextval/) {
        return;
    }

    $line->{column_default} =~ s/\:\:.*//;
    $line->{column_default} =~ s/^\'//;
    $line->{column_default} =~ s/\'$//;
    if($line->{column_default} eq 'true') {
        $line->{column_default} = 1;
    } elsif($line->{column_default} eq 'false') {
        $line->{column_default} = 0;
    } 

    if($line->{column_default} eq '') {
        return;
    }

    return $line->{column_default};
}

sub reload($self) {
    # Nothing to do..
    return;
}

sub register($self) {
    $self->register_cleanup("cleanup");

    return;
}

sub cleanup($self) {
    $self->checkDBH();
    $self->{mdbh}->rollback;

    return;
}

sub dbd_options($self, $key, $value) {
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
    #my @stdFuncs = qw(prepare prepare_cached do quote pg_savepoint pg_rollback_to pg_release);
    my @stdFuncs = qw(do quote pg_savepoint pg_rollback_to pg_release);
    my @simpleFuncs = qw(commit rollback errstr);
    my @varSetFuncs = qw(AutoCommit RaiseError);
    my @varGetFuncs = qw();
    my @handleFuncs = qw(prepare prepare_cached);

    for my $f (@simpleFuncs){
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
        *{__PACKAGE__ . "::$f"} = sub ($arg1) { 
            $arg1->checkDBH();
            $arg1->{lastprepare} = '';
            return $arg1->{mdbh}->$f();
        };
    }

    for my $f (@stdFuncs){
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
        *{__PACKAGE__ . "::$f"} = sub ($arg1, $arg2) {
            $arg1->checkDBH();
            if(0 && $arg1->{isDebugging}) {
                print STDERR $arg1->{modname}, " ", $arg2, "\n";
            };
            return $arg1->{mdbh}->$f($arg2);
        };
    }
    
    for my $f (@handleFuncs){
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
        *{__PACKAGE__ . "::$f"} = sub ($arg1, $arg2) {
            $arg1->checkDBH();
            $arg1->{lastprepare} = $arg2;
            my $sth = $arg1->{mdbh}->$f($arg2);
            $sth->{Callbacks}->{execute} = sub {
                if(scalar @_ > 1) {
                    for(my $j = 1; $j < scalar @_; $j++) {
                        if(ref $_[$j] eq '' && !is_utf8($_[$j])) {
                            eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                                my $temp = decode_utf8($_[$j]);
                                $_[$j] = $temp;
                            };
                        }
                    }
                }

                return;
            };
            return $sth;
        };
    }

    for my $f (@varSetFuncs){
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
        *{__PACKAGE__ . "::$f"} = sub ($arg1, $arg2) {
            $arg1->checkDBH();
            return $arg1->{mdbh}->{$f} = $arg2;
        };
    }

    for my $f (@varGetFuncs){
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
        *{__PACKAGE__ . "::$f"} = sub ($arg1) {
            $arg1->checkDBH();
            return $arg1->{mdbh}->{$f};
        };
    }



    ### BLOB handling primitives ###
    my @blobFuncs = qw(write read lseek tell close unlink import export);
    {
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)

        *{__PACKAGE__ . "::pg_lo_creat"} = sub ($arg1, $BLOBMODE) {
            $arg1->checkDBH();
            return $arg1->{mdbh}->pg_lo_creat($BLOBMODE);
        };

        *{__PACKAGE__ . "::pg_lo_open"} = sub ($arg1, $BLOBID, $BLOBMODE) {
            $arg1->checkDBH();
            return $arg1->{mdbh}->pg_lo_open($BLOBID, $BLOBMODE);
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

sub decode_hstore($self, $val) {
    # return hashref
    return Pg::hstore::decode($val);
}

sub encode_hstore($self, $hashref) {
    # return string
    return Pg::hstore::encode($hashref);
}

sub pg_notifies($self) {
    $self->checkDBH();
    my $notify = $self->{mdbh}->pg_notifies;
    return $notify;
}

# Sample of autogenerated function
#sub prepare($self, $arg) {
#
#    return $self->{mdbh}->prepare($arg);
#}

1;
__END__
