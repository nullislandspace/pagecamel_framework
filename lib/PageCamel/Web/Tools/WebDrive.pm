package PageCamel::Web::Tools::WebDrive;
#---AUTOPRAGMASTART---
use v5.40;
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

use base qw(PageCamel::Web::BaseWebSocket);
use PageCamel::Helpers::DateStrings;
use MIME::Base64;
use JSON::XS;
use Digest::SHA1 qw(sha1_hex);
use File::Basename;
use Crypt::Digest::SHA256 qw[sha256_hex];
use PageCamel::Helpers::Padding qw[doFPad];
use PageCamel::Helpers::URI qw(encode_uri);

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{chunksize} //= 1_000_000;
    $self->{uncpath} //= '';
    $self->{template} = 'tools/webdrive';
    $self->{extrasettings} = [];
    $self->{defaultDisconnectTimeout} = 25;

    return $self;
}

sub wsregister($self) {
    $self->register_webpath($self->{downloadwebpath}, 'get_download', "GET");
    $self->register_webpath($self->{hashingworkerpath}, 'get_hashingworker', "GET");
    $self->register_webpath($self->{uploadworkerpath}, 'get_uploadworker', "GET");
    $self->register_webpath($self->{ajaxwebpath}, 'get_files', "POST");
    return;
}

sub wsmaskget($self, $ua, $settings, $webdata) {
    my $fullajaxpath;
    if($self->{usessl}) {
        $fullajaxpath = 'https://';
    } else {
        $fullajaxpath = 'http://';
    }
    $fullajaxpath .= $ua->{headers}->{Host} . $self->{ajaxwebpath};

    $webdata->{ajaxwebpath} = $fullajaxpath;
    $webdata->{HashingWorker} = $self->{hashingworkerpath};
    $webdata->{UploadWorker} = $self->{uploadworkerpath};
    $webdata->{UNCPath} = $self->{uncpath};
    $ua->{UseUnsafeDataTablesInline} = 1;

    return 200;
}

sub wshandlerstart($self, $ua, $settings) {
    $self->{upfiles} = [];
    $self->{waitingforchunk} = 0;
    return;
}

sub wshandlemessage($self, $realmsg) {
    my $settings = $self->{sessiondata}->{settings};

    if($realmsg->{type} eq 'UPLOADREQUEST') {
        my @remotehashes = split/\,/, $realmsg->{hashes};
        my %updata = (
            remotename => $realmsg->{filename},
            remotesize => $realmsg->{filesize},
            localname => $self->{basepath} . '/' . $self->clean_fname($realmsg->{filename}),
            remotehashes => \@remotehashes,
        );


        my $lsize = 0;
        if(-f $updata{localname}) {
            $lsize = -s $updata{localname};
        }

        if($lsize > $updata{remotesize}) {
            # Need to truncate local file
            truncate $updata{localname}, $updata{remotesize};
            $lsize = $updata{remotesize};
        }


        my @localhashes;

        # Generate local chunk checksums
        if($lsize > 0) {
            open(my $ifh, '<', $updata{localname}) or croak("$ERRNO");
            binmode($ifh);
            my $chunknum = 0;

            while(1) {
                my $chunk;
                sysread($ifh, $chunk, $settings->{chunk_size});
                last if(!defined($chunk) || !length($chunk));

                push @localhashes, sha256_hex($chunk);
                $chunknum++;
            }
            close $ifh;
        }

        my @missingchunks;
        my $missingchunk = 0;
        foreach my $chunk (@remotehashes) {
            if(!defined($localhashes[$missingchunk]) || $chunk ne $localhashes[$missingchunk]) {
                push @missingchunks, $missingchunk;
            }
            $missingchunk++;
        }
        $updata{missingchunks} = \@missingchunks;
        if(scalar @missingchunks) {
            push @{$self->{upfiles}}, \%updata;
        } else {
            # No missing chunks
            my %donemsg = (
                type => 'FILEDONE',
                filename => $updata{remotename},
            );
            if(!$self->wsprint(\%donemsg)) {
                return 0;
            }
        }

    } elsif($realmsg->{type} eq 'DELETEFILE') {
        my $found = 0;
        opendir(my $dfh, $self->{basepath}) or return 1;
        while((my $fname = readdir $dfh)) {
            my $fullname = $self->{basepath} . '/' . $fname;
            if($fname eq $realmsg->{filename} && -f $fullname) {
                $found = 1;
                last;
            }
        }
        closedir $dfh;
        if($found) {
            unlink $self->{basepath} . '/' . $realmsg->{filename};
        }

        my %donemsg = (
            type => 'RELOADTABLE',
        );
        if(!$self->wsprint(\%donemsg)) {
            return 0;
        }
    }

    return 1;
}

