package PageCamel::Web::PGAdmin4Proxy;
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

use base qw(PageCamel::Web::BaseModule);
use IO::Socket::IP;
use PageCamel::Helpers::URI qw[encode_uri_path encode_uri_part];

my @ignorepgadmin4headers = qw[Date Server Title X-Meta-Robots];
#my @ignoreclientheaders = qw[Connection Cookie DNT Host Referer Upgrade-Insecure-Requests Accept-Encoding];
my @ignoreclientheaders = qw[Host Upgrade-Insecure-Requests Accept-Encoding];

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub register($self) {
    $self->register_webpath($self->{webpath}, "get", 'GET', 'POST');
    $self->register_postfilter("postfilter");
    return;
}

sub crossregister($self) {
    if(defined($self->{auth_realm})) {
        $self->register_basic_auth($self->{webpath}, $self->{auth_realm});
    }
    return;
}

sub postfilter($self, $ua, $header, $result) {
    my $clientpath = $ua->{url};
    my $mypath = $self->{webpath};

    if(defined($self->{cookie})) {
        if(!defined($header->{-cookie})) {
            $header->{-cookie} = [];
        }
        push @{$header->{-cookie}}, $self->{cookie};
        $self->extend_header($result, "Vary", "Cookie");
        delete $self->{cookie}; # Don't leak cookie next time, if for some reason prefilter is never called (for example on path redirection prefiltering)
    }

    #if($clientpath =~ /^$mypath/ && $ua->{headers}->{'User-Agent'} eq 'mercurial/proto-1.0') {
    #    # Assume client wants keep alive set (mostly for older mercurial versions)
    #    # This isn't very nice, since it results in some "REQUEST LINE TIMEOUT" errors but can't be helped. Should still speed up
    #    # processing a bit
    #    print STDERR "Forcing keep-alive for mercurial/proto-1.0\n";
    #    $ua->{keepalive} = 1;
    #}

    return;

}

