package PageCamel::Web::VNC5;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;
use Digest::SHA1 qw(sha1);
use MIME::Base64;
use PageCamel::Helpers::WSockFrame;
use IO::Socket::INET;
use JSON::XS;
use IO::Handle;
use Time::HiRes qw[sleep alarm time];
use PageCamel::Helpers::Passwords;
use PageCamel::Helpers::Strings qw[windowsStringsQuote encodeVNCString normalizeString];
use PageCamel::Helpers::WebPrint;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my $ok = 1;
    # Required settings
    foreach my $key (qw[systemsettings reporting]) {
        if(!defined($self->{$key})) {
            print STDERR "PWReset.pm: Setting $key is required but not set!\n";
            $ok = 0;
        }
    }

    if(!$ok) {
        croak("Failed to load " . $self->{modname} . " due to config errors!");
    }

    return $self;
}

sub register {
    my $self = shift;

    if(defined($self->{webpath})) {
        $self->register_webpath($self->{webpath}, "get", "GET", "POST");
    }

    if(defined($self->{wspath})) {
        $self->register_webpath($self->{wspath}, 'socketstart', "GET", "CONNECT");
        $self->register_protocolupgrade($self->{wspath}, 'sockethandler', "websocket");
    }
    #$self->register_public_url($self->{wspath});

    return;
}

sub reload {
    my ($self) = @_;

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    $sysh->createText(modulename => $self->{modname},
                    settingname => 'usage_hint',
                    settingvalue => '',
                    description => 'Usage hint displayed on all masks',
                    processinghints => [
                        'type=textfield'
                                        ])
        or croak("Failed to create setting usage_hint!");

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

    $sysh->createText(modulename => $self->{modname},
                    settingname => 'force_base64',
                    settingvalue => 0,
                    description => 'Use Base64 encoding (slow)',
                    processinghints => [
                        'type=switch'
                                        ])
        or croak("Failed to create setting force_base64!");

    $sysh->createNumber(modulename => $self->{modname},
                    settingname => 'outgoing_packet_delay',
                    settingvalue => 0,
                    description => 'Force a delay (milliseconds)for each outgoing websocket packet',
                    value_min => 0.0,
                    value_max => 2000.0,
                    processinghints => [
                        'decimal=0',
                    ],
                    )
        or croak("Failed to create setting outgoing_packet_delay!");

    $sysh->createText(modulename => $self->{modname},
                    settingname => 'force_flush',
                    settingvalue => 0,
                    description => 'Add extra flush() calls after writes to sockets',
                    processinghints => [
                        'type=switch'
                                        ])
        or croak("Failed to create setting force_flush!");


    $sysh->createNumber(modulename => $self->{modname},
                    settingname => 'client_connect_timeout',
                    settingvalue => 30,
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
                    settingvalue => 30,
                    description => 'Client disconnect timeout (seconds)',
                    value_min => 5.0,
                    value_max => 120.0,
                    processinghints => [
                        'decimal=0',
                    ],
                    )
        or croak("Failed to create setting client_disconnect_timeout!");

    $sysh->createNumber(modulename => $self->{modname},
                    settingname => 'server_timeout',
                    settingvalue => 25,
                    description => 'Server timeout (seconds)',
                    value_min => 5.0,
                    value_max => 120.0,
                    processinghints => [
                        'decimal=0',
                    ],
                    )
        or croak("Failed to create setting server_timeout!");

    $sysh->createNumber(modulename => $self->{modname},
                    settingname => 'vnc_block_size',
                    settingvalue => 1000,
                    description => 'Read block max size (bytes) for VNC TCP socket',
                    value_min => 100.0,
                    value_max => 1_000_000.0,
                    processinghints => [
                        'decimal=0',
                    ],
                    )
        or croak("Failed to create setting server_timeout!");

    $sysh->createNumber(modulename => $self->{modname},
                    settingname => 'ws_block_size',
                    settingvalue => 100,
                    description => 'Read block max size (bytes) for Websocket',
                    value_min => 100.0,
                    value_max => 1_000_000.0,
                    processinghints => [
                        'decimal=0',
                    ],
                    )
        or croak("Failed to create setting server_timeout!");

    $sysh->createBool(modulename => $self->{modname},
                        settingname => 'record_session',
                        settingvalue => 0,
                        description => 'Record all sessions',
                        processinghints => [
                            'type=switch',
                                            ])
            or croak("Failed to create setting record_session!");

    return;
}


