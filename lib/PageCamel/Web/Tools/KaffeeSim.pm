# PAGECAMEL  (C) 2008-2019 Rene Schickbauer
# Developed under Artistic license
package PageCamel::Web::Tools::KaffeeSim;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 2.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;
use Digest::SHA1 qw(sha1);
use MIME::Base64;
use PageCamel::Helpers::WSockFrame;
use IO::Socket::INET;
use JSON::XS;
use IO::Handle;
use Time::HiRes qw[sleep alarm];
use Data::Dumper;
use Fcntl;
use PageCamel::Helpers::Passwords;
use PageCamel::Helpers::Strings qw[windowsStringsQuote];
use PageCamel::Helpers::WebPrint;
use Net::Clacks::Client;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    if(!defined($self->{readonly})) {
        $self->{readonly} = 0;
    }


    return $self;
}

sub register {
    my $self = shift;

    $self->register_webpath($self->{webpath}, 'get', "GET");
    $self->register_webpath($self->{wspath}, 'socketstart', "GET", "CONNECT");
    $self->register_protocolupgrade($self->{wspath}, 'sockethandler', "websocket");

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

    return;
}

sub get {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $th = $self->{server}->{modules}->{templates};
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    my %settings;
    foreach my $setname (qw[websocket_encryption client_connect_timeout client_disconnect_timeout]) {
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

    my %webdata =
    (
        $self->{server}->get_defaultwebdata(),
        PageTitle       =>  $self->{pagetitle},
        webpath         =>  $self->{webpath},
        PostLink        =>  $self->{webpath},
        Settings        =>  \%settings,
        WSURL           =>  $wsurl,
        PingTimeout     => int($settings{client_disconnect_timeout} * 1000 / 2),
        Readonly        => $self->{readonly},
        isDebugging     => $self->{isDebugging},
    );


    my $template = $th->get("tools/kaffeesim", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
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
    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};

    my %settings;
    foreach my $setname (qw[websocket_encryption client_connect_timeout client_disconnect_timeout]) {
        my ($ok, $setref) = $sysh->get($self->{modname}, $setname);
        if(!$ok || !defined($setref->{settingvalue})) {
            croak("Failed to read setting $setname");
        }
        $settings{$setname} = $setref->{settingvalue};
    }

    my $clacks = $self->newClacksFromConfig($clconf);

    my @clackssettings = (
        'Production_Enable',
        'Manual_Override',
        'Boiler::Waterlevel',
        'Boiler::Invalve',
        'Boiler::Temp',
        'Boiler::Heater',
        'Boiler::Outvalve',
        'Boiler::Fullrefill',
        'Beans::Level',
        'Beans::Invalve',
        'Grinder::Power',
        'Mixer::Power',
        'Outcounter::Count',
        'Outcounter::Flowing',
        'Wastecounter::Count',
        'Wastecounter::Flowing',
    );
    my %reverselookup;
    my %lookup;


    foreach my $setname (@clackssettings) {
        $clacks->listen('Kaffee::' . $setname);
        my ($device, $sensor) = split/\:\:/, $setname;
        my $lname;
        if(defined($sensor)) {
            $lname = lc $device . '_' . lc $sensor;
        } else {
            $lname = lc $device;
        }
        $reverselookup{$lname} = $setname;
        $lookup{'Kaffee::' . $setname} = $lname;
    }
    $clacks->notify('Kaffee::update_all');


    my $timeout = time + $settings{client_disconnect_timeout};

    my $frame = PageCamel::Helpers::WSockFrame->new;

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
                my $status = sysread($ua->{realsocket}, $buf, 100);
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

            $workCount += $clacks->doNetwork();

            while (my $message = $frame->next_bytes) {
                $workCount++;
                #print STDERR "> Opcode: ", $frame->opcode, "\n";
                #print STDERR "    Data: ", $message, "\n";

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
                    if(!webPrint($ua->{realsocket}, $frame->new(buffer => encode_json(\%msg), type => 'text')->to_bytes)) {
                        print STDERR "Write to socket failed, closing connection!\n";
                        $socketclosed = 1;
                        last;
                    }
                    $clacks->ping();
                    print STDERR "Ping\n";
                    next;
                } elsif($realmsg->{type} eq 'LISTEN') {
                    if(!$self->{readonly}) {
                        $clacks->listen('Kaffee::' . $reverselookup{$realmsg->{varname}});
                    }
                } elsif($realmsg->{type} eq 'NOTIFY') {
                    if(!$self->{readonly}) {
                        $clacks->notify('Kaffee::' . $realmsg->{varname});
                    }
                } elsif($realmsg->{type} eq 'SET') {
                    if(!$self->{readonly}) {
                        $clacks->set('Kaffee::' . $reverselookup{$realmsg->{varname}}, $realmsg->{varvalue});
                    }
                }
            }

            # This is OUTSIDE the $frame->next_bytes loop, because a close event never returns a full frame
            # from WSockFrame
            if($frame->is_close) {
                print STDERR "CLOSE FRAME RECIEVED!\n";
                $socketclosed = 1;
                if(!webPrint($ua->{realsocket}, $frame->new(buffer => 'data', type => 'close')->to_bytes)) {
                    print STDERR "Write to socket failed, failed to properly close connection!\n";
                }
            }

            while(1 && !$socketclosed) {
                my $cmsg = $clacks->getNext();
                last unless defined($cmsg);

                #print STDERR "Clacks IN: ", $cmsg->{type}, "\n";
                $workCount++;

                if($cmsg->{type} eq 'set') {
                    if($cmsg->{name} =~ /enable/) {
                        print STDERR "Clacks SET: ", $cmsg->{name}, "\n";
                    }
                    my $webname = $lookup{$cmsg->{name}};
                    my %msg = (
                        type => 'VALUE',
                        varname => $webname,
                        varval => $cmsg->{data},
                    );
                    if(!webPrint($ua->{realsocket}, $frame->new(buffer => encode_json(\%msg), type => 'text')->to_bytes)) {
                        print STDERR "Write to socket failed, closing connection!\n";
                        $socketclosed = 1;
                        last;
                    }
                }
            }


            if(!$workCount) {
                sleep(0.05);
            }

            if($timeout < time) {
                print STDERR "CLIENT TIMEOUT\n";
                $socketclosed = 1;
            }

        }



    }


    print STDERR "Done\n";

    delete $self->{sessiondata};

    return 1;
}

1;
