package PageCamel::Web::Livestream::ServeM3U8Archive;
#---AUTOPRAGMASTART---
use 5.032;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
use feature 'signatures';
no warnings qw(experimental::signatures);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::FileSlurp qw[slurpBinFile slurpBinFilePart];
use PageCamel::Helpers::DateStrings;
use Digest::SHA1  qw(sha1_hex);
use File::stat;
use Time::localtime;
use Time::HiRes qw[sleep];

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    if(!defined($self->{dontlog})) {
        $self->{dontlog} = 0;
    }

    if(!defined($self->{show_unreleased})) {
        $self->{show_unreleased} = 0;
    }

    return $self;
}

sub reload {
    my ($self) = shift;
    # Nothing to do

    return;
}

sub register {
    my $self = shift;
    $self->register_webpath($self->{webpath}, "get_download", 'GET');
    
    return;
}

sub crossregister {
    my ($self) = @_;

    if(defined($self->{public}) && $self->{public} == 1) {
        $self->register_public_url($self->{webpath});
    }

    return;
}

sub get_download {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $webpath = $ua->{url};
    my @parts = split/\//, $webpath;
    my $filename = pop @parts;
    my $streamid = pop @parts;

    if(!defined($filename) || !defined($streamid)) {
        return (status => 404);
    }

    my $selsth = $dbh->prepare_cached("SELECT *, CASE WHEN publish_time < now() THEN true ELSE false END AS publish_date_ok
                                        FROM livestreams WHERE livestream_id = ?")
        or croak($dbh->errstr);

    if(!$selsth->execute($streamid)) {
        $dbh->rollback;
        return(status => 500);
    }
    my $line = $selsth->fetchrow_hashref();
    $selsth->finish;
    $dbh->commit;

    if(!defined($line) || !defined($line->{livestream_id})) {
        return (status => 404);
    }

    if(!$self->{show_unreleased} && (!$line->{is_published} || !$line->{publish_date_ok})) {
        return (status => 404);
    }

    if($filename eq $self->{m3u8file}) {
        return $self->get_index($ua, $streamid);
    }


    if($filename !~ /^\d{14}\.ts$/ && $filename !~ /^takeout\d+\.ts$/) {
        return (
            status => 404,
        );
    }

    # Grab metadata
    my $realfilename = $self->{basepath} . $streamid . '/' . $filename;
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

sub get_index {
    my ($self, $ua, $streamid) = @_;

    my $data = '';
    my $filecount = 0;
    my $loopcount = 0;
    my $realfilename = $self->{basepath} . $streamid . '/' . $self->{m3u8file};
    my $realwebpath = $self->{webpath} . $streamid . '/';

rereadindex:
    open(my $ifh, '<', $realfilename) or return(status => 500);
    while((my $line = <$ifh>)) {
        if($line =~ /XXXPATHXXX/) {
            $filecount++;
            $line =~ s/XXXPATHXXX/$realwebpath/g;
            $line =~ s/\/\//\//g;
        }
        $data .= $line;
    }
    close $ifh;
    #if($filecount < 5) {
    #    # Maythe the file is just beeing written, retry unless we exceed 5 loops already
    #    $loopcount++;
    #    if($loopcount > 5) {
    #        return(status => 500);
    #    }
    #    $data = '';
    #
    #    sleep(0.3);
    #    goto rereadindex;
    #}

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