sub get($self, $ua) {
    my $pgadmin4path = $ua->{url};

    my $remove = $self->{webpath};
    $pgadmin4path =~ s/^$remove//;
    $pgadmin4path =~ s/\@//g;
    $pgadmin4path =~ s/\://g;
    #$pgadmin4path = $self->{pgadmin4} . $pgadmin4path;
    if($pgadmin4path !~ /^\//) {
        $pgadmin4path = '/' . $pgadmin4path;
    }

    $pgadmin4path = encode_uri_path($pgadmin4path);
    my @uriparamkey = keys %{$ua->{uriparams}};
    if(@uriparamkey) {
        my @parts;
        foreach my $key (@uriparamkey) {
            push @parts, $key . '=' . encode_uri_part($ua->{uriparams}->{$key});
        }
        $pgadmin4path .= '?' . join('&', @parts);
    }


    my $socket = IO::Socket::IP->new(
        PeerHost => $self->{pgadmin4}->{host},
        PeerPort => $self->{pgadmin4}->{port},
        Proto => 'tcp',
    );
    return(status => 500) unless($socket);
    #binmode $socket;

    if($ua->{method} eq 'POST') {
        $socket->send("POST $pgadmin4path HTTP/1.1\r\n");
    } else {
        $socket->send("GET $pgadmin4path HTTP/1.1\r\n");
    }
    $socket->send("Host: localhost:82\r\n");

    foreach my $key (keys %{$ua->{headers}}) {
        my $val = $ua->{headers}->{$key};
        next if(contains($key, \@ignoreclientheaders));

        #print STDERR "---------> $key\n";
        if($key eq 'Referer') {
            print STDERR "###################################################################################\n";
            print STDERR "Referer: $val\n";
            print STDERR "###################################################################################\n";
        }

        if($key eq 'Cookie') {
            if(defined($ua->{cookies}->{pga4_session})) {
                $socket->send('Cookie: pga4_session=' . $ua->{cookies}->{pga4_session} . "; PGADMIN_LANGUAGE=en\r\n");
                #$socket->send('Cookie: pga4_session=6910e56d-3cb3-4e14-985f-2782180d3f33!4U5TYoR8NjdV0VOjeXvcDdZxrXs' . "\r\n");
                #print STDERR "###################################################################################\n";
                #print STDERR Dumper($ua->{cookies}), "\n";
                #print STDERR "###################################################################################\n";
            }
            next;
        }
        if($key eq 'Origin') {
            $socket->send("Origin: http://localhost:82\r\n");
        }

        #print STDERR "<<< $key => $val\n";
        $socket->send("$key: $val\r\n");
    }
    if($pgadmin4path =~ /^\/login/ && $ua->{method} eq 'GET') {
        $socket->send("Connection: keep-alive\r\n");
    }

    #if($pgadmin4path eq '/authenticate/login' && $ua->{method} eq 'POST') {
    #    $socket->send('Referer: http://localhost:82/login?next=%2Fbrowser%2F' . "\r\n");
    #}
    $socket->send("\r\n");

    if($ua->{method} eq 'POST') {
        print STDERR "******************************************************************\r\n";
        print STDERR "POSTDATA: ", $ua->{postdata}, "\n";
        print STDERR "******************************************************************\r\n";
        $socket->send($ua->{postdata});
    }
    my %retpage;
    my $statusline = $self->readsocketline($socket, 30);
    my @statusparts = split/\ /, $statusline, 3;
    $retpage{status} = $statusparts[1];
    $retpage{statustext} = $statusparts[2];

    while(1) {
        my $headerline = $self->readsocketline($socket, 10);
        last if($headerline eq '');
        if($pgadmin4path =~ /^\/login/ && $ua->{method} eq 'GET') {
            #print STDERR "~~~~~~~~~~      $headerline\n";
        }
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

    #print STDERR "################ REQUESTFORM ######################\n";
    #print STDERR Dumper($content), "\n";

    $socket = IO::Socket::IP->new(
        PeerHost => $self->{pgadmin4}->{host},
        PeerPort => $self->{pgadmin4}->{port},
        Proto => 'tcp',
    );
    return(status => 500) unless($socket);

    if(0 && $pgadmin4path =~ /^\/login/ && $ua->{method} eq 'GET') {
        #name="csrf_token" type="hidden" value="IjdlMzFmMTZmYjhjYjhhNWRjNDMyYTE4M2VlN2RkYTc3OTJmNzI4MTYi.X4AOvQ.Mwg2gb6Wd796FKxPig6hKaKteYU"
        my $token;
        if($content =~ /name\=\"csrf\_token\".*?value\=\"(.*?)\"/) {
            $token = $1;
        }
        my $cookie = $retpage{'Set-Cookie'};
        $cookie =~ s/^.*pga4\_session\=//g;
        $cookie =~ s/\&.*//g;

        my $postcontent = "next=%2Fbrowser%2F&csrf_token=" . $token . "&email=" . $self->{user} . "&password=" . $self->{password} . "&language=en\r\n";

        $socket->send("POST /authenticate/login HTTP/1.1\r\n");
        $socket->send("Host: localhost:82\r\n");
        $socket->send("Connection: keep-alive\r\n");
        $socket->send("Content-Length: " . length($postcontent) . "\r\n");
        $socket->send("Cache-Control: max-age=0\r\n");
        $socket->send("Origin: http://localhost:82\r\n");
        $socket->send("Upgrade-Insecure-Requests: 1\r\n");
        $socket->send("DNT: 1\r\n");
        $socket->send("Content-Type: application/x-www-form-urlencoded\r\n");
        $socket->send("User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/85.0.4183.121 Safari/537.36\r\n");
        $socket->send("Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9\r\n");
        $socket->send("Sec-Fetch-Site: same-origin\r\n");
        $socket->send("Sec-Fetch-Mode: navigate\r\n");
        $socket->send("Sec-Fetch-User: ?1\r\n");
        $socket->send("Sec-Fetch-Dest: document\r\n");
        $socket->send("Referer: http://localhost:82/login?next=%2Fbrowser%2F\r\n");
        #$socket->send("Accept-Encoding: gzip, deflate, br\r\n");
        $socket->send("Accept-Language: en-US,en;q=0.9,de;q=0.8\r\n");
        $socket->send("Cookie: pga4_session=" . $cookie . "; PGADMIN_LANGUAGE=en\r\n");
        $socket->send("\r\n");
        $socket->send($postcontent);


        %retpage = ();
        $statusline = $self->readsocketline($socket, 30);
        @statusparts = split/\ /, $statusline, 3;
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

        #my $content;
        #if(defined($retpage{'Transfer-Encoding'}) && $retpage{'Transfer-Encoding'} =~ /chunked/) {
        #    $content = $self->readChunked($socket);
        #    delete $retpage{'Transfer-Encoding'};
        #} elsif(defined($retpage{'Content-Length'})) {
        #    $content = $self->readPlain($socket, $retpage{'Content-Length'});
        #} else {
        #    print STDERR "DO NOT KNOW HOW MUCH TO READ!!!!!\n";
        #    return(status => 500);
        #}

        print STDERR "################ POSTRETURN ######################\n";
        print STDERR Dumper(\%retpage), "\n";
        print STDERR Dumper($content), "\n";

        return (status => 200, type=>"text/plain", data=>"OK");

    }

    $content =~ s/href\=\"/href="\/developer\/pgadmin4/g;
    $content =~ s/src\=\"/src="\/developer\/pgadmin4/g;
    $content =~ s/action\=\"/action="\/developer\/pgadmin4/g;

    if(defined($retpage{'Set-Cookie'})) {
        $self->{cookie} = $retpage{'Set-Cookie'};
        #print STDERR "+++++++++++++++++++++++++++++++++++++\n";
        #print STDERR $retpage{'Set-Cookie'};
        #print STDERR "+++++++++++++++++++++++++++++++++++++\n";
        $self->{cookie} .= '; path=/; SameSite=strict';
        delete $retpage{'Set-Cookie'};
    }

    if($content =~ /to\ target\ URL\:\ \<a\ href\=\"(.*?)\"/) {
        $retpage{location} = $1;
    }
    if(defined($retpage{Location})) {
        delete $retpage{Location};
    }

    foreach my $key (keys %retpage) {
        if($key ne lc $key) {
            #print STDERR "Lowercasing $key...\n";
            $retpage{lc $key} = $retpage{$key};
            delete $retpage{$key};
        }
    }


    # Fix broken links in RSS feeds
    #if($content =~ /^\<rss\ version\=/ ||
    #        ($retpage{type} =~ /text\/xml/ && $content =~ /\<rss\ version\=/) ||
    #        ($retpage{type} =~ /application\/atom\+xml/)) {
    #    my $baseurl = $self->{baseurl};
    #    $content =~ s/http\:\/\/\:8000/$baseurl/g;
    #}

    # hgweb / hg serve use unsafe inline scripting unfortunately
    #$ua->{UseUnsafeMercurialProxy} = 1;

    $retpage{data} = $content;

    return %retpage;
}

sub readsocketline($self, $socket, $timeout = 30) {
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

sub readChunked($self, $socket) {
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

sub readPlain($self, $socket, $clength) {
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

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
