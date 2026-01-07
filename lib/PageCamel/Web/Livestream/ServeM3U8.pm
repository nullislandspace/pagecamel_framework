package PageCamel::Web::Livestream::ServeM3U8;
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

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::FileSlurp qw[slurpBinFile slurpBinFilePart];
use PageCamel::Helpers::DateStrings;
use Digest::SHA1  qw(sha1_hex);
use File::stat;
use Time::localtime;
use Time::HiRes qw[sleep];

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    if(!defined($self->{dontlog})) {
        $self->{dontlog} = 0;
    }

    return $self;
}

sub reload($self) {
    # Nothing to do

    return;
}

sub register($self) {
    $self->register_webpath($self->{webpath}, "get_download", 'GET');
    
    return;
}

sub crossregister($self) {
    if(defined($self->{public}) && $self->{public} == 1) {
        $self->register_public_url($self->{webpath});
    }

    return;
}

sub get_download($self, $ua) {
    my $filename = $ua->{url};
    my $remove = $self->{webpath};
    $filename =~ s/^$remove//;

    if($filename eq 'index.m3u8') {
        return $self->get_index($ua);
    }


    if($filename !~ /^\d{14}\.ts$/) {
        return (
            status => 404,
        );
    }

    # Grab metadata
    my $realfilename = $self->{basepath} . $filename;
    my $data = slurpBinFile($realfilename);
    my $fstat = stat($realfilename);
    my $lastmodified = ctime($fstat->mtime);
    my $lastmodifiedheader = getWebdate(parseWebdate($lastmodified));
    my $datalength = $fstat->size;
    my $etag = sha1_hex($filename . $datalength . $lastmodified);

    my %dataGenerator = (
        module      => $self,
        funcname    => "file_get",
    );
    
    my %retstatus = (
        status  =>  200,
        type    => 'video/MP2T',
        "content_length" => $datalength,
        expires         => '+10m',
        cache_control   =>  'max-age=600',
        disable_compression => 1,
        etag    => $etag,
        "Last-Modified" => $lastmodifiedheader,
        data => $data,
    );

    if($self->{dontlog}) {
        $retstatus{'__do_not_log_to_accesslog'} = 1;
    }

    return %retstatus;
}

sub get_index($self, $ua) {
    my $data = '';
    my $filecount = 0;
    my $loopcount = 0;
    my $realfilename = $self->{basepath} . 'index.m3u8';
rereadindex:
    open(my $ifh, '<', $realfilename) or return(status => 500);
    while((my $line = <$ifh>)) {
        if($line =~ /XXXPATHXXX/) {
            $filecount++;
            $line =~ s/XXXPATHXXX/$self->{webpath}/g;
            $line =~ s/\/\//\//g;
        }
        $data .= $line;
    }
    close $ifh;
    if($filecount < 5) {
        # Maythe the file is just beeing written, retry unless we exceed 3 loops already
        $loopcount++;
        if($loopcount > 5) {
            return(status => 500);
        }
        $data = '';

        sleep(0.1);
        goto rereadindex;
    }

    my %retstatus = (status  =>  200,
        type    => 'application/x-mpegURL',
        "content_length" => length($data),
        disable_compression => 1,
        data => $data,
    );

    if($self->{dontlog}) {
        $retstatus{'__do_not_log_to_accesslog'} = 1;
    }

    return %retstatus;
}



1;
__END__

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
