#/usr/bin/env perl


package Reporting;
#---AUTOPRAGMASTART---
use v5.42;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 5.0;
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

sub new($proto, %config) {
    my $class = ref($proto) || $proto;
    
    my $self = bless \%config, $class;

    return $self;
} 

sub debuglog($self, @data) {
    print join('', @data), "\n";
    return;
}

package main;

BEGIN {
    unshift @INC, "/home/cavac/src/pagecamel_framework/lib";
};

use PageCamel::Helpers::AsyncUA;
use Time::HiRes qw(sleep);

my $reph = Reporting->new();

my $ua = PageCamel::Helpers::AsyncUA->new(host => 'palebluedot.cavac.at', use_ssl => 1, ua => 'PageCamel_AsyncUA/' . $VERSION, reph => $reph);

if(1){
    print "############################## GET ########################\n";
    if(!$ua->get('/guest/sleeptest/asdjkhfashdflkahsdflhasas7d8687asd6f')) {
        croak("Failed to start request");
    }

    while(!$ua->finished()) {
        print "Do something else...\n";
        sleep(0.05);
    }

    my ($status, $headers, $body) = $ua->result();
    print "Return code: $status\n";
    #print Dumper($headers);
    print Dumper($body);
}

if(1){
    print "############################## POST ########################\n";
    if(!$ua->post('/guest/sleeptest/asdjkhfashdflkahsdflhasas7d8687asd6f', 'application/octed-stream', 'Hello World')) {
        #if(!$ua->post('/guest/sleeptest/asdjkhfashdflkahsdflhasas7d8687asd6f', 'application/x-www-form-urlencoded', 'field1=value1&field2=value2')) {
        croak("Failed to start request");
    }

    while(!$ua->finished()) {
        print "Do something else...\n";
        sleep(0.05);
    }

    my ($status, $headers, $body) = $ua->result();
    print "Return code: $status\n";
    #print Dumper($headers);
    print Dumper($body);
}