sub wshandlebinarymessage($self, $message) {
    my $settings = $self->{sessiondata}->{settings};

    # Parse binary SETCHUNK: [chunk_num:4][fname_len:2][fname:N][data:...]
    my $chunk_num = unpack('N', substr($message, 0, 4));
    my $fname_len = unpack('n', substr($message, 4, 2));
    my $filename = substr($message, 6, $fname_len);
    my $chunkdata = substr($message, 6 + $fname_len);

    # Validate against expected upload
    if($filename ne $self->{upfiles}->[0]->{remotename} ||
       $chunk_num ne $self->{upfiles}->[0]->{missingchunks}->[0]) {
        return 0;
    }

    # Write chunk to disk (raw binary, no base64 decode needed)
    my $seekto = $chunk_num * $settings->{chunk_size};
    my $filemode = '+<';
    if(!-f $self->{upfiles}->[0]->{localname}) {
        $filemode = '>';
        if($seekto != 0) {
            croak("Internal error: New file must begin with first chunk!");
        }
    }
    open(my $ofh, $filemode, $self->{upfiles}->[0]->{localname}) or croak("$ERRNO");
    binmode $ofh;
    seek($ofh, $seekto, 0);
    print $ofh $chunkdata;
    close $ofh;

    shift @{$self->{upfiles}->[0]->{missingchunks}};
    if(!scalar @{$self->{upfiles}->[0]->{missingchunks}}) {
        my %donemsg = (
            type => 'FILEDONE',
            filename => $self->{upfiles}->[0]->{remotename},
        );
        if(!$self->wsprint(\%donemsg)) {
            return 0;
        }
        shift @{$self->{upfiles}};
    }

    $self->{waitingforchunk} = 0;
    return 1;
}

sub wscyclic($self, $ua) {
    if(!$self->{waitingforchunk} && scalar @{$self->{upfiles}}) {
        my $remain = scalar @{$self->{upfiles}->[0]->{missingchunks}};
        my $remote = scalar @{$self->{upfiles}->[0]->{remotehashes}};
        my $percentage = 100 - int($remain / $remote * 100);
        my %msg = (
            type => 'UPLOADCHUNK',
            filename => $self->{upfiles}->[0]->{remotename},
            chunk => $self->{upfiles}->[0]->{missingchunks}->[0],
            percentage => $percentage,
        );
        if(!$self->wsprint(\%msg)) {
            return 0;
        }
        $self->{waitingforchunk} = 1;
    }
    return 1;
}

sub wscleanup($self) {
    delete $self->{upfiles};
    delete $self->{waitingforchunk};
    return;
}

sub get_hashingworker($self, $ua) {
    return $self->get_workerscript($ua, 'tools/webdrive_hashingworker.js');
}

sub get_uploadworker($self, $ua) {
    return $self->get_workerscript($ua, 'tools/webdrive_uploadworker.js');
}


sub get_workerscript($self, $ua, $templatename) {
    my $th = $self->{server}->{modules}->{templates};
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    my %settings;
    foreach my $setname (qw[websocket_encryption client_connect_timeout client_disconnect_timeout chunk_size]) {
        my ($ok, $setref) = $sysh->get($self->{modname}, $setname);
        if(!$ok || !defined($setref->{settingvalue})) {
            croak("Failed to read setting $setname");
        }
        $settings{$setname} = $setref->{settingvalue};
    }

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        Settings        =>  \%settings,
        ExtraScripts     => ['/static/sha256.js'],
    );

    my $template = $th->get($templatename, 0, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "application/javascript",
            data    => $template);
}

