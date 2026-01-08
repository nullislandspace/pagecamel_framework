package PageCamel::Web::BaseWebSocket;
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
use PageCamel::Helpers::DateStrings;
use MIME::Base64;
use PageCamel::Helpers::WSockFrame;
use JSON::XS;
use Time::HiRes qw[sleep alarm time];
use PageCamel::Helpers::WebPrint;
use Digest::SHA1  qw(sha1 sha1_hex);
use IO::Select;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class
    
    if(defined($self->{wspath})) {
        croak("Option 'wspath' set, but not allowed with new BaseWebSocket class");
    }

    my $ok = 1;
    foreach my $key (qw[reporting systemsettings]) {
        if(!defined($self->{$key})) {
            print STDERR "BaseWebSocket for ", $self->{modname}, " is missing setting ", $key, "\n";
            $ok = 0;
        }
    }
    if(!$ok) {
        croak("Config errors in module ", $self->{modname});
    }

    if(!defined($self->{sleeptime})) {
        # Make it VERY responsive and CPU hungry by default
        $self->{sleeptime} = 0.01;
    }

    if(!defined($self->{reconnect})) {
        $self->{reconnect} = 0;
    }

    if(!defined($self->{blockui})) {
        $self->{blockui} = 1;
    }

    if(!defined($self->{socket_only})) {
        $self->{socket_only} = 0;
    }

    if(!defined($self->{usemastertemplate})) {
        $self->{usemastertemplate} = 1;
    }

    return $self;
}

sub register($self) {
    $self->register_webpath($self->{webpath}, 'get', "GET", "CONNECT");
    $self->register_protocolupgrade($self->{webpath}, 'sockethandler', "websocket");
    
    $self->wsregister();
    
    return;
}

sub crossregister($self) {
    if(defined($self->{public}) && $self->{public}) {
        $self->register_public_url($self->{webpath});
    }
    
    $self->wscrossregister();
    return;
}

sub reload($self) {
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
                    settingvalue => 10,
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

    $self->wsreload();
        
    return;
}

# define empty Websocket base callbacks (in case the specific implementation doesn't overload them)
sub wsregister($self) {
    return;
}

sub wscrossregister($self) {
    return;
}

sub wsreload($self) {
    return;
}

sub wsmaskget($self, $ua, $settings, $webdata) {
    return 200; # HTTP Status OK
}

sub wsstart($self, $ua, $webdata) {
    return;
}

sub wshandlerstart($self, $ua, $settings) {
    return;
}

sub wsdisconnect($self, $ua, $settings) {
    return;
}

sub wscleanup($self, $ua, $settings) {
    return;
}


sub wshandlemessage($self, $message) {
    return 1;
}

sub wshandlebinarymessage($self, $message) {
    return 1;
}


sub wscyclic($self, $ua) {
    return 1;
}

sub wsprint($self, $message, $usebinary = 0) {
    my $frame = $self->{sessiondata}->{frame};
    my $ua = $self->{sessiondata}->{ua};
    my $settings = $self->{sessiondata}->{settings};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $webprint = PageCamel::Helpers::WebPrint->new(reph => $reph);
    
    my $buffer = encode_json($message);
    #$reph->debuglog("JSON: $buffer");
    
    my $frametype = 'text';
    if($usebinary) {
        $frametype = 'binary';
    }
    
    my $framedata = $frame->new(buffer => $buffer, type => $frametype)->to_bytes;

    #$reph->debuglog("Sending ", length($framedata) , " bytes (= original buffer length ", length($buffer) , " bytes)");
    #my $starttime = time;
    if(!$webprint->write($ua->{realsocket}, $framedata)) {
        $reph->debuglog("Write to socket failed, closing connection!");
        return 0;
    }
    #my $endtime = time;
    #$reph->debuglog("   done, took ", $endtime - $starttime, " seconds");
    
    return 1;
}

