package PageCamel::Web::Mercurial::ROProxy;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use IO::Socket::IP;
use PageCamel::Helpers::URI qw[encode_uri_path encode_uri_part];

my @ignoremercurialheaders = qw[Date Server Title X-Meta-Robots];
my @ignoreclientheaders = qw[Connection Cookie DNT Host Referer Upgrade-Insecure-Requests];

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub register {
    my $self = shift;

    $self->register_webpath($self->{webpath}, "get", 'GET');
    return;
}

sub crossregister {
    my ($self) = @_;

    $self->register_public_url($self->{webpath});
    return;
}

sub get {
    my ($self, $ua) = @_;

    my $mercurialpath = $ua->{url};

    my $remove = $self->{webpath};
    $mercurialpath =~ s/^$remove//;
    $mercurialpath =~ s/\@//g;
    $mercurialpath =~ s/\://g;
    #$mercurialpath = $self->{mercurial} . $mercurialpath;
    if($mercurialpath !~ /^\//) {
        $mercurialpath = '/' . $mercurialpath;
    }

    $mercurialpath = encode_uri_path($mercurialpath);
    my @uriparamkey = keys %{$ua->{uriparams}};
    if(@uriparamkey) {
        my @parts;
        foreach my $key (@uriparamkey) {
            push @parts, $key . '=' . encode_uri_part($ua->{uriparams}->{$key});
        }
        $mercurialpath .= '?' . join('&', @parts);
    }

    my $socket = IO::Socket::IP->new(
        PeerHost => $self->{mercurial}->{host},
        PeerPort => $self->{mercurial}->{port},
        Proto => 'tcp',
    );
    return(status => 500) unless($socket);
    #binmode $socket;

    print STDERR "++++++++++++ GET $mercurialpath HTTP/1.1\n";
    print STDERR "???????????? ", $ua->{'original_path_info'}, "\n";
    $socket->send("GET $mercurialpath HTTP/1.1\r\n");
    
    foreach my $key (keys %{$ua->{headers}}) {
        my $val = $ua->{headers}->{$key};
        next if(contains($key, \@ignoreclientheaders));
        #print STDERR "<<< $key => $val\n";
        $socket->send("$key: $val\r\n");
    }
    $socket->send("\r\n");
    my %retpage;
    my $statusline = $self->readsocketline($socket, 30);
    my @statusparts = split/\ /, $statusline, 3;
    $retpage{status} = $statusparts[1];
    $retpage{statustext} = $statusparts[2];

    while(1) {
        my $headerline = $self->readsocketline($socket, 10);
        last if($headerline eq '');
        my ($hname, $hvalue) = split/\:/, $headerline, 3;
        if($hname eq 'Content-Type') {
            $retpage{type} = $hvalue;
        } else {
            $retpage{$hname} = $hvalue;
        }
    }

    my $content;
    if(defined($retpage{'Transfer-Encoding'}) && $retpage{'Transfer-Encoding'} =~ /chunked/) {
        $content = $self->readChunked($socket);
        delete $retpage{'Transfer-Encoding'};
    } elsif(defined($retpage{'Content-Length'})) {
        $content = $self->readPlain($socket, $retpage{'Content-Length'});
    } else {
        print STDERR "DO NOT KNOW HOW MUCH TO READ!!!!!\n";
        return(status => 500);
    }

    # Fix broken links in RSS feeds
    if($content =~ /^\<rss\ version\=/ ||
            ($retpage{type} =~ /text\/xml/ && $content =~ /\<rss\ version\=/) ||
            ($retpage{type} =~ /application\/atom\+xml/)) {
        my $baseurl = $self->{baseurl};
        $content =~ s/http\:\/\/\:8000/$baseurl/g;
    }

    # hgweb / hg serve use unsafe inline scripting unfortunately
    $ua->{UseUnsafeMercurialProxy} = 1;

    $retpage{data} = $content;

    return %retpage;
}

sub readsocketline {
    my ($self, $socket, $timeout) = @_;

    if(!defined($timeout) || !$timeout) {
        $timeout = 30;
    };

    my $failat = time + $timeout;
    
    my $line = '';
    while(1) {
        my $char = '';
        $socket->recv($char, 1);
        last if(time > $failat);
        next if(!defined($char) || $char eq '');
        next if($char eq "\r");
        last if($char eq "\n");
        $line .= $char;
    }

    return $line;
}

sub readChunked {
    my ($self, $socket) = @_;

    my $content = '';
    while(1) {
        my $chunklen = $self->readsocketline($socket, 30);
        $chunklen = hex($chunklen);
        last unless $chunklen;
        my $partial = $self->readPlain($socket, $chunklen);
        $content .= $partial;
        my $dummycrlf = $self->readsocketline($socket, 10);
    }

    return $content;

}

sub readPlain {
    my ($self, $socket, $clength) = @_;

    my $content = '';
    my $reallength = 0;
    while($reallength < $clength) {
        my $partial;
        my $readlen = 1000;
        my $remainlen = $clength - $reallength;
        if($readlen > $remainlen) {
            $readlen = $remainlen;
        }
        $socket->recv($partial, $readlen);
        if(defined($partial) && $partial ne '') {
            $reallength += length($partial);
            $content .= $partial;
        }
    }

    return $content;
}


1;
__END__

=head1 NAME

PageCamel::Web::OSMTiles -

=head1 SYNOPSIS

  use PageCamel::Web::OSMTiles;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 crossregister



=head2 get



=head1 IMPORTANT NOTE

This module is part of the PageCamel framework. Currently, only limited support
and documentation exists outside my DarkPAN repositories. This source is
currently only provided for your reference and usage in other projects (just
copy&paste what you need, see license terms below).

To see PageCamel in action and for news about the project,
visit my blog at L<https://cavac.at>.

=head1 AUTHOR

Rene Schickbauer, E<lt>pagecamel@cavac.atE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2016 by Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