sub get {
    my ($self, $ua) = @_;

    my $th = $self->{server}->{modules}->{templates};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    
    my $webpath = $ua->{url};
    
    my $search = $self->{webpath} . '/admdirect/';
    if($webpath =~ /^$search(.*)/) {
        my $cname = $1;
        my %webdata =
        (
            $self->{server}->get_defaultwebdata(),
        );
        if(contains('has_admin', $webdata{userData}->{rights})) {
            # Simulate a POST from the "select" webmask
            $ua->{method} = 'POST';
            $ua->{postparams}->{'reason'} = 'Check ComputerDB VNC settings';
            $ua->{postparams}->{'computername'} = $cname;
        }
    }

    my $uamethod = $ua->{method} || '';
    if($uamethod eq 'POST') {
        return $self->get_vnc($ua);
    } else {
        return $self->get_select($ua);
    }
}

sub get_select {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $th = $self->{server}->{modules}->{templates};
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $pwh = PageCamel::Helpers::Passwords->new({dbh => $dbh, reph => $reph, sysh => $sysh});

    my ($ok1, $usagehint) = $sysh->get($self->{modname}, 'usage_hint');

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{pagetitle},
        webpath         =>  $self->{webpath},
        PostLink        =>  $self->{webpath},
        UsageHint       =>  $usagehint,
        showads => $self->{showads},
    );

    my @computers;
    my $selsth = $dbh->prepare_cached("SELECT * FROM computers NATURAL JOIN computers_vnccompany
                                      WHERE company_name = ?
                                      AND is_enabled = 't'
                                      AND has_vnc = true
                                      AND vnc_password != ''
                                      ORDER BY line_id, computer_name")
            or croak($dbh->errstr);
    if(!$selsth->execute($webdata{userData}->{company})) {
        $dbh->rollback;
    } else {
        while((my $computer = $selsth->fetchrow_hashref)) {
            push @computers, $computer;
        }
        $selsth->finish;
    }
    $webdata{AvailComputers} = \@computers;

    $dbh->rollback;

    my $template = $th->get("vncselect", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub get_vnc {
    my ($self, $ua) = @_;

    my $th = $self->{server}->{modules}->{templates};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $pwh = PageCamel::Helpers::Passwords->new({dbh => $dbh, reph => $reph, sysh => $sysh});

    my ($ok1, $husebase64) = $sysh->get($self->{modname}, 'force_base64');
    my $usebase64 = $husebase64->{settingvalue};

    my %clientsettings;
    foreach my $sname (qw[client_connect_timeout client_disconnect_timeout websocket_encryption force_base64]) {
        my ($ok2, $sval) = $sysh->get($self->{modname}, $sname);
        if($sval->{fieldtype} eq 'number') {
            $clientsettings{$sname} = 0 + $sval->{settingvalue};
        } else {
            $clientsettings{$sname} = $sval->{settingvalue};
        }
    }

    my $exthostname = $ua->{headers}->{'Host'};
    my ($exthname, $exthport) = split/\:/, $exthostname;
    if(!defined($exthname) || $exthname eq '') {
        $exthname = $self->{proxyhost};
    }
    if(!defined($exthport) || $exthport eq '') {
        $exthport = $self->{proxyport};
    }


    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        PostLink    =>  $self->{webpath},
        ProxyHost   =>  $exthname,
        ProxyPort   =>  $exthport,
        AjaxGetCard =>  $self->{webpath} . '/getcard',
        AjaxSetCard =>  $self->{webpath} . '/setcard',
        ClientSettings => \%clientsettings,
        showads => $self->{showads},
    );
    if($usebase64) {
        $webdata{websocketencoding} = 'base64';
    } else {
        $webdata{websocketencoding} = 'binary';
    }

    my $reason = $ua->{postparams}->{'reason'} || '';
    #$reason = windowsStringsQuote($reason);
    $reason = normalizeString($reason);
    my $host = $ua->{postparams}->{'computername'} || '';
    my $hostok = 0;

    my $hostdata;
    my $selsth = $dbh->prepare_cached("SELECT * FROM computers NATURAL JOIN computers_vnccompany
                                      WHERE company_name = ?
                                      AND computer_name = ?
                                      AND is_enabled = 't'
                                      AND has_vnc = true
                                      AND vnc_password != ''
                                      ORDER BY line_id, computer_name")
            or croak($dbh->errstr);
    if(!$selsth->execute($webdata{userData}->{company}, $host)) {
        $dbh->rollback;
    } else {
        while((my $computer = $selsth->fetchrow_hashref)) {
            if($computer->{computer_name} eq $host) {
                $hostok = 1;
                $hostdata = $computer;
            }
        }
        $selsth->finish;
    }
    if($reason eq '' || $host eq '') {
        $hostok = 0;
    }

    if(!$hostok) {
        # Something went wrong, just re-display the select mask
        $dbh->rollback;
        return $self->get_select($ua);
    }

    $webdata{Computer} = $hostdata;


    my $proxyport = 0;



    my $sockid = $pwh->gen_textsalt();
    # Construct the socket path from WSPath
    #my $socketpath = 'ws';
    #if($self->{usessl}) {
    #    $socketpath = 'wss';
    #}
    #$socketpath .= '://' . $exthostname . $self->{wspath} . '/' . $sockid;
    my $socketpath = $self->{wspath} . '/' . $sockid;


    $webdata{WSPath} = $socketpath;

    my $insth = $dbh->prepare_cached("INSERT INTO computers_vnc_session (session_id, computer_name, ip_address, vnc_port)
                                     VALUES (?, ?, ?, ?)")
            or croak($dbh->errstr);
    if(!$insth->execute($sockid, $host, $hostdata->{vnc_ip}, $hostdata->{vnc_port})) {
        $dbh->rollback;
        return(status => 500);
    }
    $webdata{vncsessionid} = $sockid;
    $webdata{vncdestinationip} = $hostdata->{$self->{computer_ip_column}};

    my $logsth = $dbh->prepare_cached("INSERT INTO computers_vnclog
                    (logtype, computer_name, client_ip, proxy_port, freelogtext, username, htmlversion)
                    VALUES ('VNC5_SESSION_START', ?, ?, ?, ?, ?, ?)")
                or croak($dbh->errstr);
    if(!$logsth->execute($host, $ua->{remote_addr}, 0, $reason, $webdata{userData}->{user}, 'html5')) {
        $dbh->rollback;
        return(status => 500);
    }

    $webdata{VNCPass} = $hostdata->{vnc_password};

    my @extracss = (
        '/static/vnc_html5/base.css',
        '/static/vnc_html5/black.css',
        '/static/vnc_html5/pagecamel.css',
    );
    $webdata{HeadExtraCSS} = \@extracss;


    $dbh->commit;
    
    if(contains('has_admin', $webdata{userData}->{rights})) {
        $webdata{ADMINMODE} = 1;
    } else {
        $webdata{ADMINMODE} = 0;
    }
    
    my $template = $th->get("vnc5", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub socketstart {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    my ($ok1, $husebase64) = $sysh->get($self->{modname}, 'force_base64');
    my $usebase64 = $husebase64->{settingvalue};

    my $upgrade = $ua->{headers}->{"Upgrade"};
    my $seckey = $ua->{headers}->{"Sec-WebSocket-Key"};
    my $protocol = $ua->{headers}->{"Sec-WebSocket-Protocol"};
    my $version = $ua->{headers}->{"Sec-WebSocket-Version"};

    if(!defined($upgrade) || !defined($seckey) || !defined($version)) {
        return (status => 400); # BAAAD Request! Sit! Stay!
    }

    # Check database
    my $oldsth = $dbh->prepare_cached("DELETE FROM computers_vnc_session
                               WHERE valid_until < now()")
            or croak($dbh->errstr);

    my $selsth = $dbh->prepare_cached("SELECT * FROM computers_vnc_session
                                      WHERE session_id = ?")
            or croak($dbh->errstr);

    if(!$oldsth->execute) {
        $dbh->rollback;
        return (status=>500);
    }

    my $webpath = $ua->{url};
    my $remove = $self->{wspath};
    $webpath =~ s/$remove//;
    $webpath =~ s/^\///;
    if(!$selsth->execute($webpath)) {
        $dbh->rollback;
        return (status => 500);
    }
    my $session = $selsth->fetchrow_hashref;
    $selsth->finish;
    if(!defined($session)) {
        $dbh->commit;
        return(status => 404);
    }

    $dbh->commit;

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
    );
    $session->{sockid} = $webpath;
    $session->{user} = $webdata{userData}->{user};
    $self->{sessiondata} = $session;

    $seckey .= "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"; # RFC6455 GUID for Websockets

    $seckey = encode_base64(sha1($seckey), '');

    my $proto = 'binary';
    if($usebase64) {
        $proto = 'base64';
    }
    my %result = (status      =>  101,
                  Upgrade     => "websocket",
                  Connection  => "Upgrade",
                  "Sec-WebSocket-Accept"  => $seckey,
                  "Sec-WebSocket-Protocol" => $proto,
                 );

    return %result;
}

sub sockethandler { ## no critic (Subroutines::ProhibitExcessComplexity)
    my ($self, $ua) = @_;

    my $session = $self->{sessiondata};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    my ($ok1, $husebase64) = $sysh->get($self->{modname}, 'force_base64');
    my ($ok2, $htestsleep) = $sysh->get($self->{modname}, 'outgoing_packet_delay');
    my ($ok3, $hforceflush) = $sysh->get($self->{modname}, 'force_flush');
    my ($ok4, $htimeout) = $sysh->get($self->{modname}, 'server_timeout');
    my ($ok5, $hvncreadblocksize) = $sysh->get($self->{modname}, 'vnc_block_size');
    my ($ok6, $hwsreadblocksize) = $sysh->get($self->{modname}, 'ws_block_size');
    my ($ok7, $hrecordsession) = $sysh->get($self->{modname}, 'record_session');

    my $usebase64 = $husebase64->{settingvalue};
    my $testsleep = $htestsleep->{settingvalue} / 1000;
    my $forceflush = $hforceflush->{settingvalue};
    my $timeout = $htimeout->{settingvalue};
    my $vncreadblocksize = $hvncreadblocksize->{settingvalue};
    my $wsreadblocksize = $hwsreadblocksize->{settingvalue};
    my $recordsession = $hrecordsession->{settingvalue};

    my $frame = PageCamel::Helpers::WSockFrame->new;

    my $rfh;
    my $starttime = time;

    my $brokenpipe = 0;
    local $SIG{PIPE} = sub { $brokenpipe = 1; };

    if($recordsession) {
        open($rfh, '>', '/home/cavac/src/temp/vncrecord_' . $session->{ip_address} . '.dat') or croak($ERRNO); ## no critic (InputOutput::RequireBriefOpen)
        print $rfh "var VNC_frame_encoding = 'binary';\n";
        print $rfh "var VNC_frame_data = [\n";
    }


    if($self->{isDebugging}) {
        print STDERR "Start Websocket protocol handler\n";
    }

    my $validstr = "UPDATE computers_vnc_session " .
                    "SET valid_until = now() + '" . (($timeout * 2) + 10) . " seconds'::interval " .
                   "WHERE session_id = ?";
    my $validsth = $dbh->prepare_cached($validstr)
            or croak($dbh->errstr);

    {
        local $INPUT_RECORD_SEPARATOR = undef;
        binmode($ua->{realsocket}, ':bytes');

        if($forceflush) {
            STDOUT->flush();
        }

        my $socketclosed = 0;

        if($self->{isDebugging}) {
            print STDERR "Connecting to " . $session->{ip_address} . ":" . $session->{vnc_port} . "\n";
        }

        my $vnc = IO::Socket::INET->new(
            PeerHost => $session->{ip_address},
            PeerPort => $session->{vnc_port},
            Proto => 'tcp',
        );

        if(!defined($vnc)) {
            print STDERR "Can't connect to " . $session->{ip_address} . ":" . $session->{vnc_port} . "\n";
            return;
        }

        $ua->{realsocket}->blocking(0);
        $vnc->blocking(0);

        my $nextping = 0;
        my $lastpong = 0;
        my $lastmsg = 0;
        my $username = 'anonymous';
        my @lines = ();
        my $idle = 0;


        if($self->{isDebugging}) {
            print STDERR " Ready to handle websocket data...\n";
        }

        while(!$socketclosed && !$brokenpipe) {
            my $webline = "";
            my $vncline = "";
            my $buf;

            # Yield processor slot when idling
            if($idle) {
                sleep(0.05);
            }
            $idle = 1;

            if(time > $nextping) {
                $nextping = time + $timeout;
                if(!webPrint($ua->{realsocket}, $frame->new(buffer=>'keepalive', type => 'ping')->to_bytes)) {
                    if($self->{isDebugging}) {
                        print STDERR "WS Write Timeout (Ping)!\n";
                    }
                    $socketclosed = 1;
                    next;
                }
                if($forceflush) {
                    $ua->{realsocket}->flush();
                }
                if($testsleep) {
                    sleep($testsleep);
                }
                $idle = 0;
            }

            if($lastpong && $lastpong < (time - $timeout * 2)) {
                if($self->{isDebugging}) {
                    print STDERR "WS Pong Timeout!\n";
                }
                $socketclosed = 1;
                next;
            }

            if($lastmsg && $lastmsg < (time - $timeout * 2)) {
                if($self->{isDebugging}) {
                    print STDERR "Last message Timeout!\n";
                }
                $socketclosed = 1;
                next;
            }

            if(!$socketclosed) {
                $buf = undef;
                my $vncstatus = sysread($vnc, $buf, $vncreadblocksize);
                if(!$vnc->connected) {
                    if($self->{isDebugging}) {
                        print STDERR "VNC Socket closed\n";
                    }
                    $socketclosed = 1;
                    last;
                }
                if(defined($buf) && length($buf)) {
                    $vncline .= $buf;
                    $idle = 0;
                }
            }

            if(!$socketclosed) {
                $buf = undef;

                my $status = sysread($ua->{realsocket}, $buf, $wsreadblocksize);
                if(!$ua->{realsocket}) {
                    if($self->{isDebugging}) {
                        print STDERR "Websocket closed\n";
                    }
                    $socketclosed = 1;
                    last;
                }

                if(defined($buf) && length($buf)) {
                    $webline .= $buf;
                    $idle = 0;
                }
            }

            if(length($webline)) {
                if(0 && $self->{isDebugging}) {
                    print STDERR "#########  Got ", length($webline), " WS bytes\n";
                }

                $frame->append($webline);
            }

            if(length($vncline)) {
                if(0 && $self->{isDebugging}) {
                    print STDERR "#########  Got ", length($vncline), " VNC bytes\n";
                }
                if($recordsession) {
                    my $toffs = int((time - $starttime) * 1000);
                    print $rfh '\'{' . $toffs . '{' . encodeVNCString($vncline) . '\',' . chr(10);
                }
                my $printok;
                if($usebase64) {
                    my $bvncline = encode_base64($vncline, '');
                    $printok = webPrint($ua->{realsocket}, $frame->new(buffer => $bvncline, type => 'text')->to_bytes);
                } else {
                    $printok = webPrint($ua->{realsocket}, $frame->new(buffer => $vncline, type => 'binary')->to_bytes);
                }
                if(!$printok) {
                    if($self->{isDebugging}) {
                        print STDERR "WS write Timeout!\n";
                    }
                    $socketclosed = 1;
                    next;
                }
                if($forceflush) {
                    $ua->{realsocket}->flush();
                }
                if($testsleep) {
                    sleep($testsleep);
                }
            };

            while (my $message = $frame->next_bytes) {
                #$idle = 0;
                if(0 && $self->{isDebugging}) {
                    print STDERR "> Opcode: ", $frame->opcode, "\n";
                }
                #print STDERR Dumper($message);

                $lastmsg = time;

                if($frame->is_pong) {
                    if(!$validsth->execute($session->{session_id})) {
                        $dbh->rollback;
                    } else {
                        $dbh->commit;
                    }
                    if(0 && $self->{isDebugging}) {
                        print STDERR getISODate(). "  PONG\n";
                    }
                    $lastpong = time;
                    next;
                }

                #if($testsleep) {
                #    sleep($testsleep);
                #}

                if($usebase64) {
                    $message = decode_base64($message);
                }

                if($recordsession) {
                    my $toffs = int((time - $starttime) * 1000);
                    print $rfh '\'}' . $toffs . '}' . encodeVNCString($message) . '\',' . chr(10);
                }
                if(!webPrint($vnc, $message)) {
                    if($self->{isDebugging}) {
                        print STDERR "VNC write Timeout!\n";
                    }
                    $socketclosed = 1;
                    next;
                }
                if($forceflush) {
                    $vnc->flush();
                }

                next;
            }

            # This is OUTSIDE the $frame->next_bytes loop, because a close event never returns a full frame
            # from WSockFrame
            if($frame->is_close) {
                if($self->{isDebugging}) {
                    print STDERR "WS send 'Socket close'!\n";
                }
                if(!webPrint($ua->{realsocket}, $frame->new(buffer => 'data', type => 'close')->to_bytes)) {
                    print STDERR "Write to socket failed, failed to properly close connection!\n";
                }
                $socketclosed = 1;
            }
        }

        close $vnc;

    }

    my $logsth = $dbh->prepare_cached("INSERT INTO computers_vnclog
                (logtype, computer_name, client_ip, proxy_port, freelogtext, username, htmlversion)
                VALUES ('VNC5_SESSION_END', ?, ?, ?, ?, ?, ?)")
            or croak($dbh->errstr);
    if(!$logsth->execute($session->{computer_name}, $ua->{remote_addr}, 0, 'Disconnect', $session->{user}, 'html5')) {
        $dbh->rollback;
    } else {
        $dbh->commit;
    }

    my $delsth = $dbh->prepare_cached("DELETE FROM computers_vnc_session
                           WHERE session_id = ?")
        or croak($dbh->errstr);
    if(!$delsth->execute($session->{session_id})) {
        $dbh->rollback;
    } else {
        $dbh->commit;
    }


    delete $self->{sessiondata};
    $ua->{realsocket}->blocking(0);

    if($recordsession) {
        print $rfh "'EOF'];\n";
        close $rfh;
    }

    return 1;
}


1;
__END__

=head1 NAME

PageCamel::Web::VNC5 -

=head1 SYNOPSIS

  use PageCamel::Web::VNC5;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 reload



=head2 get



=head2 get_select



=head2 get_vnc



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
