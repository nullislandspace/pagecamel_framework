package PageCamel::Web::Tools::WebDrive;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.8;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;
use MIME::Base64;
use PageCamel::Helpers::WSockFrame;
use JSON::XS;
use Time::HiRes qw[sleep alarm time];
use PageCamel::Helpers::WebPrint;
use File::Basename;
use Crypt::Digest::SHA256 qw[sha256_hex];
use PageCamel::Helpers::Padding qw[doFPad];
use PageCamel::Helpers::URI qw(encode_uri);
use Digest::SHA1  qw(sha1 sha1_hex);

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class
    
    if(!defined($self->{chunksize})) {
        $self->{chunksize} = 1_000_000; # 1MB default chunksize
    }

    if(!defined($self->{uncpath}) || $self->{uncpath} eq '') {
        $self->{uncpath} = '';
    }

    return $self;
}

sub register {
    my $self = shift;

    $self->register_webpath($self->{webpath}, 'get', "GET");
    $self->register_webpath($self->{downloadwebpath}, 'get_download', "GET");
    $self->register_webpath($self->{wspath}, 'socketstart', "GET", "CONNECT");
    $self->register_protocolupgrade($self->{wspath}, 'sockethandler', "websocket");
    
    $self->register_webpath($self->{hashingworkerpath}, 'get_hashingworker', "GET");
    $self->register_webpath($self->{uploadworkerpath}, 'get_uploadworker', "GET");
    $self->register_webpath($self->{ajaxwebpath}, 'get_files', "POST");

    return;
}

sub reload {
    my ($self) = @_;

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};


    $sysh->createNumber(modulename => $self->{modname},
                    settingname => 'client_connect_timeout',
                    settingvalue => 10,
                    description => 'Client connect timeout (seconds)',
                    value_min => 5.0,
                    value_max => 120.0,
                    processinghints => [
                        'decimal=0',
                    ],
                    )
        or croak("Failed to create setting client_connect_timeout!");

    $sysh->createNumber(modulename => $self->{modname},
                    settingname => 'client_disconnect_timeout',
                    settingvalue => 25,
                    description => 'Client disconnect timeout (seconds)',
                    value_min => 5.0,
                    value_max => 120.0,
                    processinghints => [
                        'decimal=0',
                    ],
                    )
        or croak("Failed to create setting client_disconnect_timeout!");

   $sysh->createText(modulename => $self->{modname},
                    settingname => 'websocket_encryption',
                    settingvalue => 'auto',
                    description => 'Allow https/ssl encryption of sockets',
                    processinghints => [
                        'type=tristate',
                        'on=Always',
                        'off=Disable',
                        'auto=Automatic'
                                        ])
        or croak("Failed to create setting websocket_encryption!");

    $sysh->createNumber(modulename => $self->{modname},
                    settingname => 'chunk_size',
                    settingvalue => 1 * 1024 * 1024, # Default 1 MB per chunk
                    description => 'Chunk size (bytes)',
                    value_min => 100.0,
                    value_max => 5 * 1024 * 1024, # max 5 MB per chunk
                    processinghints => [
                        'decimal=0',
                    ],
                    )
        or croak("Failed to create setting chunk_size!");

    return;
}

