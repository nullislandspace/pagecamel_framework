package PageCamel::Web::OSMTiles;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp;
our $VERSION = 2.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::FileSlurp qw(slurpBinFile);
use Digest::SHA1  qw(sha1_hex);
use PageCamel::Helpers::DateStrings;




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

    my $tile = $ua->{url};

    my $remove = $self->{webpath};
    $tile =~ s/^$remove//;
    $tile =~ s/\.png$//;
    $tile =~ s/^\///;
    my ($z, $x, $y) = split/\//, $tile;
    return (status  =>  404) if(!defined($z) || !defined($x) || !defined($y));

    $z = int(0 + $z);
    return (status  =>  404) if($z > $self->{maxzoom});

    $x = int(0 + $x);
    $y = int(0 + $y);

    my $filepath = $self->{tiledir} . '/' . $z . '/' . $x . '/' . $y . '.png';

    if(!-f $filepath) {
        my $cmd = $self->{command} . " $z $x $y";
        my @result = `$cmd`;
        return (status => 500) if($result[0] !~ /^OK\ /);

        my $genpath = $result[0];
        chomp $genpath;
        $genpath =~ s/^OK\ //;
        croak("Oops, wrong path!") if($genpath ne $filepath);
        croak("Oops, no file!") unless(-f $filepath);
    }

    my $filelastmodified = getLastModifiedWebdate($filepath);
    my $data = slurpBinFile($filepath);
    my $etag = sha1_hex($data);

    my $lastmodified = $ua->{headers}->{'If-Modified-Since'} || '';
    if($lastmodified ne "") {
        # Compare the dates
        my $lmclient = parseWebdate($lastmodified);
        my $lmserver = parseWebdate($filelastmodified);
        if($lmclient >= $lmserver) {
            return(status   => 304);
        }
    }


    my $lastetag = $ua->{headers}->{'If-None-Match'} || '';

    if($lastetag ne "" && $etag eq $lastetag) {
        # Resource matches the cached one in the browser, so just notify
        # we didn't modify it
        return(status   => 304);
    }



    my %retpage = (status          =>  200,
            type            => 'image/png',
            data            => $data,
            expires         => $self->{expires},
            cache_control   =>  $self->{cache_control},
            "Last-Modified" => $filelastmodified,
            "ETag"          => $etag,
            disable_compression => 1,
            );

    return %retpage;
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

Copyright (C) 2008-2019 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
