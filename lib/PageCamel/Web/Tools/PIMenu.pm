package PageCamel::Web::Tools::PIMenu;
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
use PageCamel::Helpers::FileSlurp qw(slurpBinFile writeBinFile slurpBinFilehandle);
use File::Basename;
use PageCamel::Helpers::DataBlobs;
use JSON::XS;
use PageCamel::Helpers::DateStrings;

use Readonly;
Readonly my $TESTRANGE => 1_000_000;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class
    
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

    if(defined($self->{public}->{webpath})) {
        $self->register_webpath($self->{public}->{webpath}, "get_public");
    }
    if(defined($self->{download}->{webpath})) {
        $self->register_webpath($self->{download}->{webpath}, "get_download", 'GET');
    }
    if(defined($self->{manage}->{webpath})) {
        $self->register_webpath($self->{manage}->{webpath}, "get_manage");
    }
    if(defined($self->{checkfname}->{webpath})) {
        $self->register_webpath($self->{checkfname}->{webpath}, "get_fname", 'POST');
    }

    if(defined($self->{sitemap}) && $self->{sitemap}) {
        $self->register_sitemap('sitemap');
    }

    $self->register_defaultwebdata('get_defaultwebdata');
    return;
}

sub crossregister {
    my ($self) = @_;
    
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    if(defined($self->{public}->{webpath})) {
        $self->register_public_url($self->{public}->{webpath});
    }
    if(defined($self->{download}->{webpath})) {
        $self->register_public_url($self->{download}->{webpath});
    }
    

    $sysh->createText(modulename => $self->{modname},
                    settingname => 'enable_pi_menu',
                    settingvalue => 1,
                    description => 'Enable the magic PI menu',
                    processinghints => [
                        'type=switch',
                                        ])
        or croak("Failed to create setting enable_pi_menu!");

    return;
}

sub clean_fname {
    my ($self, $filename) = @_;

    my $safe_filename_characters = "a-zA-Z0-9_.-";
    $filename =~ s/\\/\//go;
    my ( $name, $path, $extension ) = fileparse ( $filename, '\..*' );
    $filename = $name . $extension;
    $filename =~ tr/ /_/;
    $filename =~ s/[^$safe_filename_characters]//g;
    return $filename;
}