sub get {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
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

    my $wsurl;
    if($settings{websocket_encryption} eq 'on') {
        $wsurl = 'wss://';
    } elsif($settings{websocket_encryption} eq 'off') {
        $wsurl = 'ws://';
    } else {
        # Decide on server ssl settings
        if($self->{usessl}) {
            $wsurl = 'wss://';
        } else {
            $wsurl = 'ws://';
        }
    }
    $wsurl .= $ua->{headers}->{Host} . $self->{wspath};
    
    my $fullajaxpath;
    if($self->{usessl}) {
        $fullajaxpath = 'https://';
    } else {
        $fullajaxpath = 'http://';
    }
    $fullajaxpath .= $ua->{headers}->{Host} . $self->{ajaxwebpath};
    
    my @headextrascripts = (
    #    '/static/jsSHA-2.1.0/sha.js',
    );

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{pagetitle},
        webpath         =>  $self->{webpath},
        ajaxwebpath     =>  $fullajaxpath,
        HashingWorker   =>  $self->{hashingworkerpath},
        UploadWorker   =>  $self->{uploadworkerpath},
        Settings        =>  \%settings,
        WSURL           =>  $wsurl,
        PingTimeout     => int($settings{client_disconnect_timeout} * 1000 / 2),
        HeadExtraScripts => \@headextrascripts,
        UNCPath         => $self->{uncpath},
        showads => $self->{showads},
    );


    $dbh->rollback;
    
    $ua->{UseUnsafeDataTablesInline} = 1;

    my $template = $th->get("tools/webdrive", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub get_hashingworker {
    my ($self, $ua) = @_;
    
    return $self->get_workerscript($ua, 'tools/webdrive_hashingworker.js');
}

sub get_uploadworker {
    my ($self, $ua) = @_;
    
    return $self->get_workerscript($ua, 'tools/webdrive_uploadworker.js');
}


sub get_workerscript {
    my ($self, $ua, $templatename) = @_;

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
    
sub socketstart {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    my $upgrade = $ua->{headers}->{"Upgrade"};
    my $seckey = $ua->{headers}->{"Sec-WebSocket-Key"};
    my $protocol = $ua->{headers}->{"Sec-WebSocket-Protocol"};
    my $version = $ua->{headers}->{"Sec-WebSocket-Version"};

    if(!defined($upgrade) || !defined($seckey) || !defined($version)) {
        return (status => 400); # BAAAD Request! Sit! Stay!
    }


    my $webpath = $ua->{url};
    my $remove = $self->{wspath};
    $webpath =~ s/$remove//;
    $webpath =~ s/^\///;

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
    );
    my $session = {};
    $session->{sockid} = $webpath;
    $session->{user} = $webdata{userData}->{user};
    $self->{sessiondata} = $session;

    $seckey .= "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"; # RFC6455 GUID for Websockets

    $seckey = encode_base64(sha1($seckey), '');

    my $proto = 'base64';

    my %result = (status      =>  101,
                  Upgrade     => "websocket",
                  Connection  => "Upgrade",
                  "Sec-WebSocket-Accept"  => $seckey,
                  "Sec-WebSocket-Protocol" => $proto,
                 );

    return %result;
}

sub sockethandler {
    my ($self, $ua) = @_;

    my $session = $self->{sessiondata};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    my %settings;
    foreach my $setname (qw[websocket_encryption client_connect_timeout client_disconnect_timeout chunk_size]) {
        my ($ok, $setref) = $sysh->get($self->{modname}, $setname);
        if(!$ok || !defined($setref->{settingvalue})) {
            croak("Failed to read setting $setname");
        }
        $settings{$setname} = $setref->{settingvalue};
    }
    
    my @upfiles;
    my $waitingforchunk = 0;

    my $timeout = time + $settings{client_disconnect_timeout};

    my $frame = PageCamel::Helpers::WSockFrame->new(max_payload_size => 500 * 1024 * 1024);

    {
        local $INPUT_RECORD_SEPARATOR = undef;

        my $socketclosed = 0;

        $ua->{realsocket}->blocking(0);
        binmode($ua->{realsocket}, ':bytes');

        my $starttime = time + 10;

        while(!$socketclosed) {
            my $workCount = 0;

            # Read data from websocket
            my $buf;
            eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                local $SIG{ALRM} = sub{croak "alarm"};
                alarm 0.5;
                my $status = sysread($ua->{realsocket}, $buf, $settings{chunk_size} * 2);
                if(!$ua->{realsocket}) {
                #if(0 && defined($status) && $status == 0) {
                    if($self->{isDebugging}) {
                        print STDERR "Websocket closed\n";
                    }
                    $socketclosed = 1;
                    last;
                }
                alarm 0;
            };
            if(defined($buf) && length($buf)) {
                $frame->append($buf);
                $workCount++;
            }

            while (my $message = $frame->next_bytes) {
                $workCount++;

                my $realmsg;
                my $parseok = 0;
                eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                    $realmsg = decode_json($message);
                    $parseok = 1;
                };
                if(!$parseok || !defined($realmsg) || !defined($realmsg->{type})) {
                    # Broken message
                    next;
                }

                if($frame->opcode == 8) {
                    #print STDERR "Connection closed by Browser\n";
                    $socketclosed = 1;
                    last;
                }

                if($realmsg->{type} eq 'PING') {
                    $timeout = time + $settings{client_disconnect_timeout};
                    my %msg = (
                        type => 'PING',
                    );
                    if(!webPrint($ua->{realsocket}, $frame->new(buffer => encode_json(\%msg), type => 'text')->to_bytes)) {
                        #print STDERR "Write to socket failed, closing connection!\n";
                        $socketclosed = 1;
                        last;
                    }
                    next;
                    
                } elsif($realmsg->{type} eq 'UPLOADREQUEST') {
                    #print STDERR "Got upload request for ", $realmsg->{filename}, "\n";
                    
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
                        open(my $ifh, '<', $updata{localname}) or croak($ERRNO);
                        binmode($ifh);
                        my $chunknum = 0;
                        
                        while(1) {
                            my $chunk;
                            sysread($ifh, $chunk, $settings{chunk_size});
                            last if(!defined($chunk) || !length($chunk));
                            
                            push @localhashes, sha256_hex(encode_base64($chunk, ''));
                            #print STDERR "B:", encode_base64($chunk, ''), "#\n";
                            #print STDERR "S:", sha256_hex(encode_base64($chunk, '')), "#\n";
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
                        push @upfiles, \%updata;
                    } else {
                        # No missing chunks
                        #print STDERR "Identical files!\n";
                        my %donemsg = (
                            type => 'FILEDONE',
                            filename => $updata{remotename},
                        );
                        if(!webPrint($ua->{realsocket}, $frame->new(buffer => encode_json(\%donemsg), type => 'text')->to_bytes)) {
                            #print STDERR "Write to socket failed, closing connection!\n";
                            $socketclosed = 1;
                            last;
                        }
                    }
                    $workCount++;
                    
                } elsif($realmsg->{type} eq 'SETCHUNK') {
                    #print STDERR "Got a data chunk!!!!!\n";
                    if($realmsg->{filename} ne $upfiles[0]->{remotename} ||
                        $realmsg->{chunk} ne $upfiles[0]->{missingchunks}->[0]) {
                        #print STDERR "Wrong filename or chunk recieved, closing connection!\n";
                        $socketclosed = 1;
                    } else {
                        my $seekto = $realmsg->{chunk} * $settings{chunk_size};
                        my $filemode = '+<';
                        if(!-f $upfiles[0]->{localname}) {
                            $filemode = '>';
                            if($seekto != 0) {
                                croak("Internal error: New file must begin with first chunk!");
                            }
                        }
                        open(my $ofh, $filemode, $upfiles[0]->{localname}) or croak($ERRNO);
                        binmode $ofh;
                        
                        seek($ofh, $seekto, 0);
                        #print STDERR "$seekto \n";
                        my $tmp = decode_base64($realmsg->{data});
                        #print STDERR "LEN: ", length($tmp), ", $tmp\n";
                        #syswrite($ofh, 'OASCH' . $tmp);
                        print $ofh $tmp;
                        close $ofh;
                        $workCount++;

                        
                        shift @{$upfiles[0]->{missingchunks}}; # Not missing anymore ;-)
                        if(!scalar @{$upfiles[0]->{missingchunks}}) {
                            # We are done with this file
                            my %donemsg = (
                                type => 'FILEDONE',
                                filename => $upfiles[0]->{remotename},
                            );
                            if(!webPrint($ua->{realsocket}, $frame->new(buffer => encode_json(\%donemsg), type => 'text')->to_bytes)) {
                                #print STDERR "Write to socket failed, closing connection!\n";
                                $socketclosed = 1;
                                last;
                            }
                            shift @upfiles;
                        }

                        $waitingforchunk = 0;
                    }
                } elsif($realmsg->{type} eq 'DELETEFILE') {
                    #$realmsg->{filename}
                    my $found = 0;
                    opendir(my $dfh, $self->{basepath}) or next;
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
                     if(!webPrint($ua->{realsocket}, $frame->new(buffer => encode_json(\%donemsg), type => 'text')->to_bytes)) {
                         #print STDERR "Write to socket failed, closing connection!\n";
                         $socketclosed = 1;
                         last;
                    }
                }
            }

            # This is OUTSIDE the $frame->next_bytes loop, because a close event never returns a full frame
            # from WSockFrame
            if($frame->is_close) {
                #print STDERR "CLOSE FRAME RECIEVED!\n";
                $socketclosed = 1;
                if(!webPrint($ua->{realsocket}, $frame->new(buffer => 'data', type => 'close')->to_bytes)) {
                    #print STDERR "Write to socket failed, failed to properly close connection!\n";
                }
            }
            
            if(!$waitingforchunk && scalar @upfiles) {
                my $remain = scalar @{$upfiles[0]->{missingchunks}};
                my $remote = scalar @{$upfiles[0]->{remotehashes}};
                my $percentage = 100 - int($remain / $remote * 100);
                my %msg = (
                    type => 'UPLOADCHUNK',
                    filename => $upfiles[0]->{remotename},
                    chunk => $upfiles[0]->{missingchunks}->[0],
                    percentage => $percentage,
                );
                if(!webPrint($ua->{realsocket}, $frame->new(buffer => encode_json(\%msg), type => 'text')->to_bytes)) {
                    #print STDERR "Write to socket failed, closing connection!\n";
                    $socketclosed = 1;
                    last;
                }
                $waitingforchunk = 1;
                $workCount++;
            }
            

            if(!$workCount) {
                sleep(0.01);
            }

            if($timeout < time) {
                #print STDERR "CLIENT TIMEOUT\n";
                $socketclosed = 1;
            }

        }
    }

    #print STDERR "Done\n";

    delete $self->{sessiondata};

    return 1;
}

sub get_files {
    my ($self, $ua) = @_;
    
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

sub clean_searchstring {
    my ($self, $searchstring) = @_;

    $searchstring =~ s/^\s+//;
    $searchstring =~ s/\s+$//;
    $searchstring =~ s/\s+/\ /g;
    my $safe_search_characters = 'a-zA-Z0-9_.\-\ !';
    $searchstring =~ s/[^$safe_search_characters]//g;
    return $searchstring;
}







sub get_download {
    my ($self, $ua) = @_;

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

sub file_get_multipart_contentlength {
    my ($self, $ua) = @_;

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

sub file_get_multipart {
    my ($self, $ua) = @_;

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

sub file_get {
    my ($self, $ua) = @_;

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

PageCamel::Web::Tools::WorkerControl -

=head1 SYNOPSIS

  use PageCamel::Web::Tools::WorkerControl;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 reload



=head2 get



=head2 socketstart



=head2 sockethandler



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