sub get_files($self, $ua) {
    my @files;
    my $total = 0;
    my $count = 0;
    if(!-d $self->{basepath}) {
        print STDERR "FAAAAIIIIL!\n";
        return (status => 500);
    }

    my (@searchpositives, @searchnegatives);
    my $searchstring = $ua->{postparams}->{'search[value]'} || '';
    $searchstring = $self->clean_searchstring($searchstring);
    if($searchstring ne '') {
        my @parts = split/\s+/, $searchstring;
        foreach my $part (@parts) {
            if(substr($part, 0, 1) ne '!') {
                push @searchpositives, $part;
            } else {
                substr($part, 0, 1, '');
                if($part ne '') {
                    push @searchnegatives, $part;
                }
            }
        }
    }

    my @rawfnames;
    opendir(my $dfh, $self->{basepath});
    while((my $fname = readdir $dfh)) {
        my $fullname = $self->{basepath} . '/' . $fname;
        next unless(-f $fullname);
        $total++;
        push @rawfnames, $fname;
    }
    closedir $dfh;

    foreach my $fname (sort { "\L$a" cmp "\L$b" } @rawfnames) {
        my $fullname = $self->{basepath} . '/' . $fname;

        # Filter results
        my $ismatch = 1;
        if(@searchpositives) {
            foreach my $sp (@searchpositives) {
                if($fname !~ /$sp/i) {
                    $ismatch = 0;
                }
            }
        }
        if(@searchnegatives) {
            foreach my $sn (@searchnegatives) {
                if($fname =~ /$sn/i) {
                    $ismatch = 0;
                }
            }
        }
        next unless($ismatch);

        my @stats = stat $fullname;
        my $xsize = $stats[7];
        my $lastmod;
        {
            my ($sec,$min, $hour, $mday,$mon, $year, $wday,$yday, $isdst) = localtime $stats[9];
            $year += 1900;
            $mon += 1;

            $mon = doFPad($mon, 2);
            $mday = doFPad($mday, 2);
            $hour = doFPad($hour, 2);
            $min = doFPad($min, 2);
            $sec = doFPad($sec, 2);
            $lastmod = "$year-$mon-$mday $hour:$min:$sec";
        }

        my %fdata = (
            'DT_RowId' => 'row_' . $total,
            file => '<a href="' . $self->{downloadwebpath} . '/' . $fname . '">' . $fname . '</a>',
            xsize => $xsize,
            date => $lastmod,
            'delete' => '<a href="#" onclick="return deleteFile(\'' . $fname . '\');">Delete</a>',
        );
        push @files, \%fdata;
        $count++;
    }

    # Sorting
    my @sortnames = qw(file xsize date);
    my $sortcol = $sortnames[$ua->{postparams}->{'order[0][column]'}];
    my $sortdir = $ua->{postparams}->{'order[0][dir]'};

    if($sortcol ne 'xsize') {
        if($sortdir eq 'asc') {
            my @sortedfiles = sort { lc($a->{$sortcol}) cmp lc($b->{$sortcol}) } @files;
            @files = @sortedfiles;
        } else {
            my @sortedfiles = sort { lc($b->{$sortcol}) cmp lc($a->{$sortcol}) } @files;
            @files = @sortedfiles;
        }
    } else {
        if($sortdir eq 'asc') {
            my @sortedfiles = sort { (0 + $a->{$sortcol}) <=> (0 + $b->{$sortcol}) } @files;
            @files = @sortedfiles;
        } else {
            my @sortedfiles = sort { (0 + $b->{$sortcol}) <=> (0 + $a->{$sortcol}) } @files;
            @files = @sortedfiles;
        }
    }


    # Cut list to requested size
    my $limit = $ua->{postparams}->{'length'} || 10;
    my $first = $ua->{postparams}->{'start'} || 0;
    my $final = $first + $limit;

    if($final >= scalar @files) {
        $final = (scalar @files) - 1;
        if($first > $final) {
            $first = -1;
        }
    }
    if($first >= scalar @files) {
        $first = -1;
    }

    if($first == -1) {
        @files = ();
    } else {
        @files = @files[$first..$final];
    }

    my %webdata = (
        aaData  => \@files,
        iTotalDisplayRecords => $count,
        iTotalRecords => $total,
        sEcho => '__0__',
    );

    my $data = encode_json(\%webdata);

    return (
        status => 200,
        type => 'application/json',
        data => $data,
    );
}

sub clean_fname($self, $filename) {
    my $safe_filename_characters = "a-zA-Z0-9_.-";
    $filename =~ s/\\/\//go;
    my ( $name, $path, $extension ) = fileparse ( $filename, '\..*' );
    $filename = $name . $extension;
    $filename =~ tr/ /_/;
    $filename =~ s/[^$safe_filename_characters]//g;
    return $filename;
}