sub get_manage {
    my ($self, $ua) = @_;

    my $webpath = $ua->{url};

    my $mode = $ua->{postparams}->{'mode'} || 'view';
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    if($mode eq "delete") {
        my $delsth = $dbh->prepare_cached("DELETE FROM pimenu WHERE filename = ?")
                or croak($dbh->errstr);
        my @delfiles = @{$ua->{postparams}->{'delfile'}};
        foreach my $delfile (@delfiles) {
            next if($delfile eq '');
            $delsth->execute($delfile) or $dbh->errstr;
        }
        $dbh->commit;
    } elsif($mode eq "upload") {
        # Make filename safe(r)

        my $realfname = $ua->{postparams}->{"upfile"} || '';
        my $filename = $ua->{postparams}->{"upfname"} || '';
        my $description = $ua->{postparams}->{"description"};
        $filename = $self->clean_fname($filename);

        if($filename ne '' && $realfname ne '' && defined($ua->{files}->{$realfname}->{data})) {
            # First delete the existing file (if there is one)
            my $delsth = $dbh->prepare_cached("DELETE FROM pimenu WHERE filename = ?")
                    or croak($dbh->errstr);
            $delsth->execute($filename) or croak($dbh->errstr);

            my $blob = PageCamel::Helpers::DataBlobs->new($dbh);
            $blob->blobOpen();
            my $data = $ua->{files}->{$realfname}->{data};
            $blob->blobWrite(\$data);
            my $filesize = $blob->getLength();
            my $blobid = $blob->blobID();
            $blob->blobClose();

            my $insth = $dbh->prepare("INSERT INTO pimenu (filename, filesize_bytes, description, file_datablob_id)
                                      VALUES (?,?,?,?)")
                    or croak($dbh->errstr);
            $insth->execute($filename, $filesize, $description, $blobid)
                    or croak($dbh->errstr);
            $dbh->commit;

        }
    }

    my @files;
    my $selsth = $dbh->prepare_cached("SELECT * FROM pimenu ORDER BY filename")
            or croak($dbh->errstr);
    $selsth->execute or croak($dbh->errstr);
    while((my $file = $selsth->fetchrow_hashref)) {
        push @files, $file;
    }


    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{manage}->{pagetitle},
        webpath         =>  $self->{manage}->{webpath},
        downwebpath     =>  $self->{download}->{webpath},
        checkfname      =>  $self->{checkfname}->{webpath},
        AvailFiles  =>  \@files,
    );

    my $template = $self->{server}->{modules}->{templates}->get("tools/pimenu", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub get_public {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};


    my @files;
    my $selsth = $dbh->prepare_cached("SELECT * FROM pimenu ORDER BY filename")
            or croak($dbh->errstr);
    $selsth->execute or croak($dbh->errstr);
    while((my $file = $selsth->fetchrow_hashref)) {
        push @files, $file;
    }


    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{public}->{pagetitle},
        webpath         =>  $self->{public}->{webpath},
        downwebpath     =>  $self->{download}->{webpath},
        AvailFiles  =>  \@files,
    );

    my $template = $self->{server}->{modules}->{templates}->get("tools/pimenu_public", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

# ------------------------------------

sub get_download {
    my ($self, $ua) = @_;

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
    if($remove !~ /\/$/) {
        $remove .= '/';
    }
    $filename =~ s/^$remove//;

    my $blobid;
    my $selsth = $dbh->prepare_cached("SELECT *
                               FROM pimenu
                               WHERE filename = ?")
            or croak($dbh->errstr);
    $selsth->execute($filename);
    while((my $file = $selsth->fetchrow_hashref)) {
        $blobid = $file->{file_datablob_id};
    }
    $selsth->finish;
    $dbh->rollback;
    if(!defined($blobid)) {
            return(status => 404);
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
        } elsif($type =~ /exe/i) {
            $mtype = "application/vnd.microsoft.portable-executable";
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



# -------------------------------------



sub get_fname {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $filename = $ua->{postparams}->{'fname'} || '';
    $filename = $self->clean_fname($filename);

    my %data = (
        fname   => $filename,
        status  => 'OK',
        statustext => 'OK',
        description => '',
    );

    # Check for existing filename
    my $selsth = $dbh->prepare_cached("SELECT *
                                      FROM pimenu
                                      WHERE filename = ?
                                      LIMIT 1")
            or croak($dbh->errstr);
    $selsth->execute($filename) or croak($dbh->errstr);
    my $existcount = 0;
    while((my $line = $selsth->fetchrow_hashref)) {
        $existcount++;
        $data{description} = $line->{description};
    }

    if($existcount) {
        $data{status} = 'WARNING';
        $data{statustext} = "File exists, will overwrite!";
    }

    my $jsondata = encode_json \%data;

    return (status  =>  200,
            type    => "text/plain",
            data    => $jsondata);
}


sub get_defaultwebdata {
    my ($self, $webdata) = @_;

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    
    $webdata->{PIMenuPublicUrl} = $self->{public}->{webpath};
    
    { # Check the enable_pi_menu flag
        my ($ok, $data) = $sysh->get($self->{modname}, 'enable_pi_menu');
        if($ok && $data->{settingvalue}) {
            $webdata->{EnablePIMenu} = 1;
        } else {
            $webdata->{EnablePIMenu} = 0;
        }
    }

    return;
}

sub sitemap {
    my ($self, $sitemap) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    push @{$sitemap}, $self->{public}->{webpath};

    my $selsth = $dbh->prepare_cached("SELECT filename FROM pimenu")
            or croak($dbh->errstr);
    $selsth->execute or croak($dbh->errstr);
    while((my $file = $selsth->fetchrow_hashref)) {
        push @{$sitemap}, $self->{download}->{webpath} . '/' .  $file->{filename};
    }
    $selsth->finish;
    $dbh->rollback;

    return;
}

1;
__END__

=head1 NAME

PageCamel::Web::Tools::PIMenu -

=head1 SYNOPSIS

  use PageCamel::Web::Tools::PIMenu;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 crossregister



=head2 clean_fname



=head2 get_manage



=head2 get_public



=head2 get_download



=head2 get_fname



=head2 get_defaultwebdata



=head2 sitemap



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
