package PageCamel::Web::Tools::ShortURL;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 1;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::Strings qw[stripString];
use MIME::Base64;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    if(!defined($self->{logo})) {
        $self->{logo} = '';
    }
    
    if(defined($self->{favicon})) {
        $self->{favicon} = decode_base64($self->{favicon});
        $self->{faviconheader} = '<link rel="shortcut icon" href="/favicon.ico*' . getFileDate() . '">'
    } else {
        $self->{faviconheader} = '';
    }

    return $self;
}

sub register {
    my $self = shift;
    $self->register_webpath($self->{webpath}, "get", 'GET', 'POST');

    # Custom METHOD handling for RFCxxxx
    #$self->register_custom_method("LONG", "custom_LONG");
    #$self->register_custom_method("SHORT", "custom_SHORT");

    return;
}

sub get {
    my ($self, $ua) = @_;

    my $remove = $self->{webpath};
    my $path = $ua->{url};
    
    if($path eq '/favicon.ico' && defined $self->{favicon}) {
        return (status => 200,
                type => 'image/vnd.microsoft.icon',
                data => $self->{favicon},
                expires         => $self->{expires},
                cache_control   =>  $self->{cache_control},
        );
    }
    
    $path =~ s/^$remove//;
    my $client_ip = $ua->{remote_addr} || '0.0.0.0';

    if($path =~ /favicon/i) {
        return (
            status  => 404,
        );
    }

    my $result = '';
    
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $logsth = $dbh->prepare_cached("INSERT INTO shorturl_logging
                                        (requesttype, request, result, client_ip)
                                        VALUES (?,?,?,?)")
            or croak($dbh->errstr);

    my $longurl;
    if($path eq '') {
        # Handle the webform
        if($ua->{method} eq 'POST') {
            # make sure we got a good form input
            $longurl = stripString($ua->{postparams}->{longurl});
            if(!defined($longurl) || $longurl eq '') {
                $ua->{method} = 'GET';
                $result = "Empty URL";
            }
            if(length($longurl) > 2000) {
                $ua->{method} = 'GET';
                $result = "Long URL too long. Sorry.";
            }
            if($longurl !~ /^http(s)?\:\/\//i || $longurl =~ /\s/) {
                # FAIL!
                $ua->{method} = 'GET';
                $result = "URL failed to validate!";
            }
        }
        
        if($ua->{method} eq 'GET') {
            return (
                status  => 200,
                type    => 'text/html',
                data    => $self->getInputForm($result),
            );
        }
        
        # Check if already exists
        my $id;
        my $cachesth = $dbh->prepare_cached("SELECT short_url FROM shorturl
                                            WHERE long_url = ?")
                or croak($dbh->errstr);
            #(requesttype, request, result, client_ip)
        if(!$cachesth->execute($longurl)) {
            $dbh->rollback;
            return (
                status  => 200,
                type    => 'text/html',
                data    => $self->getInputForm("Sorry, something went wrong."),
            );
        }
        ($id) = $cachesth->fetchrow_array;
        $cachesth->finish;
        if(defined($id) && $id ne '') {
            $dbh->commit;
            $result = 'Short URL created: ' . $self->{basehost} . $self->{webpath} . $id;
            if($logsth->execute('RECREATEURL', $longurl, $id, $client_ip)) {
                $dbh->commit;
            } else {
                $dbh->rollback;
            }
            return (
                status  => 200,
                type    => 'text/html',
                data    => $self->getInputForm($result),
            );
        }
        
        # Ok, create a new one
        $id = $self->createID();
        my $insth = $dbh->prepare_cached("INSERT INTO shorturl (short_url, long_url)
                                         VALUES (?, ?)")
                or croak($dbh->errstr);
        $result = 'Short URL created: ' . $self->{basehost} . $self->{webpath} . $id;
        if($insth->execute($id, $longurl)) {
            $dbh->commit;
        } else {
            $dbh->rollback;
            $result = "Sorry, something went wrong.";
        }

        if($logsth->execute('CREATEURL', $longurl, $id, $client_ip)) {
            $dbh->commit;
        } else {
            $dbh->rollback;
        }
        
        return (
            status  => 200,
            type    => 'text/html',
            data    => $self->getInputForm($result),
        );

    }
    
    my $selsth = $dbh->prepare_cached("SELECT long_url FROM shorturl
                                      WHERE short_url = ?")
            or croak($dbh->errstr);
    if(!$selsth->execute($path)) {
        $dbh->rollback;
        return(status => 500);
    }
    ($longurl) = $selsth->fetchrow_array;
    $selsth->finish;
    $dbh->commit;
    if(defined($longurl) && $longurl ne '') {
        if($logsth->execute('RESOLVEURL', $path, $longurl, $client_ip)) {
            $dbh->commit;
        } else {
            croak($dbh->errstr);
            $dbh->rollback;
        }
        return (
            status  => 301,
            location => $longurl,
            type    => 'text/plain',
            data    => 'Redirecting to real URL...',
        );
    }
    if($logsth->execute('RESOLVEURLFAIL', $path, '', $client_ip)) {
        $dbh->commit;
    } else {
        $dbh->rollback;
    }
    return (
        status  => 200,
        type    => 'text/html',
        data    => $self->getInputForm('Unknown short URL.'),
    );
}

sub createID {
    my ($self) = @_;
    
    my @validchars = split//, '01234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_';
    my $shortid = '';
    for(1..6) {
        $shortid .= $validchars[rand @validchars];
    }
    return $shortid;
    
}

sub getInputForm {
    my ($self, $result) = @_;
    
    if(!defined($result)) {
        $result = '';
    }
    
    my $form = '<html><head><title>' . $self->{pagetitle} . '</title>' . $self->{faviconheader} . '</head>' .
                '<body>' . $self->{longpagetitle} . '<br/>' .
                $self->{logo} .
                '<form action="' . $self->{webpath} . '" method="post">' .
                '<input type="text" name="longurl" size="80" maxlength="2000">' .
                '<input type="submit" value="Shorten me!">' .
                '</form><br/>' .
                '<h2>' . $result . '</h2><br/>' .
                'If you encounter problems, please send a bug report to <b>urlshortener-bugs (at) cavac.at' .
                '</body></html>';
    return $form;
}

sub custom_LONG {
    my ($self, $ua) = @_;


    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $urls = '';


    my $done = 0;
    my $id = $ua->{postparams}->{'original_path_info'} || '';
    $id =~ s/.*\///;
    $id = 0 + $id;
    if($id == 0) {
        # No URL, nothing to do
        $done = 1;
    }

    if(!$done) {
        # First, check if link already exists
        my $selsth = $dbh->prepare_cached("SELECT long_url FROM shorturl
                                    WHERE short_id = ?")
                or croak($dbh->errstr);
        $selsth->execute($id) or croak($dbh->errstr);
        while((my $url = $selsth->fetchrow_array)) {
            $urls .= "$url\n";
            $done = 1;
        }
        $selsth->finish;
        $dbh->rollback;
    }

    if($urls eq '') {
        return (status => 404);
    }

    return (status      => 200,
            type    => "text/plain",
            data    => $urls);
}


sub custom_SHORT {
    my ($self, $ua) = @_;


    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $urls = '';

    my $done = 0;
    my $url = $ua->{postparams}->{'original_path_info'} || '';
    $url =~ s/^(\W+)//;
    $url =~ s/(\W+)$//;
    if($url eq '') {
        # No URL, nothing to do
        $done = 1;
    }

    my $basehost = $ua->url(-base=>1);

    if(!$done) {
        # First, check if link already exists
        my $selsth = $dbh->prepare_cached("SELECT short_id FROM shorturl
                                    WHERE long_url = ?")
                or croak($dbh->errstr);
        $selsth->execute($url) or croak($dbh->errstr);
        while((my $id = $selsth->fetchrow_array)) {
            my $shorturl = $basehost . $self->{unshort}->{webpath} . $id;
            $urls .= "$shorturl\n";
            $done = 1;
        }
        $selsth->finish;
        $dbh->rollback;
    }

    if(!$done) {
        my $insth = $dbh->prepare_cached("INSERT INTO shorturl (long_url)
                                          VALUES (?)
                                          RETURNING short_id")
                or croak($dbh->errstr);
        $insth->execute($url) or croak($dbh->errstr);
        my $id = $insth->fetch()->[0];
        $insth->finish;
        my $shorturl = $basehost . $self->{unshort}->{webpath} . $id;
        $urls .= "$shorturl\n";
        $done = 1;
        $dbh->commit;
    }

    if($urls eq '') {
        return (status => 404);
    }

    return (status  =>  200,
            type    => "text/plain",
            data    => $urls);
}


1;
__END__

=head1 NAME

PageCamel::Web::Debug::ShortURL -

=head1 SYNOPSIS

  use PageCamel::Web::Debug::ShortURL;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 get_short



=head2 get_long



=head2 unshort



=head2 custom_LONG



=head2 custom_SHORT



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
