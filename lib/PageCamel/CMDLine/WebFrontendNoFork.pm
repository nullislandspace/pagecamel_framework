package PageCamel::CMDLine::WebFrontendNoFork;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.7;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use IO::Socket::IP;
use IO::Socket::SSL;
use IO::Select;
use IO::Socket::UNIX;
use PageCamel::Helpers::ConfigLoader;
use Time::HiRes qw(sleep usleep);
use PageCamel::Helpers::Logo;
use Sys::Hostname;
use POSIX;

#use sigtrap qw(handler my_handler normal-signals stack-trace error-signals);
#
#sub my_handler {
#    print "Caught signal $!\n";
#    return;
#}

# For turning off SSL session cache
use Readonly;
Readonly my $SSL_SESS_CACHE_OFF => 0x0000;
Readonly my $timeout => 120; # 120 seconds timeout
Readonly my $blocksize => 1_000_000; # read at max 1MB per sysread

my $keepRunning = 1;

$SIG{USR1} = sub {
    #print "SIG USR1\n";
    return;
};

$SIG{PIPE} = sub {
    print "SIG PIPE\n";
    return;
};

$SIG{STOP} = sub {
    print "SIG STOP\n";
    return;
};

$SIG{INT} = sub {
    #print "SIGINT\n";
    $keepRunning = 0;
    return;
};

$SIG{TERM} = sub {
    #print "SIGTERM\n";
    $keepRunning = 0;
    return;
};


BEGIN {
    {
        # We need to add some extra function to IO::Socket::SSL, IO::Socket::UNIX and IO::Socket::IP
        # so we can track the client ID on all sockets
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)

        foreach my $dist (qw[IP SSL UNIX]) {
            my $distname = 'IO::Socket::' . $dist;
            *{$distname . "::_setClientID"} = sub {
                my ($self, $cid) = @_;

                ${*$self}{'__client_id'} = $cid; ## no critic (References::ProhibitDoubleSigils)
                return;
            };

            *{$distname . "::_getClientID"} = sub {
                my ($self) = @_;

                return ${*$self}{'__client_id'} || ''; ## no critic (References::ProhibitDoubleSigils)
            };
        }
    }

}


sub new {
    my ($class, $isDebugging, $configfile) = @_;
    my $self = bless {}, $class;
    
    $self->{isDebugging} = $isDebugging;
    $self->{configfile} = $configfile;
    
    croak("Config file $configfile not found!") unless(-f $configfile);

    if(0 && $isDebugging) {
        my @lines = `/usr/bin/who`;
        foreach my $line (@lines) {
            if($line =~ /\((.*)\)/) {
                my $debugip = $1;
                print "DEBUG MODE - LIMIT TO IP $debugip\n";
                $self->{debugip} = $debugip;
                last;
            }
        }
    }

    $self->init();
    
    return $self;
}

sub init {
    my ($self) = @_;
    
    print "Loading config file ", $self->{configfile}, "\n";
    my $config = LoadConfig($self->{configfile},
                        ForceArray => [ 'service', 'ip'],);
    
    $self->{config} = $config;

    my $hname = hostname;
    if(defined($config->{hosts}->{$hname})) {
        print "   Host-specific configuration for '$hname'\n";
        foreach my $keyname (keys %{$config->{hosts}->{$hname}}) {
            $config->{$keyname} = $config->{hosts}->{$hname}->{$keyname};
        }
    }
    
    my $APPNAME = $config->{appname};
    PageCamelLogo($APPNAME, $VERSION);
    print "Changing application name to '$APPNAME'\n\n";
    my $ps_appname = lc($APPNAME);
    $ps_appname =~ s/[^a-z0-9]+/_/gio;
    
    if(!-d '/run/lock/pagecamel') {
        mkdir '/run/lock/pagecamel';
        chmod 0755, '/run/lock/pagecamel';
    }
    
    my $weblockname = "/run/lock/pagecamel_" . $ps_appname . ".lock";

    if(-f $weblockname) {
        carp("LOCKFILE $weblockname ALREADY EXISTS!");
        carp("REMOVING LOCKFILE $weblockname!");
        unlink $weblockname;
    }

    # FIXME Add exclusive locked open for $weblockname

    $self->{ps_appname} = $ps_appname;
    $PROGRAM_NAME = $ps_appname . '_master';


    my @tcpsockets;
    my %usessl;
    foreach my $service (@{$config->{external_network}->{service}}) {
        if(!defined($service->{usessl})) {
            $service->{port} = 0;
        }
        print '** Service at port ', $service->{port}, ' does ', $service->{usessl} ? '' : 'NOT', " use SSL/TLS\n";
        foreach my $ip (@{$service->{bind_adresses}->{ip}}) {
            my $bindid = $ip . ':' . $service->{port};
            $usessl{$bindid} = $service->{usessl};
            my $tcp = IO::Socket::IP->new(
                    LocalHost => $ip,
                    LocalPort => $service->{port},
                    Listen => 1,
                    ReuseAddr => 1,
                    Proto => 'tcp',
                    Blocking => 0,
            ) or croak("Failed to bind: " . $ERRNO);
            #binmode($tcp, ':bytes');
            push @tcpsockets, $tcp;
            print "   Listening on ", $ip, ":, ", $service->{port}, "/tcp\n";
        }
    }
    $self->{tcpsockets} = \@tcpsockets;
    $self->{usessl} = \%usessl;
    
    return;
}

