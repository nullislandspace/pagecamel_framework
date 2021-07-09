package PageCamel::Web::Mercurial::Proxy;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.7;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
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

    if(!defined($self->{readwrite})) {
        $self->{readwrite} = 0;
    }

    return $self;
}

sub register {
    my $self = shift;

    if($self->{readwrite}) {
        $self->register_webpath($self->{webpath}, "get", 'GET', 'POST');
    } else {
        $self->register_webpath($self->{webpath}, "get", 'GET');
    }
    $self->register_postfilter("postfilter");
    return;
}

sub crossregister {
    my ($self) = @_;

    if(defined($self->{auth_realm})) {
        $self->register_basic_auth($self->{webpath}, $self->{auth_realm});
    }
    return;
}

sub postfilter {
    my ($self, $ua, $header, $result) = @_;

    my $clientpath = $ua->{url};
    my $mypath = $self->{webpath};

    if($clientpath =~ /^$mypath/ && $ua->{headers}->{'User-Agent'} eq 'mercurial/proto-1.0') {
        # Assume client wants keep alive set (mostly for older mercurial versions)
        # This isn't very nice, since it results in some "REQUEST LINE TIMEOUT" errors but can't be helped. Should still speed up
        # processing a bit
        print STDERR "Forcing keep-alive for mercurial/proto-1.0\n";
        $ua->{keepalive} = 1;
    }

    return;

}

sub get {
    my ($self, $ua) = @_;

    if(!$self->{readwrite} && $ua->{method} ne 'GET' && $ua->{method} ne 'HEAD') {
        # Readonly proxy does not accept POST
        # Should be handled by WebBase anyway, this is just to be sure
        return (status => 405); # Method not allowed
    }

    my $mercurialpath = $ua->{url};

    my $remove = $self->{webpath};
    $mercurialpath =~ s/^$remove//;
    $mercurialpath =~ s/\@//g;
    $mercurialpath =~ s/\://g;
    #$mercurialpath = $self->{mercurial} . $mercurialpath;
    if($mercurialpath !~ /^\//) {
        $mercurialpath = '/' . $mercurialpath;
    }

    print STDERR "###########   PATH: $mercurialpath\n";

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

    if(!defined($socket)) {
        print STDERR "###########   Can't open socket to mercurial\n";
        return(status => 500);
    }
    #binmode $socket;

    if($ua->{method} eq 'POST') {
        $socket->send("POST $mercurialpath HTTP/1.1\r\n");
    } else {
        $socket->send("GET $mercurialpath HTTP/1.1\r\n");
    }

    foreach my $key (keys %{$ua->{headers}}) {
        my $val = $ua->{headers}->{$key};
        next if(contains($key, \@ignoreclientheaders));
        #print STDERR "<<< $key => $val\n";
        $socket->send("$key: $val\r\n");
    }
    $socket->send("\r\n");

    if($ua->{method} eq 'POST') {
        $socket->send($ua->{postdata});
    }
    my %retpage;
    my $statusline = $self->readsocketline($socket, 30);
    if(!defined($statusline)) {
        print STDERR "###########   Can't read status line (timeout?)\n";
        return(status => 500);
    }

    my @statusparts = split/\ /, $statusline, 3;
    $retpage{status} = $statusparts[1];
    $retpage{statustext} = $statusparts[2];

    while(1) {
        my $headerline = $self->readsocketline($socket, 10);
        if(!defined($headerline)) {
            print STDERR "###########   Can't read header line (timeout?)\n";
            return(status => 500);
        }
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
        if(!defined($content)) {
            print STDERR "###########   Can't read chunked content (timeout?)\n";
            return(status => 500);
        }
        delete $retpage{'Transfer-Encoding'};
    } elsif(defined($retpage{'Content-Length'})) {
        $content = $self->readPlain($socket, $retpage{'Content-Length'}, 60);
        if(!defined($content)) {
            print STDERR "###########   Can't read plain content (timeout?)\n";
            return(status => 500);
        }
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
        if(time > $failat) {
            return;
        }
        next if(!defined($char) || $char eq '');
        next if($char eq "\r");
        last if($char eq "\n");
        $failat = time + $timeout;
        $line .= $char;
    }

    return $line;
}

sub readChunked {
    my ($self, $socket) = @_;

    my $content = '';
    while(1) {
        my $chunklen = $self->readsocketline($socket, 30);
        if(!defined($chunklen)) {
            return;
        }
        $chunklen = hex($chunklen);
        last unless $chunklen;
        my $partial = $self->readPlain($socket, $chunklen, 60);
        $content .= $partial;
        my $dummycrlf = $self->readsocketline($socket, 10);
    }

    return $content;

}

sub readPlain {
    my ($self, $socket, $clength, $timeout) = @_;

    if(!defined($timeout) || !$timeout) {
        $timeout = 30;
    };

    my $content = '';
    my $reallength = 0;
    my $failat = time + $timeout;
    while($reallength < $clength) {
        if(time > $failat) {
            return;
        }
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
            $failat = time + $timeout;
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

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