sub clean_searchstring($self, $searchstring) {
    $searchstring =~ s/^\s+//;
    $searchstring =~ s/\s+$//;
    $searchstring =~ s/\s+/\ /g;
    my $safe_search_characters = 'a-zA-Z0-9_.\-\ !';
    $searchstring =~ s/[^$safe_search_characters]//g;
    return $searchstring;
}







sub get_download($self, $ua) {
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
    my $remove = $self->{downloadwebpath};
    $filename =~ s/^$remove//;
    $filename =~ s/^\///g;

    my $found = 0;
    opendir(my $dfh, $self->{basepath}) or return(status => 500);
    while((my $fname = readdir $dfh)) {
        if($fname eq $filename) {
            $found = 1;
            last;
        }
    }
    closedir($dfh);

    if(!$found) {
        return(status => 404);
    }
    my $fullname = $self->{basepath} . '/' . $filename;

    if(!-f $fullname) {
        return(status => 404);
    }

    my $data;
    my $contentlength = 0;

    my $extfile;
    $extfile->{realfilename} = $fullname;
    $extfile->{filename} = $filename;


    $extfile->{datalength} = -s $extfile->{realfilename};
    $extfile->{lastmodified} = getLastModifiedWebdate($extfile->{realfilename});
    $extfile->{etag} = sha1_hex($extfile->{realfilename} . $extfile->{datalength} . $extfile->{lastmodified});


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

    { # Handle "304 Not Modified" fast turnaround

        my $lastetag = $ua->{headers}->{'If-None-Match'} || '';
        if(defined($extfile->{etag}) &&
                $lastetag ne "" &&
                $extfile->{etag} eq $lastetag) {
            # Resource matches the cached one in the browser, so just notify
            # we didn't modify it
            return(status   => 304);
        }

        my $lastmodified = $ua->{headers}->{'If-Modified-Since'} || '';

        if($lastmodified ne "") {
            # Compare the dates
            my $lmclient = parseWebdate($lastmodified);
            my $lmserver = parseWebdate($extfile->{'lastmodified'});
            if($lmclient >= $lmserver) {
                return(status   => 304);
            }
        }
    }

    if($uamethod eq 'GET') {
        my $lastmodified = $extfile->{lastmodified};
        my $tmp = parseWebdate($lastmodified);
        $lastmodified = getWebdate($tmp);

        my %dataGenerator = (
            module      => $self,
            funcname    => "file_get",
        );

        $self->{file}->{fname} = $extfile->{realfilename};
        $self->{file}->{offs} = 0;
        $self->{file}->{dataend} = $extfile->{datalength};

        return (status  =>  200,
            type    => $mtype,
            "content_length" => $extfile->{datalength},
            expires         => $self->{expires},
            cache_control   =>  $self->{cache_control},
            disable_compression => 1,
            "Accept-Ranges"   => 'bytes',
            etag    => $extfile->{etag},
            "Last-Modified" => $lastmodified,
            dataGenerator   => \%dataGenerator,
        );
    } elsif($uamethod eq 'GET-RANGE') {
        $contentlength = $extfile->{datalength};

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

        my $lastmodified = $extfile->{lastmodified};
        my $tmp = parseWebdate($lastmodified);
        $lastmodified = getWebdate($tmp);

        my %dataGenerator = (
            module      => $self,
            funcname    => "file_get",
        );

        $self->{file}->{fname} = $extfile->{realfilename};
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
            etag    => $extfile->{etag},
            "Last-Modified" => $lastmodified,
            dataGenerator   => \%dataGenerator,
        );
    } elsif($uamethod eq 'GET-MULTIRANGE') {
        $contentlength = $extfile->{datalength};

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

        my $lastmodified = $extfile->{lastmodified};
        my $tmp = parseWebdate($lastmodified);
        $lastmodified = getWebdate($tmp);

         my %dataGenerator = (
            module      => $self,
            funcname    => "file_get_multipart",
        );

        $self->{file}->{fname} = $extfile->{realfilename};
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
            etag    => $extfile->{etag},
            "Last-Modified" => $lastmodified,
            dataGenerator   => \%dataGenerator,
        );
    } elsif($uamethod eq 'HEAD') {
        my $lastmodified = $extfile->{lastmodified};
        my $tmp = parseWebdate($lastmodified);
        $lastmodified = getWebdate($tmp);

        return (status  =>  200,
            type    => $mtype,
            expires         => $self->{expires},
            cache_control   =>  $self->{cache_control},
            disable_compression => 1,
            "Accept-Ranges"   => 'bytes',
            content_length  => $extfile->{datalength},
            etag    => $extfile->{etag},
            "Last-Modified" => $lastmodified,
        );

    }


   return(status => 500); # Something went wrong
}