sub run {
    my ($self) = @_;

    my $ok = 0;
    eval {
        $self->handle_protocol();
        $ok = 1;
    };

    if($EVAL_ERROR) {
        print "EVAL ERROR: ", $EVAL_ERROR, "\n";
    } elsif(!$ok) {
        print "Something failed!\n";
    } else {
        print "Normal exit?????\n";
    }

    return;
}

sub handle_protocol {
    my ($self) = @_;

    my %clients;
    my @toremove;
    my $selector = IO::Select->new();

    while($keepRunning) {
        # Check for new clients
        foreach my $tcp (@{$self->{tcpsockets}}) {
            my $clientsocket = $tcp->accept;

            next unless(defined($clientsocket));
            $clientsocket->blocking(0);

            my $lhost = $clientsocket->sockhost();
            my $lport = $clientsocket->sockport();
            my $peerhost = $clientsocket->peerhost();
            my $peerport = $clientsocket->peerport();

            my $socketid = $lhost . ':' . $lport;
            my $clientid = $lhost . ':' . $lport . '/' . $peerhost . ':' . $peerport;

            #print "**** Connection $clientid \n";

            if(defined($self->{debugip})) {
                if($peerhost ne $self->{debugip}) {
                    #print "**** Debugging but connection not from debugip -> closing ****\n";
                    $clientsocket->close;
                    next;
                }
            }

            my $childcount = scalar keys %clients;
            if($childcount >= $self->{config}->{max_childs}) {
                #print "Too many children already!\n";
                $clientsocket->close;
                next;
            }

            my $selectedbackend = $self->{config}->{internal_socket};
            my $usessl = $self->{usessl}->{$socketid};

            if($usessl) {
                my $defaultdomain = $self->{config}->{sslconfig}->{ssldefaultdomain};
                my $encrypted;
                my $ok = 0;
                #print "BLI\n";
                eval {
                    $encrypted = IO::Socket::SSL->start_SSL($clientsocket,
                        SSL_server => 1,
                        SSL_key_file=>  $self->{config}->{sslconfig}->{ssldomains}->{$defaultdomain}->{sslkey},
                        SSL_cert_file=> $self->{config}->{sslconfig}->{ssldomains}->{$defaultdomain}->{sslcert},
                        SSL_cipher_list => $self->{config}->{sslconfig}->{sslciphers},
                        SSL_create_ctx_callback => sub {
                            my $ctx = shift;

                            #print "******************* CREATING NEW CONTEXT ********************\n";

                            # Enable workarounds for broken clients
                            Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL);

                            # Disable session resumption completely
                            Net::SSLeay::CTX_set_session_cache_mode($ctx, $SSL_SESS_CACHE_OFF);

                            # Disable session tickets
                            Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_NO_TICKET);

                            # Check requested server name
                            Net::SSLeay::CTX_set_tlsext_servername_callback($ctx, sub {
                                my $ssl = shift;
                                my $h = Net::SSLeay::get_servername($ssl);

                                if(!defined($h)) {
                                    #print "SSL: No Hostname given during SSL setup\n";
                                    return;
                                }

                                if(!defined($self->{config}->{sslconfig}->{ssldomains}->{$h})) {
                                    #print "SSL: Hostname $h not configured\n";
                                    #print Dumper($self->{config}->{sslconfig}->{ssldomains});
                                    return;
                                }
                                
                                if(defined($self->{config}->{sslconfig}->{ssldomains}->{$h}->{internal_socket})) {
                                    # This SSL connection uses a different backend
                                    $selectedbackend = $self->{config}->{sslconfig}->{ssldomains}->{$h}->{internal_socket};
                                }

                                if($h eq $self->{config}->{sslconfig}->{ssldefaultdomain}) {
                                    # Already the correct CTX setting, just return
                                    return;
                                }

                                #print "§§§§§§§§§§§§§§§§§§§§§§§   Requested Hostname: $h §§§\n";
                                my $newctx;
                                if(defined($self->{config}->{sslconfig}->{ssldomains}->{$h}->{ctx})) {
                                    $newctx = $self->{config}->{sslconfig}->{ssldomains}->{$h}->{ctx};
                                } else {
                                    $newctx = Net::SSLeay::CTX_new;
                                    if(!defined($newctx)) {
                                        #print "Can't create new SSL CTX\n";
                                        return;
                                    }
                                    Net::SSLeay::CTX_set_cipher_list($newctx, $self->{config}->{sslconfig}->{sslciphers});
                                    if(!Net::SSLeay::set_cert_and_key($newctx, $self->{config}->{sslconfig}->{ssldomains}->{$h}->{sslcert},
                                                                        $self->{config}->{sslconfig}->{ssldomains}->{$h}->{sslkey})) {
                                                                    #print "Can't set cert and key file\n";
                                        return;
                                    }
                                    $self->{config}->{sslconfig}->{ssldomains}->{$h}->{ctx} = $newctx;
                                }
                                Net::SSLeay::set_SSL_CTX($ssl, $newctx);
                            });

                            #    Prepared/tested for future ALPN needs (e.g. HTTP/2)
                            ## Advertise supported HTTP versions
                            #Net::SSLeay::CTX_set_alpn_select_cb($ctx, ['http/1.1', 'http/2.0']);
                        },
                    );
                    $ok = 1;
                };
                #print "BLA\n";
                if(!$ok || !defined($encrypted) || !$encrypted) {
                    #print "startSSL failed: ", $SSL_ERROR, "\n";
                    next;
                }
                #print "BLUB\n";
            }

            #print "FOO\n";
            my $backend = IO::Socket::UNIX->new(
                    Peer => $selectedbackend,
                    Type => SOCK_STREAM,
                    Blocking => 0,
            );
            #print "BAR\n";
            if(!defined($backend)) {
                warn("Failed to connect to backend: $ERRNO");
                next;
            }

            binmode($clientsocket);
            binmode($backend);
            #print "BAZ\n";

            $clientsocket->_setClientID('client#' . $clientid);
            $backend->_setClientID('backend#' . $clientid);
            #print "NOP\n";

            my %client = (
                clientsocket => $clientsocket,
                backendsocket => $backend,
                lhost => $lhost,
                lport => $lport,
                peerhost => $peerhost,
                peerport => $peerport,
                usessl => $usessl,
                toclient => '',
                tobackend => "PAGECAMEL $lhost $lport $peerhost $peerport $usessl $PID HTTP/1.1\r\n",
                removeat => time + $timeout,
                backendok => 1,
                clientok => 1,
            );
            $clients{$clientid} = \%client;

            $selector->add($clientsocket);
            $selector->add($backend);
            #print "NOR\n";
        }

        my @inclients = $selector->can_read(0.05);
        foreach my $clientsocket (@inclients) {
            #print "Can read from socket\n";
            my $tempid = $clientsocket->_getClientID();
            #print "   ID $tempid\n";

            my ($from, $clientid) = split/\#/, $tempid;

            next unless($clients{$clientid}->{$from . 'ok'});

            my $rawbuffer;
            my $readok = 0;
            eval {
                sysread($clientsocket, $rawbuffer, $blocksize);
                $readok = 1;
            };
            if(!$readok) {
                #print "Client socket $from read error $clientid\n";
                push @toremove, $clientid;
                next;
            }

            if(defined($rawbuffer) && length($rawbuffer)) {
                #print "READOK ", length($rawbuffer), "\n";
                if($from eq 'backend') {
                    $clients{$clientid}->{toclient} .= $rawbuffer;
                } else {
                    $clients{$clientid}->{tobackend} .= $rawbuffer;
                }
            } else {
                $clients{$clientid}->{$from . 'ok'} = 0;
                #print "READFAILED\n";
            }
        }

        # Write data to peers in as large chunks as possible
        foreach my $clientid (keys %clients) {
            # Write to backend
            if(length($clients{$clientid}->{tobackend})) {
                #print "Write to backend $clientid\n";
                my $written;
                eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                    #print "AAAA\n";
                    $written = syswrite($clients{$clientid}->{backendsocket}, $clients{$clientid}->{tobackend});
                    #print "BBBB\n";
                };
                #print "X\n";
                if($EVAL_ERROR) {
                    print "Backend write error: $EVAL_ERROR\n";
                    push @toremove, $clientid;
                    next;
                }
                if(!$clients{$clientid}->{backendsocket}->opened || $clients{$clientid}->{backendsocket}->error || ($ERRNO ne '' && !$ERRNO{EWOULDBLOCK})) {
                    print "webPrint write failure to backend: $ERRNO\n";
                    push @toremove, $clientid;
                    next;
                }
                #print "Y\n";

                if(defined($written) && $written) {
                    #print "Written $written bytes to backend\n";
                    if(length($clients{$clientid}->{tobackend}) == $written) {
                        $clients{$clientid}->{tobackend} = '';
                    } else {
                        $clients{$clientid}->{tobackend} = substr($clients{$clientid}->{tobackend}, $written);
                    }
                    $clients{$clientid}->{removeat} = time + $timeout; # Update timeout after sucessful write
                } else {
                    print "Failed to write to backend\n";
                }
            }

            # Write to client
            if(length($clients{$clientid}->{toclient})) {
                #print "Write to client $clientid\n";
                my $written;
                eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                    $written = syswrite($clients{$clientid}->{clientsocket}, $clients{$clientid}->{toclient});
                };
                if($EVAL_ERROR) {
                    #print "Frontend write error: $EVAL_ERROR\n";
                    push @toremove, $clientid;
                    next;
                }
                if(!$clients{$clientid}->{clientsocket}->opened || $clients{$clientid}->{clientsocket}->error || ($ERRNO ne '' && !$ERRNO{EWOULDBLOCK})) {
                    #print "webPrint write failure to client: $ERRNO\n";
                    push @toremove, $clientid;
                    next;
                }


                if(defined($written) && $written) {
                    #print "Written $written bytes to client\n";
                    if(length($clients{$clientid}->{toclient}) == $written) {
                        $clients{$clientid}->{toclient} = '';
                    } else {
                        $clients{$clientid}->{toclient} = substr($clients{$clientid}->{toclient}, $written);
                    }
                    $clients{$clientid}->{removeat} = time + $timeout; # Update timeout after sucessful write
                } else {
                    #print "Failed to write to client\n";
                }
            }
        }

        # Check for timeouts and closed connections
        foreach my $clientid (keys %clients) {
            if($clients{$clientid}->{removeat} < time) {
                #print "Timeout detected for $clientid\n";
                push @toremove, $clientid;
                next;
            }

            if(!$clients{$clientid}->{backendok} && !length($clients{$clientid}->{toclient})) {
                #print "Backend done for $clientid\n";
                push @toremove, $clientid;
                next;
            }

            if(!$clients{$clientid}->{clientok}) {
                #print "Client closed connection for $clientid\n";
                push @toremove, $clientid;
                next;
            }

        }

        while((my $clientid = shift @toremove)) {
            next unless(defined($clients{$clientid})); # Already removed?

            #print "Removing client $clientid\n";

            # Close backend socket
            my $backendcloseok = 0;
            eval {
                $clients{$clientid}->{backendsocket}->close();
                $backendcloseok = 1;
            };
            if(!$backendcloseok) {
                #print "Failed to close backend for $clientid\n";
            }

            # Close client socket
            my $clientcloseok = 0;
            eval {
                $clients{$clientid}->{clientsocket}->close();
                $clientcloseok = 1;
            };
            if(!$clientcloseok) {
                #print "Failed to close client for $clientid\n";
            }

            my $deleteok = 0;
            eval {
                delete($clients{$clientid});
                $deleteok = 1;
            };
            if(!$deleteok) {
                #print "DELETE FAILED $EVAL_ERROR\n";
            }

            #print "Client $clientid removed\n";
        }

        next;

        if(!(scalar keys %clients)) {
            # No clients to handle, let's sleep and try again later
            sleep(0.1);
            next;
        }

        my $datatosend = 0;
        foreach my $clientid (keys %clients) {
            if(length($clients{$clientid}->{tobackend}) || length($clients{$clientid}->{toclient})) {
                $datatosend = 1;
            }
        }
        if(!$datatosend) {
            # No data in output buffer, sleep a bit
            sleep(0.1);
            next;
        }

    }

    print "run() loop finished.\n";
    return;
}

1;