sub get($self, $ua) {
    my $th = $self->{server}->{modules}->{templates};
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $upgrade = $ua->{headers}->{"Upgrade"};
    if(defined($upgrade)) {
        # Handle Websocket connection
        return $self->socketstart($ua);
    }

    if($self->{socket_only}) {
        return (status => 426, # "Upgrade required
            Upgrade     => "websocket",
        );
    }

    my %settings;
    my @setnames = qw[websocket_encryption client_connect_timeout client_disconnect_timeout chunk_size];
    push @setnames, @{$self->{extrasettings}};
    foreach my $setname (@setnames) {
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
    $wsurl .= $ua->{headers}->{Host} . $self->{webpath};
    $settings{ping_timeout} = int($settings{client_disconnect_timeout} * 1000 / 2);
    
    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{pagetitle},
        webpath         =>  $self->{webpath},
        Settings        =>  \%settings,
        WSURL           =>  $wsurl,
        Reconnect       =>  $self->{reconnect},
        BlockUI         =>  $self->{blockui},
        EnableDB        =>  1,
        showads => $self->{showads},
    );

    if(!$self->{isDebugging}) {
        # Allow overriding default
        $webdata{isDebugging} = 0; 
    }

    push @{$webdata{HeadExtraModuleScriptsNoPostfix}}, '/static/pchelpers/import_pcwebsocket.js';
    
    my $substatus = $self->wsmaskget($ua, \%settings, \%webdata);
    if($substatus == 999) {
        # Display mask with error message instead
        my $errortemplate = $th->get("basewebsocket_error", $self->{usemastertemplate}, %webdata);
        return (status  =>  404) unless $errortemplate;
        return (status  =>  200,
                type    => "text/html",
                data    => $errortemplate);
    }

    if($substatus != 200) {
        return (status => $substatus);
    }

    my $subtemplate = $th->render_partials($self->{template}, %webdata);
    if(!defined($subtemplate)) {
        $reph->debuglog("Error rendering subtemplate ", $self->{template}, " for BaseWebSocket: ", $self->{modname});
        return (status  =>  404);
    }
    $webdata{WEBSOCKETMASK} = $subtemplate;

    $webdata{allowCloseSocket} = '1';
    if(!$self->{usemastertemplate}) {
        $webdata{allowCloseSocket} = '0';
    }

    my $template = $th->get("basewebsocket", $self->{usemastertemplate}, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

    
sub socketstart($self, $ua) {
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    my $upgrade = $ua->{headers}->{"Upgrade"};
    my $seckey = $ua->{headers}->{"Sec-WebSocket-Key"};
    my $protocol = $ua->{headers}->{"Sec-WebSocket-Protocol"};
    my $version = $ua->{headers}->{"Sec-WebSocket-Version"};

    if(!defined($upgrade) || !defined($seckey) || !defined($version)) {
        return (status => 400); # BAAAD Request! Sit! Stay!
    }

    my %settings;
    my @setnames = qw[websocket_encryption client_connect_timeout client_disconnect_timeout chunk_size];
    push @setnames, @{$self->{extrasettings}};
    foreach my $setname (@setnames) {
        my ($ok, $setref) = $sysh->get($self->{modname}, $setname);
        if(!$ok || !defined($setref->{settingvalue})) {
            croak("Failed to read setting $setname");
        }
        $settings{$setname} = $setref->{settingvalue};
    }

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
    );
    my $session = {};
    $session->{user} = $webdata{userData}->{user};
    $self->{sessiondata} = $session;

    $seckey .= "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"; # RFC6455 GUID for Websockets

    $seckey = encode_base64(sha1($seckey), '');

    # $proto must match the same string from  JavaScript side: new WebSocket(ttvars.websocketurl, 'pagecamel');
    my $proto = 'pagecamel';
    
    $self->wsstart($ua, \%webdata);

    my %result = (status      =>  101,
                  Upgrade     => "websocket",
                  Connection  => "Upgrade",
                  "Sec-WebSocket-Accept"  => $seckey,
                  "Sec-WebSocket-Protocol" => $proto,
                 );

    return %result;
}

sub sockethandler($self, $ua) {
    my $session = $self->{sessiondata};
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    my $th = $self->{server}->{modules}->{templates};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $webprint = PageCamel::Helpers::WebPrint->new(reph => $reph);

    my %settings;
    my @setnames = qw[websocket_encryption client_connect_timeout client_disconnect_timeout chunk_size];
    push @setnames, @{$self->{extrasettings}};
    foreach my $setname (@setnames) {
        my ($ok, $setref) = $sysh->get($self->{modname}, $setname);
        if(!$ok || !defined($setref->{settingvalue})) {
            croak("Failed to read setting $setname");
        }
        $settings{$setname} = $setref->{settingvalue};
    }
    
    $self->wshandlerstart($ua, \%settings);

    my $timeout = time + $settings{client_disconnect_timeout};

    my $frame = PageCamel::Helpers::WSockFrame->new(max_payload_size => 500 * 1024 * 1024);
    $self->{sessiondata}->{frame} = $frame;
    $self->{sessiondata}->{ua} = $ua;
    $self->{sessiondata}->{settings} = \%settings;

    {
        local $INPUT_RECORD_SEPARATOR = undef;

        my $socketclosed = 0;

        $ua->{realsocket}->blocking(0);
        binmode($ua->{realsocket}, ':bytes');

        my $select = IO::Select->new($ua->{realsocket});
        my $starttime = time + 10;

        while(!$socketclosed) {
            my $workCount = 0;

            # Read data from websocket using IO::Select instead of alarm()
            my $buf;
            if($select->can_read(0.1)) {
                my $status = sysread($ua->{realsocket}, $buf, $settings{chunk_size} * 2);
                if(!defined($status) || $status == 0) {
                    if($self->{isDebugging}) {
                        $reph->debuglog("Websocket closed");
                    }
                    $socketclosed = 1;
                    last;
                }
            }
            if(defined($buf) && length($buf)) {
                $frame->append($buf);
                $workCount++;
            }

            while (my $message = $frame->next_bytes) {
                $workCount++;

                #$reph->debuglog("OPCODE ", $frame->opcode);

                if($frame->opcode == 8) {
                    $reph->debuglog("Connection closed by Browser");
                    $socketclosed = 1;
                    last;
                }

                if($frame->opcode == 2) {
                    #$reph->debuglog("BINARY FRAME! ", Dumper($message));
                    if(!$self->wshandlebinarymessage($message)) {
                        $socketclosed = 1;
                        last;
                    }
                }


                if($frame->opcode != 1) {
                    $reph->debuglog("UNSUPPORTED OPCODE ", $frame->opcode);
                    next;
                }

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


                if($realmsg->{type} eq 'PING') {
                    $timeout = time + $settings{client_disconnect_timeout};
                    my %msg = (
                        type => 'PING',
                    );
                    if(!$self->wsprint(\%msg)) {
                        $reph->debuglog("Write to socket failed, closing connection!");
                        $socketclosed = 1;
                        last;
                    }
                    next;
                } elsif($realmsg->{type} eq 'DEBUGLOG') {
                    my $debugline;
                    if(ref $realmsg->{data} eq 'SCALAR' || ref $realmsg->{data} eq '') {
                        $debugline = $realmsg->{data};
                    } else {
                        $debugline = Dumper($realmsg->{data});
                        if($debugline =~ /^\$VAR1\ \=\ \{\}\;/) {
                            $debugline = '';
                        }
                    }
                    if($debugline ne '') {
                        $reph->debuglog("DEBUGLOG MESSAGE: ", $debugline);
                    }
                } else {
                    if(!$self->wshandlemessage($realmsg)) {
                        $socketclosed = 1;
                        last;
                    }
                }
            }

            # This is OUTSIDE the $frame->next_bytes loop, because a close event never returns a full frame
            # from WSockFrame
            if($frame->is_close) {
                $reph->debuglog("CLOSE FRAME RECIEVED!");
                $socketclosed = 1;
                if(!$webprint->write($ua->{realsocket}, $frame->new(buffer => 'data', type => 'close')->to_bytes)) {
                    $reph->debuglog("Write to socket failed, failed to properly close connection!");
                }
            }
            
            if(!$self->wscyclic($ua)) {
                $socketclosed = 1;
                last;
            }

            if($timeout < time) {
                $reph->debuglog("CLIENT TIMEOUT");
                $socketclosed = 1;
            }

        }
    }

    $self->wsdisconnect($ua, \%settings);
    $self->wscleanup();

    delete $self->{sessiondata};

    return 1;
}


1;
__END__