sub file_get_multipart_contentlength($self, $ua) {
    my $len = 0;
    foreach my $okrange (@{$self->{file}->{ranges}}) {

        $len += length($self->{file}->{separator}) + 2; # Separator + 2x newlines
        $len += 14 + length($self->{file}->{mtype}) + 2; # content type + newline
        $len += 15 + length($okrange->{rangeheader}) + 4; # range header + 2x newlines
        $len += $okrange->{len};
        $len += 2; #newline
    }

    $len += length($self->{file}->{separator}) + 2; # Separator + newline

    return $len;
}

sub file_get_multipart($self, $ua) {
    if(!defined($self->{file}->{fh})) {
        $self->{file}->{fh} = File::Binary->new($self->{file}->{fname});
        $self->{file}->{len} = 0;
    }

    my $data;
    if(!defined($self->{file}->{offs})) {
        # Need next part

        if(!(scalar @{$self->{file}->{ranges}})) {
            # No more parts? We're done here
            $data = $self->{file}->{separator} . "\r\n";
            $self->{file}->{len} += length($data);
            $self->{file}->{fh}->close();
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

    $self->{file}->{fh}->seek($self->{file}->{offs});
    my $curlength = $self->{file}->{dataend} - $self->{file}->{offs};

    if($curlength > $self->{chunksize}) {
        # Limit chunk to maximum chunk size
        $needMoreLoops = 1;
        $curlength = $self->{chunksize};
    }

    $data .= $self->{file}->{fh}->get_bytes($curlength);
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

sub file_get($self, $ua) {
    my $ok = 0;

    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
        if(!defined($self->{file}->{fh})) {
            $self->{file}->{fh} = File::Binary->new($self->{file}->{fname});
        }
        $ok = 1;
    };

    if(!$ok) {
        return (
            data => '',
            done => 1,
        )
    };

    my $needMoreLoops = 0;

    $self->{file}->{fh}->seek($self->{file}->{offs});
    my $curlength = $self->{file}->{dataend} - $self->{file}->{offs};

    if($curlength > $self->{chunksize}) {
        # Limit chunk to maximum chunk size
        $needMoreLoops = 1;
        $curlength = $self->{chunksize};
    }

    my $data = $self->{file}->{fh}->get_bytes($curlength);
    $self->{file}->{offs} += $curlength;

    if(!$needMoreLoops) {
        $self->{file}->{fh}->close();
        delete $self->{file};
    }

    return (
        data => $data,
        done => !$needMoreLoops,
    );
}


1;
__END__

=head1 NAME

PageCamel::Web::Tools::WebDrive - WebSocket-based file upload/download manager

=head1 SYNOPSIS

  use PageCamel::Web::Tools::WebDrive;

=head1 DESCRIPTION

WebDrive provides a browser-based file management interface with WebSocket-based
chunked upload support. It extends BaseWebSocket to get standard WebSocket handling
(PING/PONG, IO::Select, pagecamel subprotocol).

=head2 new

Constructor. Sets defaults for chunksize, uncpath, template, and disconnect timeout.

=head2 wsregister

Registers extra webpaths for download, hashing worker, upload worker, and AJAX file listing.

=head2 wsmaskget

Populates webdata with AJAX path, worker paths, and UNC path for the template.

=head2 wshandlerstart

Initializes upload file queue and chunk waiting state for a new WebSocket session.

=head2 wshandlemessage

Handles UPLOADREQUEST and DELETEFILE JSON messages from the browser.

=head2 wshandlebinarymessage

Handles binary SETCHUNK messages from the browser. Parses the binary frame format
(chunk number, filename, raw chunk data) and writes the chunk to disk.

=head2 wscyclic

Sends UPLOADCHUNK requests to the browser when chunks are pending.

=head2 wscleanup

Cleans up upload state after WebSocket disconnection.

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
