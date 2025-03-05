package PageCamel::Web::Tools::SleepTest;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.6;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---



use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::FileSlurp qw(slurpBinFile);
use JSON::XS;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class
    
    return $self;
}

sub register($self) {

    $self->register_webpath($self->{webpath}, "get", 'GET', 'POST');
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

    if($ua->{method} eq 'POST') {
        return $self->handlePost($ua);
    }

    $reph->debuglog("SleepTest module: GET sleeping for 30 seconds");
    sleep(5);
    $reph->debuglog("SleepTest module: Wakeup");

    my %rawdata = (
        hello => 'world',
        hallo => 'welt',
    );

    my $json = encode_json \%rawdata;

    return (status => 200,
            type => 'application/json',
            data => $json,
    );

}

sub handlePost($self, $ua) {
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    print STDERR Dumper($ua);

    $reph->debuglog("SleepTest module: POST sleeping for 30 seconds");
    sleep(5);
    $reph->debuglog("SleepTest module: Wakeup");

    my $data = join('', reverse split//, $ua->{postdata});

    return (status => 200,
            type => 'application/octed-stream',
            data => $data,
    );
}

