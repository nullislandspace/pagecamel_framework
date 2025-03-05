#/usr/bin/env perl

use v5.40;
use strict;
use warnings;
our $VERSION = 4.6;

package Reporting;

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

use Data::Dumper;
use PageCamel::Helpers::AsyncUA;
use Time::HiRes qw(sleep);
use Carp;

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
