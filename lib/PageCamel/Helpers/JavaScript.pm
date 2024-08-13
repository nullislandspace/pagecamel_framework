package PageCamel::Helpers::JavaScript;
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

use JavaScript::Embedded;
use JSON::XS;
use PageCamel::Helpers::DangerSign;
use Storable 'dclone';

sub new($class, %config) {
    my $self = bless \%config, $class;

    if(!defined($self->{reph})) {
        croak('PageCamel::Helpers::JavaScript needs reph reporting handler');
    }

    my $js;
    if(!defined($self->{timeout})) {
        croak('PageCamel::Helpers::JavaScript missing timeout setting!');
    } elsif(!$self->{timeout}) {
        $js = JavaScript::Embedded->new();
        print STDERR DangerSignUTF8();
        cluck('PageCamel::Helpers::JavaScript configured with a DISABLED timeout!');
    } else {
        $js = JavaScript::Embedded->new(timeout => $self->{timeout});
    }

    $self->{js} = $js;

    $self->{js}->set('debuglog' => sub {
        $self->_logfromjs($_[0]);
    });

    $self->{rawlines} = [];

    my $basecode = <<~ENDJSBASECODE;
        // START JavaScript.pm
        var memory = new Object;
        function __encode(obj) {
            return JSON.stringify(obj);
        }
        
        function __decode(txt) {
            return JSON.parse(txt);
        }
        
        function __setmemory(txt) {
            memory = __decode(txt);
        }
        
        function __getmemory() {
            return __encode(memory);
        }
        
        function __getKeys(obj) {
            var keys = Object.keys(obj);
            return keys;
        }
        // END JavaScript.pm
        ENDJSBASECODE



    if(!$self->loadCode($basecode)) {
        croak("Could not initialize JavaScript basecode");
    }

    $self->{lastError} = '';
    $self->{hasError} = 0;

    return $self;
}

sub _logfromjs($self, $text) {

    $self->{reph}->debuglog($text);

    return;
}

sub loadCode($self, $code) {
    if(!defined($code)) {
        croak("JS code undefined!");
    }

    my @lines = split/\n/, $code;
    foreach my $line (@lines) {
        $line =~ s/\r//g;
        push @{$self->{rawlines}}, $line;
    }
 
    $self->{hasError} = 0;
    $self->{lastError} = '';
    my $ok = 0;
    eval {
        $self->{js}->eval($code);
        $ok = 1;
    };

    if(!$ok) {
        $self->{hasError} = 1;
        $self->{lastError} = "Loading JS Code failed: " . $EVAL_ERROR;
        print STDERR  $self->{lastError}, "\n";
    }
    return $ok;
}

sub getCode($self) {
    # Don't return a reference to our internal lines, make sure we return a deep copy.
    # We might need to use those lines to re-init JavaScrip::Embedded in the future
    my $templines = dclone($self->{rawlines});

    return $templines;
}
    

sub call($self, $name, @arguments) {

    my $func = $self->{js}->get_object($name);
    if(!defined($func)) {
        print STDERR "Function $name does not exist!\n";
        return;
    }

    $self->{hasError} = 0;
    $self->{lastError} = '';
    my $ok = 0;
    my $retval;
    eval {
        $retval = $func->(@arguments);
        $ok = 1;
    };
    if(!$ok) {
        $self->{hasError} = 1;
        $self->{lastError} = "Function $name: " . $EVAL_ERROR;
        print STDERR  $self->{lastError}, "\n";
        return;
    }
    return $retval;

}

sub registerCallback($self, $name, $func) {

    $self->{js}->set($name, $func);

    return;
}

sub encode($self, $data) {

    return encode_json $data;
}

sub decode($self, $json) {

    return decode_json $json;
}

sub toArray($self, $object) {

    my @arr;
    $object->forEach(sub {
        my ($value, $index, $ar) = @_;
        push @arr, $value;
    });

    return @arr;


}

sub getKeys($self, $object) {

    my $rval = $self->call('__getKeys', $object);
    
    return $self->toArray($rval);
}

sub toHash($self, $object) {

    my @keys = $self->getKeys($object);
    my %hash;

    foreach my $key (@keys) {
        $hash{$key} = $object->$key;
    }

    return %hash;
}

sub setMemory($self, $memory) {

    $self->call('__setmemory', $memory);
    if($self->{hasError}) {
        return 0;
    }
    return 1;
}

sub getMemory($self) {

    return $self->call('__getmemory');
}

sub initMemory($self) {

    return $self->call('initMemory');
}

1;
