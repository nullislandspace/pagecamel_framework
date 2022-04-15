package PageCamel::Helpers::JavaScript;
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

BEGIN {
    mkdir '/tmp/pagecamel_helpers_javascript_inline';
    $ENV{PERL_INLINE_DIRECTORY} = '/tmp/pagecamel_helpers_javascript_inline';
};
use JavaScript::Duktape;
use JSON::XS;

sub new {
    my ($class, %config) = @_;
    my $self = bless \%config, $class;

    if(!defined($self->{reph})) {
        croak('PageCamel::Helpers::JavaScript needs reph reporting handler');
    }

    if(!defined($self->{timeout})) {
        croak('PageCamel::Helpers::JavaScript needs timeout (default timeout value)');
    }

    my $js = JavaScript::Duktape->new(timeout => $self->{timeout});
    $self->{js} = $js;

    $self->{js}->set('log' => sub {
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

    if(defined($self->{code})) {
        $self->load();
    }


    return $self;
}

sub _logfromjs {
    my ($self, $text) = @_;

    $self->{reph}->debuglog($text);

    return;
}

sub load {
    my ($self, $code) = @_;

    if(defined($code)) {
        $self->{code} = $code;
    }
 
    $self->{js}->eval($self->{code});

    return;
}

sub call {
    my ($self, $name, @arguments) = @_;

    my $func = $self->{js}->get_object($name);
    if(!defined($func)) {
        print STDERR "Function $func does not exist!\n";
        return;
    }
    return $func->(@arguments);
}

sub registerCallback {
    my ($self, $name, $func) = @_;

    $self->{js}->set($name, $func);

    return;
}

sub encode {
    my ($self, $data) = @_;

    return encode_json $data;
}

sub decode {
    my ($self, $json) = @_;

    return decode_json $json;
}

sub toArray {
    my ($self, $object) = @_;

    my @arr;
    $object->forEach(sub {
        my ($value, $index, $ar) = @_;
        push @arr, $value;
    });

    return @arr;


}

sub getKeys {
    my ($self, $object) = @_;

    my $rval = $self->call('__getKeys', $object);
    
    return $self->toArray($rval);
}

sub toHash {
    my ($self, $object) = @_;

    my @keys = $self->getKeys($object);
    my %hash;

    foreach my $key (@keys) {
        $hash{$key} = $object->$key;
    }

    return %hash;
}

sub setMemory {
    my ($self, $memory) = @_;

    $self->call('__setmemory', $memory);

    return;
}

sub getMemory {
    my ($self) = @_;

    return $self->call('__getmemory');
}

sub initMemory {
    my ($self) = @_;

    $self->call('initMemory');
    return;
}

1;
