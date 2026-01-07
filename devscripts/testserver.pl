#!/usr/bin/env perl
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

package TestServer;

use base qw(Net::Server::Single);


sub process_request($self) {
    my @headers;
    my $lcount = 0;
    my %request;
    while(1) {
        my $header = <STDIN>;
        $lcount++;
        $header =~ s/[\r\n]+$//;
        last if($header eq "");
        if($lcount == 1) {
            $self->parse_request_line(\%request, $header);
        } else {
            $self->parse_header_line(\%request, $header);
        }
        push @headers, $header;
    }
    
    my $postdata;
    if(defined($request{headers}->{'Content-Length'})) {
        my $datalen = read STDIN, $postdata, $request{headers}->{'Content-Length'};
        if($datalen != $request{headers}->{'Content-Length'}) {
            print STDERR "Failed to read postdata\n";
        } elsif($datalen != length($postdata)) {
            print STDERR "INTERNAL ERROR: read() reported wrong number of bytes read\n";
        }
        $request{postdata} = $postdata;
    }
    
    if(defined($postdata) && $request{headers}->{'Content-Type'} eq 'application/x-www-form-urlencoded') {
        $self->parse_postdata(\%request, $postdata);
    }
    
    print "HTTP/1.1 200 OK\r\n";
    my $content;
    my $ctype = 'text/html';
    my $extraheader;
    if($request{url} eq '/formrequest') {
        $content = getForm(\%request);
        $extraheader = "Set-Cookie: session=42b'--\r\n";
    } elsif($request{url} eq '/formsubmit') {
        $content = parseSubmit(\%request);
    } else {
        $content = join("\r\n", @headers);
        $ctype = 'text/plain';
    }
    print "Content-Type: $ctype\r\n";
    print "Content-Length: " . length($content) . "\r\n";
    if(defined($extraheader)) {
        print $extraheader;
    }
    print "\r\n";
    print $content;
}

sub parse_request_line($self, $request, $header) {
    if($header =~ /^([A-Z]+)\ (\S+)\ HTTP\/(1\.\d)$/) {
        ($request->{method}, $request->{url}, $request->{httpversion}) = ($1, $2, $3); 
    } else {
        print STDERR "Illegal request line!\n";
    }
    
    if($request->{url} =~ /([^\?]+)\?(.+)/) {
        my $params;
        ($request->{url}, $params) = ($1, $2);
        my %uriparams;
        my @parts = split/\&/, $params;
        foreach my $part (@parts) {
            my ($rawkey, $rawval) = split/\=/, $part;
            my $dkey = uri_decode($rawkey);
            my $dval = uri_decode($rawval);
            if(!defined($uriparams{$dkey})) {
                $uriparams{$dkey} = $dval;
            } else {
                if(ref($uriparams{$dkey}) ne 'ARRAY') {
                    my $tempval = $uriparams{$dkey};
                    my @temp = ($tempval, $dval);
                    $uriparams{$dkey} = \@temp;
                } else {
                    push @{$uriparams{$dkey}}, $dval;
                }
            }
        }
        $request->{uriparams} = \%uriparams;
        print STDERR "bla\n";
        
    }
    
    return;
}

sub parse_postdata($self, $request, $postdata) {
    my %postparams;
    my @parts = split/\&/, $postdata;
    foreach my $part (@parts) {
        my ($rawkey, $rawval) = split/\=/, $part;
        my $dkey = uri_decode($rawkey);
        my $dval = uri_decode($rawval);
        if(!defined($postparams{$dkey})) {
            $postparams{$dkey} = $dval;
        } else {
            if(ref($postparams{$dkey}) ne 'ARRAY') {
                my $tempval = $postparams{$dkey};
                my @temp = ($tempval, $dval);
                $postparams{$dkey} = \@temp;
            } else {
                push @{$postparams{$dkey}}, $dval;
            }
        }
    }
    $request->{postparams} = \%postparams;
    print STDERR "bla\n";
    
    return;
}

sub parse_header_line($self, $request, $header) {
    if($header =~ /^(\S+)\:\ (.+)$/) {
        my ($name, $value) = ($1, $2);
        if(!defined($request->{headers})) {
            $request->{headers} = {};
        }
        $request->{headers}->{$name} = $value;
    } else {
        print STDERR "Illegal header line!\n";
    }
    
    return;
}

sub getForm($self, $request) {
    my $form = <<'END_FORM';
<html>
    <head>
        <title>Test Form BLAAAAA</title>
    </head>
    <body>
        <h1>Testform</h1>
        <p>
            <form action="/formsubmit" method="POST">
                Name: <input type="text" name="username" value="BLA"><br/>
                Active: <input type="checkbox" name="isactive"><br/>
                <input type="submit">
            </form>
        </p>
    </body>
</html>
END_FORM
    return $form;
}

sub parseSubmit($self, $request) {
    my $form = <<'END_FORM';
<html>
    <head>
        <title>Test Form BLAAAAA</title>
    </head>
    <body>
        <h1>Testform</h1>
        <a href="/formrequest">Try again</a>
    </body>
</html>
END_FORM
    return $form;
}


TestServer->run(port => 8080);
