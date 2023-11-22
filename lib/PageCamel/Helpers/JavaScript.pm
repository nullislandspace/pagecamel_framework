package PageCamel::Helpers::JavaScript;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.3;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use JavaScript::Embedded;
use JSON::XS;

sub new($class, %config) {
    my $self = bless \%config, $class;

    if(!defined($self->{reph})) {
        croak('PageCamel::Helpers::JavaScript needs reph reporting handler');
    }

    if(!defined($self->{timeout})) {
        croak('PageCamel::Helpers::JavaScript needs timeout (default timeout value)');
    }

    my $js = JavaScript::Embedded->new(timeout => $self->{timeout});
    $self->{js} = $js;

    $self->{js}->set('debuglog' => sub {
        $self->_logfromjs($_[0]);
    });

    $self->{js}->eval(qq{
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
        
    });

#    if(defined($self->{code})) {
#        $self->load();
#    }


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

    $self->{code} = $code;
 
    $self->{js}->eval($self->{code});

    return;
}

sub call($self, $name, @arguments) {

    my $func = $self->{js}->get_object($name);
    if(!defined($func)) {
        print STDERR "Function $func does not exist!\n";
        return;
    }
    return $func->(@arguments);
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

    return;
}

sub getMemory($self) {

    return $self->call('__getmemory');
}

sub initMemory($self) {

    $self->call('initMemory');
    return;
}

1;
