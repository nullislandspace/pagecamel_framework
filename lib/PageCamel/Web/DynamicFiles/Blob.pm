package PageCamel::Web::DynamicFiles::Blob;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.5;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DataBlobs;
use Number::Bytes::Human qw(format_bytes);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::URI qw(encode_uri);

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    croak("<public> not defined in module $self->{modname}") unless defined($self->{public});
    croak("<pagetitle> not defined in module $self->{modname}") unless defined($self->{download}->{pagetitle});

    if(!defined($self->{directorylisting})) {
        $self->{directorylisting} = 1;
    }

    if(!defined($self->{chunksize})) {
        $self->{chunksize} = 50_000; # 50 kB
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
    $self->register_webpath($self->{download}->{webpath}, "get_download", 'GET', 'POST');
    
    if(defined($self->{wastedspace})) {
        $self->register_webpath($self->{wastedspace}->{webpath}, "get_wastedspace", 'GET');
    }
    
    return;
}

sub crossregister {
    my ($self) = @_;

    if($self->{public}) {
        $self->register_public_url($self->{download}->{webpath});
    }

    return;
}

sub get_download { ## no critic (Subroutines::ProhibitExcessComplexity)
    my ($self, $ua, $isErrorMode) = @_;

    if(!defined($isErrorMode)) {
        $isErrorMode = 0;
    }

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $uamethod = $ua->{method};
    my @headkeys = sort keys %{$ua->{headers}};
    my %rheaders;
    foreach my $headkey (@headkeys) {
        $rheaders{$headkey} = $ua->{headers}->{$headkey};
    }

    my $range;
    if(defined($rheaders{HTTP_RANGE}) && $uamethod eq 'GET') {
        $range = $rheaders{HTTP_RANGE};
        $range =~ s/.*\=//;
        if($range !~ /\,/) {
            $uamethod = 'GET-RANGE';
        } else {
            $uamethod = 'GET-MULTIRANGE';
        }

        print STDERR "** $uamethod : $range\n";
    } else {
        print STDERR "** $uamethod\n";
    }


    my $filename = $ua->{url};
    my $remove = $self->{download}->{webpath};
    $filename =~ s/^$remove//;
    if($isErrorMode) {
        $filename = $self->{errorfile};
        if($filename !~ /^\//) {
            $filename = '/' . $filename;
        }
    }

    my $blobid;
    my $selsth = $dbh->prepare_cached("SELECT *
                               FROM dynamicfiles
                               WHERE module = ? AND filename = ?")
            or croak($dbh->errstr);
    $selsth->execute($self->{dbmodule}, $filename);
    while((my $file = $selsth->fetchrow_hashref)) {
        $blobid = $file->{file_datablob_id};
    }
    $selsth->finish;
    $dbh->rollback;
    if(!defined($blobid)) {
        if(!$isErrorMode) {
            if($self->{directorylisting}) {
                return $self->getDirectory($ua, $filename);
            } elsif(defined($self->{errorfile})) {
                return $self->get_download($ua, 1);
            } else {
                return(status => 404);
            }
        } else {
            return(status => 404);
        }
    }

    my $data;
    my $contentlength = 0;

    my $mtype = "application/octet-stream";
    if($filename =~ /(.*)\.([a-zA-Z0-9]+)$/) {
        my ($kname, $type) = ($1, $2);
        if($type =~ /htm/i) {
            $mtype = "text/html";
        } elsif($type =~ /txt/i) {
            $mtype = "text/plain";
        } elsif($type =~ /css/i) {
            $mtype = "text/css";
        } elsif($type =~ /js/i) {
            $mtype = "application/javascript";
        } elsif($type =~ /ico/i) {
            $mtype = "image/vnd.microsoft.icon";
        } elsif($type =~ /bmp/i) {
            $mtype = "image/bmp";
        } elsif($type =~ /png/i) {
            $mtype = "image/png";
        } elsif($type =~ /jpg/i) {
            $mtype = "image/jpeg";
        }
    }

    my ($blobetag, $blobdatalength, $bloblastupdate);
    { # Handle "304 Not Modified" fast turnaround
        # Temporarly open datablob in readonly mode
        my $blob = PageCamel::Helpers::DataBlobs->new($dbh, $blobid, 1);
        $blobetag = $blob->getETag();
        $blobdatalength = $blob->getLength();
        $bloblastupdate = $blob->getLastUpdate();
        $blob->blobClose();
        $dbh->rollback;

        my $lastetag = $ua->{headers}->{'If-None-Match'} || '';
        if(defined($blobetag) &&
                $lastetag ne "" &&
                $blobetag eq $lastetag) {
            # Resource matches the cached one in the browser, so just notify
            # we didn't modify it
            return(status   => 304);
        }

        my $lastmodified = $ua->{headers}->{'If-Modified-Since'} || '';

        if($lastmodified ne "") {
            # Compare the dates
            my $lmclient = parseWebdate($lastmodified);
            my $lmserver = parseWebdate($bloblastupdate);
            if($lmclient >= $lmserver) {
                return(status   => 304);
            }
        }
    }

    if($uamethod eq 'GET') {
        my $tmp = parseWebdate($bloblastupdate);
        my $lastmodified = getWebdate($tmp);
        my %dataGenerator = (
            module      => $self,
            funcname    => "file_get",
        );

        $self->{file}->{blobid} = $blobid;
        $self->{file}->{offs} = 0;
        $self->{file}->{dataend} = $blobdatalength;

        return (status  =>  200,
            type    => $mtype,
            "content_length" => $blobdatalength,
            expires         => $self->{expires},
            cache_control   =>  $self->{cache_control},
            disable_compression => 1,
            "Accept-Ranges"   => 'bytes',
            etag    => $blobetag,
            "Last-Modified" => $lastmodified,
            dataGenerator   => \%dataGenerator,
        );
    } elsif($uamethod eq 'GET-RANGE') {
        $contentlength = $blobdatalength;

        # Add missing args for shorthand ranges
        if($range =~ /^\-/o) {
            $range = "0$range";
        }
        if($range =~ /\-$/) {
            $range = $range . ($contentlength - 1);
        }

        my ($start, $end) = split/\-/, $range;

        # Validate Range
        if($start < 0 || $end >= $contentlength || $start > $end) {
            return (status  =>  416); # "Requested Range Not Satisfiable"
        }
        my $len = ($end - $start) + 1;

        my $lastmodified = $bloblastupdate;
        my $tmp = parseWebdate($lastmodified);
        $lastmodified = getWebdate($tmp);

        my %dataGenerator = (
            module      => $self,
            funcname    => "file_get",
        );

        $self->{file}->{blobid} = $blobid;
        $self->{file}->{offs} = $start;
        $self->{file}->{dataend} = $end + 1;

        my $rangeheader = "bytes " . $start . "-" . $end . "/" . $contentlength;
        return (status  =>  206,
            type    => $mtype,
            "content_length" => $len,
            expires         => $self->{expires},
            cache_control   =>  $self->{cache_control},
            disable_compression => 1,
            "Accept-Ranges"   => 'bytes',
            "Content-Range"   => $rangeheader,
            etag    => $blobetag,
            "Last-Modified" => $lastmodified,
            dataGenerator   => \%dataGenerator,
        );
    } elsif($uamethod eq 'GET-MULTIRANGE') {
        $contentlength = $blobdatalength;

        my $sep = "---****---" . int(rand(1_000_000)) . "---ThisSeparatesTheContent---" . int(rand(1_000_000)) . "---***---";
        my $fulldata = "";

        my @okranges;

        $range =~ s/\ //g;
        my @rparts = split/\,/,$range;

        my $rangeid = 0;
        foreach my $rpart (@rparts) {

            # Add missing args for shorthand ranges
            if($rpart =~ /^\-/o) {
                $rpart = "0$rpart";
            }
            if($rpart =~ /\-$/) {
                $rpart = $rpart . ($contentlength - 1);
            }

            my ($start, $end) = split/\-/, $rpart;

            # Validate Range
            if($start < 0 || $end >= $contentlength || $start > $end) {
                return (status  =>  416); # "Requested Range Not Satisfiable"
            }
            my $len = ($end - $start) + 1;

            # Validate against already accepted ranges, merge ranges
            my $isok = 1;
            foreach my $okrange (@okranges) {
                if($start >= $okrange->{start} && $start <= $okrange->{end}) {
                    if($end > $okrange->{end}) {
                        $okrange->{end} = $end;
                    }
                    $isok = 0;
                }
                if($end >= $okrange->{start} && $end <= $okrange->{end}) {
                    if($start < $okrange->{start}) {
                        $okrange->{start} = $start;
                    }
                    $isok = 0;
                }

                # Here comes the tricky bit. If the later range overlaps the existing range in a way that it has to
                # be extended, let's do that.
                if($start <= $okrange->{start} && $end >= $okrange->{end}) {
                    $okrange->{start} = $start;
                    $okrange->{end} = $end;
                    $isok = 0;
                }
            }
            if($isok) {
                my %tmprange = (
                    start   => $start,
                    end     => $end,
                    rangeid => $rangeid,
                );
                $rangeid++;
                push @okranges, \%tmprange;
            }

        }

        # Do some sanity-checking. If we STILL have some overlapping ranges, there is a trickery going on!
        my $hasTrickery = 0;
        foreach my $okrange (@okranges) {
            foreach my $chkrange (@okranges) {
                next if($okrange->{rangeid} == $chkrange->{rangeid});
                if($chkrange->{start} >= $okrange->{start} && $chkrange->{start} <= $okrange->{end}) {
                    $hasTrickery = 1;
                }
                if($chkrange->{end} >= $okrange->{start} && $chkrange->{end} <= $okrange->{end}) {
                    $hasTrickery = 1;
                }
                if($chkrange->{start} < $okrange->{start} && $chkrange->{end} > $okrange->{end}) {
                    $hasTrickery = 1;
                }
            }
            $okrange->{len} = ($okrange->{end} - $okrange->{start}) + 1;
            $okrange->{rangeheader} = "bytes " . $okrange->{start} . "-" . $okrange->{end} . "/" . $contentlength;
        }
        if($hasTrickery) {
            return (status  =>  403,
                    type    => 'text/plain',
                    data    => 'Your Range request header is needlessly complex. A one-pass merge on my side could not fix all overlapping ranges. ' .
                                'Please fix your HTTP client implementation and try again.'
                            );
        }

        my $lastmodified = $bloblastupdate;
        my $tmp = parseWebdate($lastmodified);
        $lastmodified = getWebdate($tmp);

         my %dataGenerator = (
            module      => $self,
            funcname    => "file_get_multipart",
        );

        $self->{file}->{blobid} = $blobid;
        $self->{file}->{ranges} = \@okranges;
        $self->{file}->{separator} = $sep;
        $self->{file}->{mtype} = $mtype;

        return (status  =>  206,
            type    => $mtype,
            "content_length" => $self->file_get_multipart_contentlength(),
            expires         => $self->{expires},
            cache_control   =>  $self->{cache_control},
            disable_compression => 1,
            "Accept-Ranges"   => 'bytes',
            "Content-Range"   => "multipart/byteranges; boundary=$sep",
            etag    => $blobetag,
            "Last-Modified" => $lastmodified,
            dataGenerator   => \%dataGenerator,
        );
    } elsif($uamethod eq 'HEAD') {
        my $lastmodified = $bloblastupdate;
        my $tmp = parseWebdate($lastmodified);
        $lastmodified = getWebdate($tmp);

        return (status  =>  200,
            type    => $mtype,
            expires         => $self->{expires},
            cache_control   =>  $self->{cache_control},
            disable_compression => 1,
            "Accept-Ranges"   => 'bytes',
            content_length  => $blobdatalength,
            etag    => $blobetag,
            "Last-Modified" => $lastmodified,
        );

    }

   return(status => 500); # Something went wrong
}

sub file_get_multipart_contentlength {
    my ($self, $ua) = @_;

    # Add up all data block sizes and corresponding headers

    my $len = 0;
    foreach my $okrange (@{$self->{file}->{ranges}}) {

        $len += length($self->{file}->{separator}) + 2; # Separator + 2x newlines
        $len += 14 + length($self->{file}->{mtype}) + 2; # content type + newline
        $len += 15 + length($okrange->{rangeheader}) + 4; # range header + 2x newlines
        $len += $okrange->{len}; # size of data
        $len += 2; #newline
    }

    $len += length($self->{file}->{separator}) + 2; # Separator + newline

    return $len;
}

sub file_get_multipart {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    if(!defined($self->{file}->{fh})) {
        $self->{file}->{fh} = PageCamel::Helpers::DataBlobs->new($dbh, $self->{file}->{blobid});
        $self->{file}->{len} = 0;
    }

    my $data;
    if(!defined($self->{file}->{offs})) {
        # Need next part

        if(!(scalar @{$self->{file}->{ranges}})) {
            # No more parts? We're done here
            $data = $self->{file}->{separator} . "\r\n";
            $self->{file}->{len} += length($data);
            $self->{file}->{fh}->blobClose();
            $dbh->rollback;
            #print STDERR "Bytes: ", $self->{file}->{len}, "\n";
            delete $self->{file};

            return (
                data => $data,
                done => 1,
            );
        }

        my $okrange = shift @{$self->{file}->{ranges}};
        $self->{file}->{offs} = $okrange->{start};
        $self->{file}->{dataend} = $okrange->{start} + $okrange->{len};
        $data .= $self->{file}->{separator} . "\r\n";
        $data .= "Content-type: " . $self->{file}->{mtype} . "\r\n";
        $data .= "Content-range: " . $okrange->{rangeheader} . "\r\n\r\n";
    }

    my $needMoreLoops = 0;

    my $curlength = $self->{file}->{dataend} - $self->{file}->{offs};

    if($curlength > $self->{chunksize}) {
        # Limit chunk to maximum chunk size
        $needMoreLoops = 1;
        $curlength = $self->{chunksize};
    }

    my $tmp;
    $self->{file}->{fh}->blobRead(\$tmp, $self->{file}->{offs}, $curlength);
    $data .= $tmp;
    $self->{file}->{offs} += $curlength;

    if(!$needMoreLoops) {
        # We are done with THIS range
        $data .= "\r\n";
        delete $self->{file}->{offs};
    }

    $self->{file}->{len} += length($data);

    return (
        data => $data,
        done => 0,
    );
}

sub file_get {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    if(!defined($self->{file}->{fh})) {
        $self->{file}->{fh} = PageCamel::Helpers::DataBlobs->new($dbh, $self->{file}->{blobid});
    }

    my $needMoreLoops = 0;

    #$self->{file}->{fh}->seek($self->{file}->{offs});
    my $curlength = $self->{file}->{dataend} - $self->{file}->{offs};

    if($curlength > $self->{chunksize}) {
        # Limit chunk to maximum chunk size
        $needMoreLoops = 1;
        $curlength = $self->{chunksize};
    }

    my $data;
    $self->{file}->{fh}->blobRead(\$data, $self->{file}->{offs}, $curlength);
    $self->{file}->{offs} += $curlength;

    if(!$needMoreLoops) {
        $self->{file}->{fh}->blobClose();
        $dbh->rollback;
        delete $self->{file};
    }

    return (
        data => $data,
        done => !$needMoreLoops,
    );
}


sub getDirectory {
    my ($self, $ua, $filename) = @_;

    return (status => 404) unless defined($self->{server}->{modules}->{templates});

    if($ua->{method} eq 'POST' && defined($ua->{postparams}->{mode}) &&
        $ua->{postparams}->{mode} eq 'search' && defined($ua->{postparams}->{filename}) &&
        $ua->{postparams}->{filename} ne '') {
            return $self->getDirectorySearch($ua, $ua->{postparams}->{filename});
    }

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    # Make sure the filename ends with a slash
    if($filename !~ /\/$/) {
        $filename .= '/';
    }

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle => $self->{download}->{pagetitle},
        DirTitle  =>  "Index of $filename",
        showads => $self->{showads},
    );

    my @files;

    if($filename ne '/') {
        my $backname = $filename;
        $backname =~ s/[^\/]+\/$//;

        my %temp = (
            linkname => '&nbsp;..&nbsp;',
            url => encode_uri($self->{download}->{webpath} . $backname),
            type    => 'Directory',
        );
        push @files, \%temp;
    }

    my $count = 0;

    { # Directories
        my $fixedfname = $dbh->quote($filename);
        $fixedfname =~ s/'$/\%'/g;

        my $sth = $dbh->prepare_cached("SELECT DISTINCT basepath FROM dynamicfiles
                                        WHERE module = ? AND basepath LIKE $fixedfname
                                        ORDER BY basepath") or croak($dbh->errstr);
        $sth->execute($self->{dbmodule}) or croak($dbh->errstr);
        my %dirs;
        while((my $line = $sth->fetchrow_hashref)) {
            my $linkname = $line->{basepath};
            $linkname =~ s/^$filename//;
            $linkname =~ s/\/.*//;
            next if($linkname eq '');
            $dirs{$linkname} = 1;
        }
        $sth->finish;

        foreach my $linkname(sort keys %dirs) {
            my %temp = (
                linkname => $linkname,
                url => encode_uri($self->{download}->{webpath} . $filename . $linkname),
                type    => 'Directory',
            );
            push @files, \%temp;
            $count++;
        }
        $sth->finish;
    }

    { # Files
        my $sth = $dbh->prepare_cached("SELECT filename, datalength as size, lastupdate as lastmodified,
                                       date_trunc('second', lastupdate) as lastmodified_simplified FROM dynamicfiles df, datablobs bl
                                        WHERE df.file_datablob_id = bl.datablob_id
                                        AND module = ?
                                        AND basepath = ?
                                        ORDER BY filename") or croak($dbh->errstr);
        $sth->execute($self->{dbmodule}, $filename) or croak($dbh->errstr);
        while((my $line  = $sth->fetchrow_hashref)) {
            my $linkname = $line->{filename};
            $linkname =~ s/.*\///;

            my %temp = (
                linkname => $linkname,
                url => encode_uri($self->{download}->{webpath} . $line->{filename}),
                type    => 'File',
                lastmodified => $line->{lastmodified},
                lastmodified_simplified => $line->{lastmodified_simplified},
                size => $line->{size},
                size_human => format_bytes($line->{size}),
            );

            push @files, \%temp;
            $count++;
        }
        $sth->finish;
    }

    if(!$count && defined($self->{errorfile})) {
        return $self->get_download($ua, 1);
    } elsif(!$count) {
        return(status => 404);
    }

    #return (status=>404) unless $count;

    $webdata{files} = \@files;

    my $templatename;
    my $usemaster;
    if($self->{public}) {
        $templatename = "dynamicfiles/directory_public";
        $usemaster = 0;
        $webdata{HideMenuBar} =  1;
    } else {
        $templatename = "dynamicfiles/directory_private";
        $usemaster = 1;
    }
    
    if(defined($self->{wastedspace})) {
        $webdata{DynamicFilesWastedSpace} = $self->{wastedspace};
    }

    my $template = $self->{server}->{modules}->{templates}->get($templatename, $usemaster, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub getDirectorySearch {
    my ($self, $ua, $filename) = @_;

    return (status => 404) unless defined($self->{server}->{modules}->{templates});


    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle => $self->{download}->{pagetitle},
        DirTitle  =>  "Search for $filename",
        PostLink => $self->{download}->{webpath},
        ShowParent => 1,
        LastSearch => $filename,
        showads => $self->{showads},
    );

    my @files;

    my $count = 0;

    $filename =~ s/\s+/\ /g;
    my @parts = split/\ /,$filename;
    my $searcher = '';
    foreach my $part (@parts) {
        $part = $dbh->quote($part);
        $part =~ s/'$/\%'/;
        $part =~ s/^'/'\%/;
        $searcher .= " AND filename ILIKE $part ";
    }
    if($searcher eq '') {
        $ua->{postdata}->{mode} = 'view';
        return $self->getDirectory($ua, '/');
    }

    { # Files
        my $sth = $dbh->prepare_cached("SELECT filename, basepath, datalength as size, lastupdate as lastmodified,
                                       date_trunc('second', lastupdate) as lastmodified_simplified FROM dynamicfiles df, datablobs bl
                                        WHERE df.file_datablob_id = bl.datablob_id
                                        AND module = ?
                                        $searcher
                                        ORDER BY basefilename") or croak($dbh->errstr);
        $sth->execute($self->{dbmodule}) or croak($dbh->errstr);
        while((my $line  = $sth->fetchrow_hashref)) {
            my $linkname = $line->{filename};
            $linkname =~ s/.*\///;

            my $plname = $line->{basepath};
            $plname =~ s/\/$//;
            $plname =~ s/.*\///;

            my %temp = (
                linkname => $linkname,
                url => encode_uri($self->{download}->{webpath} . $line->{filename}),
                parentlinkname => $plname,
                parenturl => encode_uri($self->{download}->{webpath} . $line->{basepath}),
                type    => 'File',
                lastmodified => $line->{lastmodified},
                lastmodified_simplified => $line->{lastmodified_simplified},
                size => $line->{size},
                size_human => format_bytes($line->{size}),
            );

            push @files, \%temp;
            $count++;
        }
        $sth->finish;
    }

    #return (status=>404) unless $count;

    $webdata{files} = \@files;

    my $templatename;
    my $usemaster;
    if($self->{public}) {
        $templatename = "dynamicfiles/directory_public";
        $usemaster = 0;
        $webdata{HideMenuBar} =  1;
    } else {
        $templatename = "dynamicfiles/directory_private";
        $usemaster = 1;
    }
    
    if(defined($self->{wastedspace})) {
        $webdata{DynamicFilesWastedSpace} = $self->{wastedspace};
    }
    
    my $template = $self->{server}->{modules}->{templates}->get($templatename, $usemaster, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}




1;
__END__

=head1 NAME

PageCamel::Web::DynamicFiles -

=head1 SYNOPSIS

  use PageCamel::Web::DynamicFiles;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 crossregister



=head2 get_download



=head2 file_get_multipart_contentlength



=head2 file_get_multipart



=head2 file_get



=head2 getDirectory



=head2 getDirectorySearch



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
