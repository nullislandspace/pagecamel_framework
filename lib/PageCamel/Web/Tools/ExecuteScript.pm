package PageCamel::Web::Tools::ExecuteScript;
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



use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::FileSlurp qw(slurpBinFile);

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class
    
    if(!defined($self->{chunksize})) {
        $self->{chunksize} = 50_000; # 50 kB
    }

    return $self;
}

sub register($self) {
    $self->register_webpath($self->{webpath}, "get");
    return;
}

sub crossregister($self) {
    if(defined($self->{public}) && $self->{public}) {
        $self->register_public_url($self->{webpath});
    }

    return;
}


sub get($self, $ua) {
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    if(!-x $self->{script}) {
        $reph->debuglog("Script ", $self->{script}, " is not executable");
        return (status => 500);
    }


    `$self->{script}`;

    if(!defined($self->{result}) || !-f $self->{result}) {
        $reph->debuglog("No result file");
        return (status => 204); # No content
    }

    my $data = slurpBinFile($self->{result});

    return (status => 200,
            type => 'application/octet-stream',
            data => $data,
    );

}
