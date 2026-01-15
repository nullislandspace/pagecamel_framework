package PageCamel::CMDLine::WebFrontend;
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

use IO::Socket::INET;
use IO::Socket::SSL;
use IO::Select;
use IO::Socket::UNIX;
use Socket qw(IPPROTO_TCP TCP_NODELAY SO_KEEPALIVE SOL_SOCKET);
use PageCamel::Helpers::ConfigLoader;
use Time::HiRes qw(sleep usleep time);
use PageCamel::Helpers::Logo;
use PageCamel::Helpers::WebPrint;
use PageCamel::Helpers::Mandant;
use PageCamel::Helpers::DateStrings;
use Sys::Hostname;
use POSIX;
use Errno qw();  # Load without importing - only needed for %! hash tying
use PageCamel::Helpers::FileSlurp qw(writeBinFile);
use PageCamel::Helpers::Logo590;

# For turning off SSL session cache
use Readonly;
Readonly my $SSL_SESS_CACHE_OFF => 0x0000;

$SIG{PIPE} = sub {
    print "SIG PIPE\n";
    return;
};

my $childcount = 0;
$SIG{CHLD} = \&REAPER;
sub REAPER {
    my $stiff;
    while (($stiff = waitpid(-1, &WNOHANG)) > 0) {
        #print "Child PID $stiff has gone the way of the Dodo\n";
        $childcount--;
    }
    $SIG{CHLD} = \&REAPER; # install *after* calling waitpid
    return;
}

sub new($class, $isDebugging, $configfile) {
    my $self = bless {}, $class;
    
    $self->{isDebugging} = $isDebugging;
    $self->{configfile} = $configfile;

    $self->{mandanth} = PageCamel::Helpers::Mandant->new();
    
    if(0 && $isDebugging) {
        my @lines = `/usr/bin/who`;
        foreach my $line (@lines) {
            if($line =~ /\((.*)\)/) {
                my $debugip = $1;
                print STDERR "DEBUG MODE - LIMIT TO IP $debugip\n";
                $self->{debugip} = $debugip;
                last;
            }
        }
    }


    $self->init();
    
    return $self;
}

sub init($self) {
    print "Loading config file ", $self->{configfile}, "\n";
    my $config = LoadConfig($self->{configfile},
                        ForceArray => [ 'service', 'ip'],);
    
    $self->{config} = $config;

    $self->{dynamicIP} = '';

    my $hname = hostname;
    if(defined($config->{hosts}->{$hname})) {
        print "   Host-specific configuration for '$hname'\n";
        foreach my $keyname (keys %{$config->{hosts}->{$hname}}) {
            $config->{$keyname} = $config->{hosts}->{$hname}->{$keyname};
        }
    }

    if(defined($ENV{PC_LOCALHOSTONLY}) && $ENV{PC_LOCALHOSTONLY}) {
        print "   PC_LOCALHOSTONLY mode active, 'forgetting' all usessl=1 services\n";
        my @newservices;
        foreach my $service (@{$config->{external_network}->{service}}) {
            if(defined($service->{usessl}) && $service->{usessl}) {
                next;
            }
            push @newservices, $service;
        }
        $config->{external_network}->{service} = \@newservices;
    }

    # Validate HTTP/2 configuration: HTTP/2 requires SSL/TLS
    foreach my $service (@{$config->{external_network}->{service}}) {
        if(!defined($service->{http2})) {
            $service->{http2} = 0;
        }

        if(defined($service->{http2}) && $service->{http2}) {
            if(!defined($service->{usessl}) || !$service->{usessl}) {
                print STDERR "HTTP/2 requires SSL/TLS! Disabling HTTP/2 on port $service->{port}\n";
                $service->{http2} = 0;
            }
        }
    }

    # Validate HTTP/3 configuration: HTTP/3 requires SSL/TLS
    foreach my $service (@{$config->{external_network}->{service}}) {
        if(!defined($service->{http3})) {
            $service->{http3} = 0;
        }

        if(defined($service->{http3}) && $service->{http3}) {
            if(!defined($service->{usessl}) || !$service->{usessl}) {
                print STDERR "HTTP/3 requires SSL/TLS! Disabling HTTP/3 on port $service->{port}\n";
                $service->{http3} = 0;
            }
        }
    }

    # Turn any comma-separated ip addresses into their own entry
    foreach my $service (@{$config->{external_network}->{service}}) {
        my @newips;
        foreach my $ip (@{$service->{bind_adresses}->{ip}}) {
            if($ip =~ /\,/) {
                push @newips, split/\,/, $ip;
            } elsif($ip eq 'DYNAMIC') {
                $self->{dynamicIP} = $self->_getLocalIPs();
                print "Activating dynamic IP Adresses: ", $self->{dynamicIP}, "\n";
                push @newips, split/\,/, $self->{dynamicIP};
                $self->{dynamicIPnextcheck} = time + 15;
            } else {
                push @newips, $ip;
            }
        }
        $service->{bind_adresses}->{ip} = \@newips;
    }

    my @hosts = keys %{$self->{config}->{sslconfig}->{ssldomains}};
    foreach my $host (@hosts) {
        print "  ... SSLDOMAIN $host ...\n";
        if($host =~ /^DUMMYTOKEN/) {
            my $newhostname = '' . $host;
            $newhostname =~ s/^DUMMYTOKEN//;
            print "       renaming domain $host to $newhostname...\n";
            $self->{config}->{sslconfig}->{ssldomains}->{$newhostname} = $self->{config}->{sslconfig}->{ssldomains}->{$host};
            delete $self->{config}->{sslconfig}->{ssldomains}->{$host};
        }
    }
    
    my $APPNAME = $config->{appname};
    PageCamelLogo($APPNAME, $VERSION);
    print "Changing application name to '$APPNAME'\n\n";
    my $ps_appname = lc($APPNAME);
    $ps_appname =~ s/[^a-z0-9]+/_/gio;

    if(!defined($self->{config}->{headertimeout})) {
        print STDERR "headertimeout not defined, setting it to 30 seconds\n";
        $self->{config}->{headertimeout} = 30;
    }
    
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


    my $hasssl = 0;
    my $hashttp3 = 0;
    my @tcpsockets;
    my @udpsockets;
    my %udpSocketInfo;  # Map socket to {ip, port, service}

    # Check if HTTP/3 XS modules are available
    my $http3Available = 0;
    eval {
        require PageCamel::XS::NGTCP2;
        require PageCamel::XS::NGHTTP3;
        require PageCamel::Protocol::HTTP3::Server;
        $http3Available = 1;
    };
    if(!$http3Available) {
        print "WARNING: HTTP/3 XS modules not available (not compiled or not in \@INC)\n";
        print "         HTTP/3 support will be disabled.\n";
        print "         Run 'make' in pagecamel_framework to compile XS modules.\n\n";
    }

    foreach my $service (@{$config->{external_network}->{service}}) {
        print '** Service at port ', $service->{port}, ' does ', $service->{usessl} ? '' : 'NOT', " use SSL/TLS\n";
        if($service->{usessl}) {
            $hasssl = 1;
        }
        if($service->{http3} && $http3Available) {
            $hashttp3 = 1;
            print '   HTTP/3 enabled on port ', $service->{port}, "\n";
        } elsif($service->{http3} && !$http3Available) {
            print '   HTTP/3 configured but XS modules not available - DISABLED\n';
        }
        foreach my $ip (@{$service->{bind_adresses}->{ip}}) {
            # Create TCP socket
            my $tcp = IO::Socket::IP->new(
                    LocalHost => $ip,
                    LocalPort => $service->{port},
                    Listen => ($config->{max_childs} || 128), # Queue size based on max_childs config
                    ReuseAddr => 1,
                    Proto => 'tcp',
            ) or croak("Failed to bind TCP: " . $ERRNO);
            push @tcpsockets, $tcp;
            print "   Listening on ", $ip, ":", $service->{port}, "/tcp\n";

            # Create UDP socket for HTTP/3 if enabled and XS modules available
            if($service->{http3} && $http3Available) {
                my $udp = IO::Socket::IP->new(
                        LocalHost => $ip,
                        LocalPort => $service->{port},
                        ReuseAddr => 1,
                        Proto => 'udp',
                ) or croak("Failed to bind UDP: " . $ERRNO);
                $udp->blocking(0);
                push @udpsockets, $udp;
                $udpSocketInfo{$udp} = {
                    ip      => $ip,
                    port    => $service->{port},
                    service => $service,
                };
                print "   Listening on ", $ip, ":", $service->{port}, "/udp (HTTP/3)\n";
            }
        }
    }
    my $select = IO::Select->new(@tcpsockets, @udpsockets);
    $self->{select} = $select;
    $self->{tcpsockets} = \@tcpsockets;
    $self->{udpsockets} = \@udpsockets;
    $self->{udpSocketInfo} = \%udpSocketInfo;
    $self->{hasssl} = $hasssl;
    $self->{hashttp3} = $hashttp3;

    # Initialize QUIC/HTTP3 state if HTTP/3 is enabled
    if($hashttp3) {
        $self->{quicConnections} = {};  # Connection ID -> Connection object
        $self->{quicConnectionsByAddr} = {};  # "ip:port" -> Connection object
    }

    if($hasssl) {
        if(!defined($self->{config}->{sslconfig}->{ssldefaultdomain})) {
            #print Dumper($self->{config}->{sslconfig});
            croak("ssldefaultdomain not set!");
        }
        my $defaultdomain = $self->{config}->{sslconfig}->{ssldefaultdomain};
        print "Default domain: $defaultdomain\n";
        my $ok = 1;
        if(!defined($self->{config}->{sslconfig}->{ssldomains}->{$defaultdomain}) ||
            !defined($self->{config}->{sslconfig}->{ssldomains}->{$defaultdomain}->{sslcert}) ||
            !defined($self->{config}->{sslconfig}->{ssldomains}->{$defaultdomain}->{sslkey})) {
            print STDERR "ssl default domain not fully configured!\n";
            $ok = 0;
        } else {
            if(!-f $self->{config}->{sslconfig}->{ssldomains}->{$defaultdomain}->{sslcert}) {
                print STDERR "File not found: ", $self->{config}->{sslconfig}->{ssldomains}->{$defaultdomain}->{sslcert}, "\n";
                $ok = 0;
            }
            if(!-f $self->{config}->{sslconfig}->{ssldomains}->{$defaultdomain}->{sslkey}) {
                print STDERR "File not found: ", $self->{config}->{sslconfig}->{ssldomains}->{$defaultdomain}->{sslkey}, "\n";
                $ok = 0;
            }
        }

        my @removedomains;
        foreach my $domain (sort keys %{$self->{config}->{sslconfig}->{ssldomains}}) {
            my $domainok = 1;
            if(!defined($self->{config}->{sslconfig}->{ssldomains}->{$domain}->{sslcert}) ||
                !defined($self->{config}->{sslconfig}->{ssldomains}->{$domain}->{sslkey})) {
                print STDERR "ssl domain $domain not fully configured!\n";
                $ok = 0;
                next;
            }
            if(!-f $self->{config}->{sslconfig}->{ssldomains}->{$domain}->{sslcert}) {
                print STDERR "Warning: File not found: " . $self->{config}->{sslconfig}->{ssldomains}->{$domain}->{sslcert}, "\n";
                $domainok = 0;
            }
            if(!-f $self->{config}->{sslconfig}->{ssldomains}->{$defaultdomain}->{sslkey}) {
                print STDERR "Warning: File not found: " . $self->{config}->{sslconfig}->{ssldomains}->{$domain}->{sslkey}, "\n";
                $domainok = 0;
            }

            if(!$domainok) {
                push @removedomains, $domain;
            }
        }

        foreach my $domain (@removedomains) {
            print STDERR "WARNING: Disabling domain $domain due to missing SSL files!\n";
            delete $self->{config}->{sslconfig}->{ssldomains}->{$domain};
        }

        if(!$ok) {
            croak("Startup aborted due to configuration errors!");
        }
    } else {
        print "Insecure mode! Completely disabling ALL SSL handling!\n";
    }
        
    
    return;
}

sub run($self) {
    # Generate SSL session ticket key once (shared by all forked children)
    # Key format: 16 bytes name + 32 bytes key (16 AES + 16 HMAC)
    if($self->{hasssl}) {
        open(my $urandom, '<:raw', '/dev/urandom') or croak("Cannot open /dev/urandom: $ERRNO");
        read($urandom, $self->{ssl_ticket_key_name}, 16) == 16 or croak("Failed to read key name from /dev/urandom");
        read($urandom, $self->{ssl_ticket_key}, 32) == 32 or croak("Failed to read key from /dev/urandom");
        close($urandom);
    }

    # Build lookup hash for UDP sockets
    my %isUdpSocket;
    foreach my $udp (@{$self->{udpsockets}}) {
        $isUdpSocket{$udp} = 1;
    }

    # Fork dedicated HTTP/3 handler process if HTTP/3 is enabled
    # This child process owns all UDP sockets and handles all QUIC/HTTP/3 traffic
    if($self->{hashttp3} && @{$self->{udpsockets}}) {
        my $http3Pid = fork();
        if(!defined($http3Pid)) {
            croak("Failed to fork HTTP/3 handler process: $ERRNO");
        } elsif($http3Pid == 0) {
            # Child process - HTTP/3 handler
            $PROGRAM_NAME = $self->{ps_appname} . '_http3';

            # Close TCP sockets (parent handles those)
            foreach my $tcpSocket (@{$self->{sockets}}) {
                $tcpSocket->close();
            }

            # Run HTTP/3 event loop (never returns)
            $self->runHTTP3Handler();
            exit(0);
        } else {
            # Parent process - close UDP sockets (child owns them)
            print getISODate(), " Forked HTTP/3 handler process (PID $http3Pid)\n";
            $self->{http3Pid} = $http3Pid;

            foreach my $udpSocket (@{$self->{udpsockets}}) {
                $self->{select}->remove($udpSocket);
                $udpSocket->close();
            }
            $self->{udpsockets} = [];
            %isUdpSocket = ();
        }
    }

    while(1) {
        # Parent process handles TCP connections only (HTTP/1.1 and HTTP/2)
        # HTTP/3/QUIC is handled by the dedicated child process
        my $selectTimeout = 0.1;  # Default 100ms

        while((my @connections = $self->{select}->can_read($selectTimeout))) {
            # After first iteration, use short timeout to drain any pending connections
            $selectTimeout = 0.001;
            foreach my $connection (@connections) {
                # TCP connection handling (HTTP/1.1 and HTTP/2)
                my $client = $connection->accept;
                next unless(defined($client));  # Accept can fail

                # Set socket options for lower latency and dead connection detection
                setsockopt($client, IPPROTO_TCP, TCP_NODELAY, 1);  # Disable Nagle's algorithm
                setsockopt($client, SOL_SOCKET, SO_KEEPALIVE, 1);  # Enable TCP keepalive

                my $peerhost = $client->peerhost();
                my $peerport = $client->peerport();
                my $hostip = $client->sockhost();
                my $hostport = $client->sockport();
                #if(1 && $peerhost ne '127.0.0.1' && $peerhost ne '178.189.98.74') {
                if(0 && $peerhost ne '127.0.0.1' && $peerhost ne '192.164.14.58') {
                    $client->close;
                    next;
                }
                print getISODate(), " Connection from ", $peerhost, ":", $peerport, " to ", $hostip, ":", $hostport, "   \n";

                if(defined($self->{debugip})) {
                    if($peerhost ne $self->{debugip}) {
                        $client->close;
                        next;
                    }
                }

                if($childcount >= $self->{config}->{max_childs}) {
                    #print "Too many children already!\n";
                    $client->close;
                    next;
                }

                my $childpid = fork();
                if(!defined($childpid)) {
                    #print "FORK FAILED!\n";
                    $client->close;
                    next;
                } elsif($childpid == 0) {
                    # Child
                    $PROGRAM_NAME = $self->{ps_appname};
                    $self->handleClient($client);
                    #print "Child PID $PID is done, exiting...\n";
                    $self->endprogram();
                } else {
                    # Parent
                    $childcount++;
                    next;
                }
            }
        }

        # Note: QUIC/HTTP/3 is handled by dedicated child process (forked above)

        if($self->{dynamicIP} ne '') {
            if($self->{dynamicIPnextcheck} < time) {
                my $newips = $self->_getLocalIPs();
                if($newips ne $self->{dynamicIP}) {
                    print STDERR "IP ADRESSES HAVE CHANGED: ", $self->{dynamicIP}, ' --> ', $newips, "\n";
                    print STDERR "     *** RESTARTING SERVICE ***\n";
                    $self->endprogram();
                }
                $self->{dynamicIPnextcheck} = time + 15;
            }
        }
    }

    print "run() loop finished.\n";
    return;
}

sub handleClient($self, $client) {
    my $sigpipeseen = 0;
    my $sigpipehandled = 0;

    $SIG{PIPE} = sub {
        #print "SIG PIPE (client)\n";
        $sigpipeseen++;
        return;
    };
    
    my $evalok = 0;
    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)

        my $finishcountdown = 0;
        # Backend connection closure is detected via socket state (sysread returning 0)
        # No need for USR1 signal - socket state detection is more reliable

        #print "Doing some network stuff in child PID $PID\n";

        my $lhost = $client->sockhost();
        my $lport = $client->sockport();
        my $peerhost = $client->peerhost();
        my $peerport = $client->peerport();

        my $usessl = 0;
        my $http2 = 0;
        my $http3 = 0;
        my $selectedbackend = $self->{config}->{internal_socket};

        # Check if we need to use SSL and/or HTTP/2/HTTP/3
        foreach my $service (@{$self->{config}->{external_network}->{service}}) {
            # Search for the correct service
            if($service->{port} == $lport) {
                # Now check the IP address
                foreach my $ip (@{$service->{bind_adresses}->{ip}}) {
                    if($ip eq $lhost) {
                        # Found it
                        $usessl = $service->{usessl};
                        $http2 = $service->{http2};
                        $http3 = $service->{http3};
                    }
                }
            }
        }

        my $headertimeout = $self->{config}->{headertimeout};
        my $endtime = time + $headertimeout;
        if($usessl) {
            # Pre-check: wait for client to send TLS ClientHello
            # This filters out port scanners that connect but send nothing
            my $precheck = IO::Select->new($client);
            if(!$precheck->can_read(5)) {
                # No data received within 5 seconds - likely port scanner, close silently
                $client->close;
                $self->endprogram();
            }

            my $defaultdomain = $self->{config}->{sslconfig}->{ssldefaultdomain};
            my $encrypted;
            my $ok = 0;
            eval {
                # Suppress "uninitialized value" warnings from Net::SSLeay during malformed handshakes
                local $SIG{__WARN__} = sub {
                    my $msg = shift;
                    return if $msg =~ /uninitialized.*IO\/Socket\/SSL\.pm/;
                    carp $msg;
                };
                #print STDERR "SSL connecting\n";
                $encrypted = IO::Socket::SSL->start_SSL($client,
                    Timeout => $headertimeout,
                    SSL_server => 1,
                    SSL_key_file=>  $self->{config}->{sslconfig}->{ssldomains}->{$defaultdomain}->{sslkey},
                    SSL_cert_file=> $self->{config}->{sslconfig}->{ssldomains}->{$defaultdomain}->{sslcert},
                    SSL_cipher_list => $self->{config}->{sslconfig}->{sslciphers},
                    SSL_create_ctx_callback => sub {
                        my $ctx = shift;

                        #print STDERR "******************* CREATING NEW CONTEXT ********************\n";

                        # Enable workarounds for broken clients
                        Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL);

                        # Enable SSL session tickets with shared key (for session resumption across forks)
                        if(defined($self->{ssl_ticket_key}) && defined($self->{ssl_ticket_key_name})) {
                            my $ticket_data = [$self->{ssl_ticket_key}, $self->{ssl_ticket_key_name}];
                            Net::SSLeay::CTX_set_tlsext_ticket_getkey_cb($ctx, sub {
                                my ($data, $name) = @_;
                                my ($ticket_key, $ticket_key_name) = @{$data};
                                # If no name given, return current key for new ticket
                                return ($ticket_key, $ticket_key_name) if !defined($name);
                                # If name matches our key, return it
                                return ($ticket_key, $ticket_key_name) if $name eq $ticket_key_name;
                                # Unknown key name - return current key (will trigger ticket renewal)
                                return ($ticket_key, $ticket_key_name);
                            }, $ticket_data);
                        }

                        # Set session timeout (5 minutes)
                        eval { Net::SSLeay::CTX_set_timeout($ctx, 300); };

                        # Load certificate chain
                        my $ssldefaultdomain = $self->{config}->{sslconfig}->{ssldefaultdomain};
                        Net::SSLeay::CTX_use_certificate_chain_file($ctx, $self->{config}->{sslconfig}->{ssldomains}->{$ssldefaultdomain}->{sslcert});

                        # Check requested server name
                        Net::SSLeay::CTX_set_tlsext_servername_callback($ctx, sub {
                            my $ssl = shift;
                            my $h = Net::SSLeay::get_servername($ssl);

                            if(!defined($h)) {
                                #print STDERR "SSL: No Hostname given during SSL setup\n";
                                return;
                            }

                            if(!defined($self->{config}->{sslconfig}->{ssldomains}->{$h})) {
                                #print STDERR "SSL: Hostname $h not configured\n";
                                #print STDERR Dumper($self->{config}->{sslconfig}->{ssldomains});
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

                            #print STDERR "§§§§§§§§§§§§§§§§§§§§§§§   Requested Hostname: $h §§§\n";
                            my $newctx;
                            if(defined($self->{config}->{sslconfig}->{ssldomains}->{$h}->{ctx})) {
                                $newctx = $self->{config}->{sslconfig}->{ssldomains}->{$h}->{ctx};
                            } else {
                                $newctx = Net::SSLeay::CTX_new or croak("Can't create new SSL CTX");
                                Net::SSLeay::CTX_set_cipher_list($newctx, $self->{config}->{sslconfig}->{sslciphers});
                                Net::SSLeay::set_cert_and_key($newctx, $self->{config}->{sslconfig}->{ssldomains}->{$h}->{sslcert},
                                                                    $self->{config}->{sslconfig}->{ssldomains}->{$h}->{sslkey})
                                        or croak("Can't set cert and key file");
                                Net::SSLeay::CTX_use_certificate_chain_file($newctx, $self->{config}->{sslconfig}->{ssldomains}->{$h}->{sslcert});
                                # Set shared ticket key for session resumption
                                if(defined($self->{ssl_ticket_key}) && defined($self->{ssl_ticket_key_name})) {
                                    my $ticket_data = [$self->{ssl_ticket_key}, $self->{ssl_ticket_key_name}];
                                    Net::SSLeay::CTX_set_tlsext_ticket_getkey_cb($newctx, sub {
                                        my ($data, $name) = @_;
                                        my ($ticket_key, $ticket_key_name) = @{$data};
                                        return ($ticket_key, $ticket_key_name) if !defined($name);
                                        return ($ticket_key, $ticket_key_name) if $name eq $ticket_key_name;
                                        return ($ticket_key, $ticket_key_name);
                                    }, $ticket_data);
                                }
                                eval { Net::SSLeay::CTX_set_timeout($newctx, 300); };
                                # Set ALPN callback on SNI-switched context for HTTP/2
                                if($http2) {
                                    Net::SSLeay::CTX_set_alpn_select_cb($newctx, sub {
                                        my ($ssl, $protocols) = @_;
                                        foreach my $proto (@{$protocols}) {
                                            if($proto eq 'h2') {
                                                return 'h2';
                                            }
                                        }
                                        return 'http/1.1';
                                    });
                                }
                                #print STDERR "Cert: ", $self->{config}->{sslconfig}->{ssldomains}->{$h}->{sslcert}, " Key: ", $self->{config}->{sslconfig}->{ssldomains}->{$h}->{sslkey}, "\n";
                                $self->{config}->{sslconfig}->{ssldomains}->{$h}->{ctx} = $newctx;
                            }
                            Net::SSLeay::set_SSL_CTX($ssl, $newctx);
                        });

                        # Set ALPN callback to negotiate HTTP/2 or HTTP/1.1
                        if($http2) {
                            Net::SSLeay::CTX_set_alpn_select_cb($ctx, sub {
                                my ($ssl, $protocols) = @_;
                                # Prefer h2 if client offers it
                                foreach my $proto (@{$protocols}) {
                                    if($proto eq 'h2') {
                                        return 'h2';
                                    }
                                }
                                return 'http/1.1';
                            });
                        }
                    },
                );
                $ok = 1;
            };
            #print STDERR "SSL connected\n";

            if(!$ok) {
                print STDERR "EVAL ERROR: ", $EVAL_ERROR, "\n";
                $self->endprogram();
            } elsif(!$ok || !defined($encrypted) || !$encrypted) {
                print STDERR getISODate(), " startSSL failed: ", $SSL_ERROR, "\n";
                $self->endprogram();
            }

            # Check if HTTP/2 was negotiated via ALPN
            if($http2) {
                my $negotiatedProtocol = $encrypted->alpn_selected() // 'http/1.1';
                if($negotiatedProtocol eq 'h2') {
                    $self->handleHTTP2Client($encrypted, $lhost, $lport, $peerhost, $peerport, $selectedbackend);
                    $self->endprogram();
                }
            }
        }
        binmode($client);

        # Read all HTTP headers of the first request on this connection.
        # We don't do a full parsing and validation here (that's the duty of the backend).
        # We only grab them to
        #    a) make sure that the user agent is actually sending a request over the connection before starting a backend
        #    b) check if a certain cookie is set if "mandant" capability is enabled and re-select the backend


        # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        #      WARNING: IO::Socket::SSL does not work if you sysread single bytes - you always have to read blocks
        # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

        my @headers;
        my $headererrors = 0;
        local $INPUT_RECORD_SEPARATOR = undef;
        my $select = IO::Select->new($client);
        my $overhead = "PAGECAMEL $lhost $lport $peerhost $peerport $usessl $PID HTTP/1.1\r\n";
        my $headerevalok = 0;

        eval {
            #print STDERR "Start header reading...\n";

            while($overhead !~ /\r\n\r\n/) {
                # Calculate remaining timeout for this iteration
                my $remaining = $endtime - time;
                if($remaining <= 0) {
                    $headererrors = 1;
                    last;
                }

                my $buf = undef;
                my @connections = $select->can_read($remaining);

                # Handle EINTR - signal interrupted the call, just retry
                if(!@connections && $ERRNO{EINTR}) {
                    next;
                }

                foreach my $socket (@connections) {
                    sysread($socket, $buf, 10_000_000);
                }
                if(!defined($buf) || !length($buf)) {
                    # No data available yet, loop will retry with updated timeout
                    next;
                }
                $overhead .= $buf;
            }
            $headerevalok = 1;
        };

        if(!$headerevalok) {
            #print STDERR "Header read timeout!\n";
            $headererrors = 1;
        }

        my $rawheaders = '' . $overhead;

        if(!$headererrors) {
            @headers = $self->parseheaders($rawheaders);
        }

        if(!$headererrors && $self->{mandanth}->isActive()) {
            # Check for Mandant cookie
            my %cookies;
            foreach my $header (@headers) {
                if($header =~ /^Cookie\:\ (.+)$/i) {
                    my @parts = split/\;/, $1;
                    foreach my $part (@parts) {
                        $part =~ s/^\s+//g;
                        $part =~ s/\s+$//g;
                        next if($part !~ /\=/);
                        my ($cname, $cval) = split/\=/, $part;
                        if(defined($cname) && $cname ne '' && defined($cval) && $cval ne '') {
                            $cookies{$cname} = $cval;
                        }
                    }
                }
            }

            if(defined($cookies{Mandant}) && $cookies{Mandant} ne '') {
                my $shortname = $cookies{Mandant};
                if(!$self->{mandanth}->isValidMandant($shortname)) {
                    my $defaultmandant = $self->{mandanth}->getDefaultMandant();
                    print STDERR "Unknown Mandant ", $shortname, ", using default mandant ", $defaultmandant, " instead\n";
                    $shortname = $defaultmandant;
                }
                my $newselectedbackend = $self->{mandanth}->getBackend($shortname);
                if(defined($newselectedbackend)) {
                    print STDERR "Using backend ", $newselectedbackend, " for mandant ", $shortname, "\n";
                    $selectedbackend = $newselectedbackend;
                } else {
                    print STDERR "Mandant config error? Ignoring Mandant config!\n";
                }
            }
        }

        my $backend;
        if(!$headererrors) {
            $backend = IO::Socket::UNIX->new(
                    Peer => $selectedbackend,
                    Type => SOCK_STREAM,
                    Timeout => 15,
                );
        }
                
        # Try to send error message to client that we couldn't reach the backend webserver
        if(!defined($backend)) {
            my $error = $ERRNO;
            my $reply;
            if($headererrors) {
                $reply = $self->get408();
            } else {
                $reply = $self->get590();
            }

            my $timeout = time + 10;
            while(length($reply) && time < $timeout) {
                my $written = 0;
                eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                    $written = syswrite($client, $reply);
                };
                if($EVAL_ERROR) {
                    print STDERR "Write error: $EVAL_ERROR\n";
                    $self->endprogram();
                }
                if(defined($written) && $written) {
                    $reply = substr($reply, $written);
                }
            }
            sleep(2);
            eval {
                close $client;
            };
            print STDERR getISODate() . " HTTP/1.1: Failed to connect to backend $selectedbackend: $error\n";
            $self->endprogram();
        }

        binmode($backend);
        $select->add($backend);

        my $done = 0;
        my $toclientbuffer = '';
        my $tobackendbuffer = $overhead;
        my $debugincapture = '';
        my $debugoutcapture = '';
        my $clientdisconnect = 0;
        my $backenddisconnect = 0;
        my $altSvcInjected = 0;  # Track if Alt-Svc header has been injected
        #print STDERR "Handling client...\n";
        while(!$done) {
            if($sigpipeseen > $sigpipehandled) {
                sleep(0.05);
                print STDERR "Sleep 0.05\n";
                $sigpipehandled++;
            }
            if($sigpipehandled > 200) {
                print STDERR "Too many SIGPIPEs, bailing out.\n";
                #print STDERR "*** Debug IN data: \n", $debugincapture, "\n";
                #print STDERR "*** Debug OUT data: \n", $debugoutcapture, "\n";
                $done = 1;
            }
            my $totalread = 0;
            my $rawbuffer;

            # Wait long if we currently have nothing to send, only wait a very short time for new data if we already got
            # something in out output buffers
            my $waittime = 0.1;
            if(length($toclientbuffer) || length($tobackendbuffer)) {
                $waittime = 0.001;
            }
            
            $ERRNO = 0;
            my @connections = $select->can_read($waittime);
            # Handle EINTR (signal interrupted call) - just continue, not an error
            if(!@connections && $ERRNO{EINTR}) {
                next;
            }
            if($ERRNO ne '' && !$ERRNO{EINTR}) {
                print STDERR "select error: $ERRNO\n";
            }
            my $max_buffer_size = 50_000_000;  # 50MB buffer limit to prevent memory exhaustion
            foreach my $connection (@connections) {
                # Skip reading if destination buffer is already too large (applies back-pressure)
                if(ref $connection eq 'IO::Socket::UNIX') {
                    next if length($toclientbuffer) >= $max_buffer_size;
                } else {
                    next if length($tobackendbuffer) >= $max_buffer_size;
                }

                sysread($connection, $rawbuffer, 10_000_000); # Read at most 10MB at a time
                if(!length($rawbuffer)) {
                    # can_read active but no data.
                    # this usually means the connection has closed
                    if(ref $connection eq 'IO::Socket::UNIX') {
                        $backenddisconnect = 1;
                    } else {
                        $clientdisconnect = 1;
                    }
                } else {
                    if(ref $connection eq 'IO::Socket::UNIX') {
                        # data FROM the backend
                        $toclientbuffer .= $rawbuffer;
                        if(length($debugoutcapture) < 1000) {
                            $debugoutcapture .= $rawbuffer;
                        }

                        # Inject Alt-Svc header for HTTP/3 advertisement (only once, only if HTTP/3 enabled)
                        if($http3 && !$altSvcInjected) {
                            my $headerEndPos = index($toclientbuffer, "\r\n\r\n");
                            if($headerEndPos >= 0) {
                                # Found end of headers - inject Alt-Svc after the first \r\n (after last header)
                                my $altSvcHeader = "Alt-Svc: h3=\":" . $lport . "\"; ma=86400\r\n";
                                substr($toclientbuffer, $headerEndPos + 2, 0, $altSvcHeader);
                                $altSvcInjected = 1;
                            }
                        }
                    } else {
                        $tobackendbuffer .= $rawbuffer;
                        if(length($debugincapture) < 1000) {
                            $debugincapture .= $rawbuffer;
                        }
                    }
                }
            }


            my $blocksize = 16_384; # Blocksize limit of SSL/TLS lib, it seems
            my $loopcount = int(10_000_000 / 16_384); # Write at max ~10MB in one loop

            # Don't write to client until Alt-Svc has been injected (or we know it's not needed)
            # This prevents sending partial headers before we can inject the Alt-Svc header
            if($http3 && !$altSvcInjected && index($toclientbuffer, "\r\n\r\n") < 0) {
                # Headers not complete yet, hold back writes
                goto SKIP_CLIENT_WRITE;
            }

            my $sendcount = $loopcount;
            my $client_offset = 0;  # Track offset to avoid repeated substr copies
            while($sendcount) {
                my $remaining = length($toclientbuffer) - $client_offset;
                if($remaining > 0 && !$clientdisconnect) {
                    my $written;
                    my $towrite = $remaining < $blocksize ? $remaining : $blocksize;

                    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                        $written = syswrite($client, $toclientbuffer, $towrite, $client_offset);
                    };
                    if($EVAL_ERROR) {
                        print STDERR "Write error: $EVAL_ERROR\n";
                    } else {
                        if($finishcountdown) {
                            # We are in countdown but could still send data to client. Reset countdown
                            $finishcountdown = time + 20;
                        }
                    }
                    if(defined($written) && $written) {
                        #print STDERR "< Clientbuffer ", length($toclientbuffer), " written ", $written, "\n";
                        $client_offset += $written;
                    } else {
                        #print STDERR "No data written to client\n";
                        last;
                    }
                } else {
                    last;
                }
                $sendcount--;
            }
            # Single substr after loop to remove all written data
            if($client_offset > 0) {
                $toclientbuffer = substr($toclientbuffer, $client_offset);
            }

            SKIP_CLIENT_WRITE:
            $sendcount = $loopcount;
            my $backend_offset = 0;  # Track offset to avoid repeated substr copies
            while($sendcount) {
                my $remaining = length($tobackendbuffer) - $backend_offset;
                if($remaining > 0 && !$backenddisconnect) {
                    my $written;
                    my $towrite = $remaining < $blocksize ? $remaining : $blocksize;

                    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                        $written = syswrite($backend, $tobackendbuffer, $towrite, $backend_offset);
                    };
                    if($EVAL_ERROR) {
                        print STDERR "Write error: $EVAL_ERROR\n";
                    } else {
                        if($finishcountdown) {
                            # We are in countdown but could still send data to backend. Reset countdown
                            $finishcountdown = time + 20;
                        }
                    }
                    if(defined($written) && $written) {
                        #print STDERR "> Backendbuffer ", length($tobackendbuffer), " written ", $written, "\n";
                        $backend_offset += $written;

                        # Reset SIGPIPE counter whenever we have success writing to the backend
                        $sigpipeseen = 0;
                        $sigpipehandled = 0;
                    } else {
                        #print STDERR "No data written to backend\n";
                        last;
                    }
                } else {
                    last;
                }
                $sendcount--;
            }
            # Single substr after loop to remove all written data
            if($backend_offset > 0) {
                $tobackendbuffer = substr($tobackendbuffer, $backend_offset);
            }

            if($clientdisconnect) {
                # print STDERR "Client disconnect detected!\n";
                # Client has gone, no sense in continuing
                $done = 1;
            }

            if(!$finishcountdown && $backenddisconnect) {
                if(!length($toclientbuffer)) {
                    # Communication done
                    $done = 1;
                } else {
                    # Start a 20 second countdown for sending remaining data to client
                    $finishcountdown = time + 20;
                }
            }

            if($finishcountdown > 0) {
                if(!length($toclientbuffer)) {
                    #print STDERR "Sending remaining data to client done\n";
                    $done = 1;
                } elsif($finishcountdown <= time) {
                    #print STDERR "Finish countdown done\n";
                    $done = 1;
                } else {
                    #print STDERR "Countdown remaining: ", $finishcountdown - time, " / Bytes remaining: ", length($toclientbuffer), "\n";
                    sleep(0.05);
                    print STDERR "Sleep# 0.05\n";
                }
            }
            
        }
        
        #print "Shutting down child PID $PID\n";
    
        eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
            close $backend;
        };
        eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
            close $client;
        };

        $evalok = 1;
    };

    if(!$evalok) {
        print STDERR "EVAL ERROR: ", $EVAL_ERROR, "\n";
    }

    return;

}

sub handleHTTP2Client($self, $client, $lhost, $lport, $peerhost, $peerport, $selectedbackend) {
    require PageCamel::CMDLine::WebFrontend::HTTP2Handler;

    # Check if HTTP/3 is enabled on this port for Alt-Svc advertisement
    my $http3Port;
    foreach my $service (@{$self->{config}->{external_network}->{service}}) {
        if($service->{port} == $lport && $service->{http3}) {
            $http3Port = $lport;
            last;
        }
    }

    my $handler = PageCamel::CMDLine::WebFrontend::HTTP2Handler->new(
        clientSocket      => $client,
        backendSocketPath => $selectedbackend,
        pagecamelInfo     => {
            lhost    => $lhost,
            lport    => $lport,
            peerhost => $peerhost,
            peerport => $peerport,
            usessl   => 1,
            pid      => $PID,
        },
        errorPage590Html  => $self->_get590Html(),
        http3Port         => $http3Port,
    );

    $handler->run();

    return;
}

sub runHTTP3Handler($self) {
    # Dedicated HTTP/3 handler process event loop
    # This runs in a forked child process and handles all QUIC/HTTP/3 traffic

    print getISODate(), " HTTP/3 handler process starting\n";

    # Initialize QUIC connection tracking
    $self->{quicConnections} = {};

    # Build IO::Select for UDP sockets
    my $udpSelect = IO::Select->new();
    foreach my $udpSocket (@{$self->{udpsockets}}) {
        $udpSelect->add($udpSocket);
    }

    # Build UDP socket info lookup
    # (Already populated in _init_sockets)

    # Main event loop
    while(1) {
        # Calculate select timeout from QUIC connection expiry times
        my $selectTimeout = 0.001;  # Default 1ms (reduced for HTTP/3 throughput)
        if(keys %{$self->{quicConnections}}) {
            my $now = PageCamel::XS::NGTCP2::timestamp();
            my $minExpiry = undef;
            my %seen;
            foreach my $connId (keys %{$self->{quicConnections}}) {
                my $quicConn = $self->{quicConnections}->{$connId};
                next unless(defined($quicConn));
                my $connPtr = "$quicConn";
                next if($seen{$connPtr}++);
                my $expiry = $quicConn->get_expiry();
                if(!defined($minExpiry) || $expiry < $minExpiry) {
                    $minExpiry = $expiry;
                }
            }
            if(defined($minExpiry)) {
                if($minExpiry <= $now) {
                    $selectTimeout = 0.001;
                } else {
                    my $timeoutNs = $minExpiry - $now;
                    $selectTimeout = $timeoutNs / 1_000_000_000;
                    $selectTimeout = 0.01 if($selectTimeout > 0.01);  # Max 10ms for HTTP/3
                    $selectTimeout = 0.0001 if($selectTimeout < 0.0001);  # Min 100us
                }
            }
        }

        # Wait for UDP packets or timeout
        $ERRNO = 0;
        my @readable = $udpSelect->can_read($selectTimeout);

        # Handle EINTR
        if(!@readable && $ERRNO{EINTR}) {
            next;
        }

        # Process incoming UDP packets
        foreach my $udpSocket (@readable) {
            $self->handleQUICPacket($udpSocket);
        }

        # Handle QUIC timeouts and send packets
        $self->handleQUICTimeouts();

        # Flush any pending UDP packets that couldn't be sent earlier
        $self->flushPendingUdpPackets();

        # Process backend I/O for all HTTP/3 connections
        $self->handleHTTP3Backends();

        # Cleanup closed connections
        $self->cleanupClosedQUICConnections();
    }
}

sub cleanupClosedQUICConnections($self) {
    # Remove connections that have finished draining
    my @toRemove;
    my %seen;

    foreach my $connId (keys %{$self->{quicConnections}}) {
        my $quicConn = $self->{quicConnections}->{$connId};
        next unless(defined($quicConn));

        my $connPtr = "$quicConn";
        next if($seen{$connPtr}++);

        if($quicConn->is_closed()) {
            # Connection is fully closed, cleanup
            my $handler = $quicConn->{_http3Handler};
            my $bytesSent = $handler ? ($handler->{streamBytesSent}->{0} // 0) : 0;
            print STDERR getISODate() . " DEBUG cleanupClosedQUICConnections: closing connId=" . unpack('H*', $connId) . " bytesSent=$bytesSent\n";
            $self->cleanupQUICConnection($quicConn);
            push @toRemove, $connId;
        }
    }

    # Remove from hash after iteration
    foreach my $connId (@toRemove) {
        delete $self->{quicConnections}->{$connId};
    }
}

sub processIncomingUdpNonBlocking($self, $udpSocket, $quicConn) {
    # Non-blocking check for incoming UDP packets (ACKs)
    # This is called during flush loops to prevent ACK starvation
    # which causes RTT inflation and throughput collapse.

    # Use select with 0 timeout for non-blocking check
    my $rin = '';
    vec($rin, fileno($udpSocket), 1) = 1;
    my $nfound = select($rin, undef, undef, 0);

    return unless($nfound > 0);

    # Process up to 10 packets per call to avoid stalling the flush loop
    my $maxPackets = 10;
    while($maxPackets-- > 0) {
        # Non-blocking recv
        my $packet;
        my $peerAddr = $udpSocket->recv($packet, 65535, Socket::MSG_DONTWAIT);

        last unless(defined($peerAddr) && length($packet));

        # Track statistics
        $self->{_incomingUdpPackets} //= 0;
        $self->{_incomingUdpBytes} //= 0;
        $self->{_incomingUdpPackets}++;
        $self->{_incomingUdpBytes} += length($packet);

        # Process the packet (this handles ACKs)
        my $ts = PageCamel::XS::NGTCP2::timestamp();
        my ($peerPort, $peerhost);
        if(length($peerAddr) == 16) {
            my $peerIp;
            ($peerPort, $peerIp) = Socket::unpack_sockaddr_in($peerAddr);
            $peerhost = Socket::inet_ntoa($peerIp);
        } else {
            my $peerIp6;
            ($peerPort, $peerIp6) = Socket::unpack_sockaddr_in6($peerAddr);
            $peerhost = Socket::inet_ntop(Socket::AF_INET6, $peerIp6);
        }

        $quicConn->process_packet($packet, {host => $peerhost, port => $peerPort}, $ts);

        # Check if more packets available
        vec($rin, fileno($udpSocket), 1) = 1;
        last unless(select($rin, undef, undef, 0) > 0);
    }
}

sub handleQUICPacket($self, $udpSocket) {
    # Receive UDP datagram
    my $packet;
    my $peerAddr = $udpSocket->recv($packet, 65535);

    return unless(defined($peerAddr) && length($packet));

    # Track incoming packet statistics
    $self->{_incomingUdpPackets} //= 0;
    $self->{_incomingUdpBytes} //= 0;
    $self->{_incomingUdpPackets}++;
    $self->{_incomingUdpBytes} += length($packet);

    # Log EVERY incoming packet for first 100, then every 10th
    if($self->{_incomingUdpPackets} <= 100 || $self->{_incomingUdpPackets} % 10 == 0) {
        print STDERR getISODate() . " INCOMING UDP #$self->{_incomingUdpPackets}: " . length($packet) . " bytes\n";
    }

    # Extract peer info (handle both IPv4 and IPv6)
    my ($peerPort, $peerhost);
    if(length($peerAddr) == 16) {
        # IPv4
        my $peerIp;
        ($peerPort, $peerIp) = Socket::unpack_sockaddr_in($peerAddr);
        $peerhost = Socket::inet_ntoa($peerIp);
    } else {
        # IPv6
        my $peerIp;
        ($peerPort, $peerIp) = Socket::unpack_sockaddr_in6($peerAddr);
        $peerhost = Socket::inet_ntop(Socket::AF_INET6, $peerIp);
    }
    my $peerkey = "$peerhost:$peerPort";

    # Get local socket info
    my $socketInfo = $self->{udpSocketInfo}->{$udpSocket};
    my $lhost = $socketInfo->{ip};
    my $lport = $socketInfo->{port};
    my $service = $socketInfo->{service};

    # Get timestamp for QUIC (ngtcp2 expects nanoseconds)
    my $ts = PageCamel::XS::NGTCP2::timestamp();

    # Try to find existing connection by peer address
    my $quicConn = $self->{quicConnectionsByAddr}->{$peerkey};

    if(defined($quicConn)) {
        # Existing connection - process packet
        $self->{_processedPackets} //= 0;
        $self->{_processedPackets}++;

        my $rv = $quicConn->process_packet($packet, {host => $peerhost, port => $peerPort}, $ts);

        if($rv < 0) {
            # Connection error or closing
            $self->{_processedErrors} //= 0;
            $self->{_processedErrors}++;
            if($quicConn->is_closed()) {
                $self->cleanupQUICConnection($quicConn);
            }
        } else {
            $self->{_processedOk} //= 0;
            $self->{_processedOk}++;

            # Log cwnd after processing ACK (every 10th successful packet)
            if($self->{_processedOk} % 10 == 0) {
                my ($cwnd, $in_flight, $ssthresh, $rtt) = $quicConn->{quic_conn}->get_cong_stat();
                my $cwndLeft = $quicConn->{quic_conn}->get_cwnd_left() // -1;
                print STDERR getISODate() . " AFTER ACK #$self->{_processedOk}: cwnd=$cwnd in_flight=$in_flight ssthresh=$ssthresh rtt=$rtt cwndLeft=$cwndLeft\n";
            }
        }

        # Log incoming packet stats periodically
        if($self->{_processedPackets} % 50 == 0) {
            my $inPkts = $self->{_incomingUdpPackets} // 0;
            my $inBytes = $self->{_incomingUdpBytes} // 0;
            my $procOk = $self->{_processedOk} // 0;
            my $procErr = $self->{_processedErrors} // 0;
            print STDERR getISODate() . " INCOMING STATS: udpPackets=$inPkts udpBytes=$inBytes processedOk=$procOk processedErr=$procErr\n";
        }

        # Send any response packets
        $self->sendQUICPackets($quicConn, $udpSocket);

        # Try to flush any pending stream data (ACKs may have opened flow control window)
        # Loop until no more progress can be made (blocked or empty)
        my $handler = $quicConn->{_http3Handler};
        my $http3Server = $quicConn->{_http3Server};
        if(defined($handler) && defined($http3Server)) {
            my $sendCb = sub { $self->sendQUICPackets($quicConn, $udpSocket); };
            my $maxFlushIterations = 100;  # Safety limit
            while($handler->flushPendingStreams($http3Server, $sendCb) && --$maxFlushIterations > 0) {
                $self->sendQUICPackets($quicConn, $udpSocket);
            }
            $self->sendQUICPackets($quicConn, $udpSocket);
        }
    } else {
        # New connection - extract connection ID from packet header
        my $dcid = $self->extractQUICConnectionId($packet);
        return unless(defined($dcid));

        # Check for existing connection by connection ID
        $quicConn = $self->{quicConnections}->{$dcid};

        if(defined($quicConn)) {
            # Connection migration - packet from new address
            $quicConn->process_packet($packet, {host => $peerhost, port => $peerPort}, $ts);
            $self->sendQUICPackets($quicConn, $udpSocket);

            # Try to flush any pending stream data (loop until blocked or empty)
            my $handler = $quicConn->{_http3Handler};
            my $http3Server = $quicConn->{_http3Server};
            if(defined($handler) && defined($http3Server)) {
                my $sendCb = sub { $self->sendQUICPackets($quicConn, $udpSocket); };
                my $maxFlushIterations = 100;
                while($handler->flushPendingStreams($http3Server, $sendCb) && --$maxFlushIterations > 0) {
                    $self->sendQUICPackets($quicConn, $udpSocket);
                }
                $self->sendQUICPackets($quicConn, $udpSocket);
            }
        } else {
            # Brand new connection
            $self->handleNewQUICConnection($udpSocket, $packet, $peerhost, $peerPort, $lhost, $lport, $service, $ts);
        }
    }

    return;
}

sub handleNewQUICConnection($self, $udpSocket, $packet, $peerhost, $peerPort, $lhost, $lport, $service, $ts) {
    require PageCamel::Protocol::QUIC::Server;
    require PageCamel::Protocol::QUIC::Connection;
    require PageCamel::CMDLine::WebFrontend::HTTP3Handler;

    # Extract BOTH DCID and SCID from the client's Initial packet
    # - client_dcid: what client sent in DCID field (random value for server)
    # - client_scid: what client sent in SCID field (client's own source CID)
    my ($client_dcid, $client_scid) = $self->extractQUICConnectionIds($packet);

    return unless(defined($client_dcid) && defined($client_scid));

    # Generate server's own SCID
    my $server_scid = $self->generateQUICConnectionId();

    # Get SSL config - pass all domains for SNI support
    my $defaultdomain = $self->{config}->{sslconfig}->{ssldefaultdomain};
    my $ssldomains = $self->{config}->{sslconfig}->{ssldomains};

    my $peerkey = "$peerhost:$peerPort";
    print getISODate(), " HTTP/3 connection from ", $peerhost, ":", $peerPort, " to ", $lhost, ":", $lport, "\n";

    # Create QUIC connection with multi-domain SNI support
    # IMPORTANT: According to ngtcp2 documentation:
    # - dcid param = client's SCID (so we can send packets back to client)
    # - scid param = server's new SCID
    # - original_dcid transport param = client's DCID from packet
    my $quicConn = PageCamel::Protocol::QUIC::Connection->new(
        id        => $server_scid,
        dcid      => $client_scid,      # ngtcp2 dcid = client's SCID
        scid      => $server_scid,      # ngtcp2 scid = server's SCID
        original_dcid => $client_dcid,  # For transport params (what client sent as DCID)
        path      => {
            local  => {host => $lhost, port => $lport},
            remote => {host => $peerhost, port => $peerPort},
        },
        peer_addr  => {host => $peerhost, port => $peerPort},
        local_addr => {host => $lhost, port => $lport},
        ssl_domains    => $ssldomains,
        default_domain => $defaultdomain,
        default_backend => $self->{config}->{internal_socket},
        on_stream_data => sub($conn, $streamId, $data, $fin) {
            $self->handleQUICStreamData($conn, $streamId, $data, $fin);
        },
        on_handshake => sub($conn) {
            $self->handleQUICHandshake($conn);
        },
    );

    # Store connection by both client's DCID (for Initial packets) and server's SCID
    $self->{quicConnections}->{$client_dcid} = $quicConn;
    $self->{quicConnections}->{$server_scid} = $quicConn;
    # Also store by client's SCID for routing responses
    $self->{quicConnections}->{$client_scid} = $quicConn;
    $self->{quicConnectionsByAddr}->{$peerkey} = $quicConn;

    # Store additional metadata
    $quicConn->{_udpSocket} = $udpSocket;
    $quicConn->{_service} = $service;
    # Backend will be selected based on SNI after handshake
    $quicConn->{_selectedbackend} = undef;

    # Process the initial packet
    my $rv = $quicConn->process_packet($packet, {host => $peerhost, port => $peerPort}, $ts);

    # Check if connection should be dropped (e.g., invalid packet)
    if($quicConn->is_closed()) {
        # Clean up connection from hash tables
        delete $self->{quicConnections}->{$client_dcid};
        delete $self->{quicConnections}->{$server_scid};
        delete $self->{quicConnections}->{$client_scid};
        delete $self->{quicConnectionsByAddr}->{$peerkey};
        return;
    }

    # Send response packets
    $self->sendQUICPackets($quicConn, $udpSocket);

    return;
}

sub handleQUICStreamData($self, $quicConn, $streamId, $data, $fin) {
    # Route stream data to the HTTP/3 server for processing
    my $http3Server = $quicConn->{_http3Server};
    if(defined($http3Server)) {
        $http3Server->process_stream_data($streamId, $data, $fin);
    }
    return;
}

sub handleQUICHandshake($self, $quicConn) {
    # QUIC handshake completed - connection is now established
    my $hostname = $quicConn->get_hostname() // 'unknown';
    my $backend = $quicConn->get_backend_socket();

    my $cid_hex = unpack('H*', $quicConn->id());
    print getISODate(), " HTTP/3 handshake completed for $cid_hex (SNI: $hostname)\n";

    # Set the backend socket based on SNI
    if(defined($backend)) {
        $quicConn->{_selectedbackend} = $backend;
    } else {
        # Fall back to default internal socket if no specific backend configured
        $quicConn->{_selectedbackend} = $self->{config}->{internal_socket};
        print getISODate(), " HTTP/3: No specific backend for $hostname, using default\n";
    }

    # Get peer address info from QUIC connection
    my $peerAddr = $quicConn->peer_addr();
    my $peerhost = $peerAddr->{host} // '0.0.0.0';
    my $peerport = $peerAddr->{port} // 0;
    my $service = $quicConn->{_service};
    my $lport = $service->{port} // 443;
    # Get local host - use first bind address from service
    my $lhost = '0.0.0.0';
    if(defined($service->{bind_adresses}) && defined($service->{bind_adresses}->{ip})) {
        my @ips = @{$service->{bind_adresses}->{ip}};
        $lhost = $ips[0] if(@ips);
    }

    # Create HTTP3Handler instance for backend proxying
    require PageCamel::CMDLine::WebFrontend::HTTP3Handler;
    my $http3Handler = PageCamel::CMDLine::WebFrontend::HTTP3Handler->new(
        quicConnection    => $quicConn,
        backendSocketPath => $quicConn->{_selectedbackend},
        pagecamelInfo     => {
            lhost    => $lhost,
            lport    => $lport,
            peerhost => $peerhost,
            peerport => $peerport,
            usessl   => 1,
        },
        errorPage590Html  => $self->_get590Html(),
    );
    $quicConn->{_http3Handler} = $http3Handler;

    # Create HTTP/3 server instance to handle HTTP/3 framing over QUIC
    # CRITICAL: The send_callback is invoked during flush_pending_data() to send QUIC packets
    # immediately. This prevents RTT inflation from packets sitting in queues with stale timestamps.
    my $http3Server = PageCamel::Protocol::HTTP3::Server->new(
        quic_conn => $quicConn,
        send_callback => sub {
            my $udpSocket = $quicConn->{_udpSocket};
            if(defined($udpSocket)) {
                $quicConn->{_sendCallbackInvocations} //= 0;
                $quicConn->{_sendCallbackInvocations}++;
                my $before = $quicConn->{_udpPacketsSent} // 0;
                $self->sendQUICPackets($quicConn, $udpSocket);
                my $after = $quicConn->{_udpPacketsSent} // 0;
                my $sent = $after - $before;
                if($quicConn->{_sendCallbackInvocations} <= 10 || $quicConn->{_sendCallbackInvocations} % 1000 == 0) {
                    print STDERR "DEBUG sendCallback invocation #$quicConn->{_sendCallbackInvocations}: sent $sent packets\n";
                }
            }
        },
        on_request => sub($server, $streamId, $headers, $fin) {
            $self->handleHTTP3Request($quicConn, $server, $streamId, $headers, $fin);
        },
        on_connect_request => sub($server, $streamId, $headers) {
            $self->handleHTTP3ConnectRequest($quicConn, $server, $streamId, $headers);
        },
        on_error => sub($server, $streamId, $error) {
            print STDERR getISODate(), " HTTP/3: Error on stream $streamId: $error\n";
        },
        on_request_body => sub($server, $streamId, $data) {
            # Forward request body data to HTTP3Handler for streaming to backend
            my $handler = $quicConn->{_http3Handler};
            if(defined($handler) && length($data)) {
                $handler->handleStreamData($server, $streamId, $data, 0);
            }
        },
    );

    $quicConn->{_http3Server} = $http3Server;
    my $cid_hex = unpack('H*', $quicConn->id());
    print getISODate(), " HTTP/3: Created HTTP/3 server for $cid_hex\n";

    # CRITICAL: Send control stream packets (SETTINGS) immediately after creating HTTP/3 server
    # If we don't send these now, the client will receive response data before SETTINGS
    # and close with H3_CLOSED_CRITICAL_STREAM error
    my $udpSocket = $quicConn->{_udpSocket};
    $self->sendQUICPackets($quicConn, $udpSocket) if(defined($udpSocket));

    return;
}

sub handleHTTP3Request($self, $quicConn, $http3Server, $streamId, $headers, $fin) {
    # HTTP/3 request received - delegate to HTTP3Handler for backend proxying
    my $method = $headers->method() // 'unknown';
    my $path = $headers->path() // '/';
    my $authority = $headers->authority() // 'unknown';

    print getISODate(), " HTTP/3: Request stream=$streamId $method $path\n";

    my $handler = $quicConn->{_http3Handler};
    if(!defined($handler)) {
        print STDERR getISODate(), " HTTP/3: No handler for connection, sending 500\n";
        $http3Server->response($streamId, 500, ['content-type', 'text/plain'], 'Internal Server Error');
        return;
    }

    # Convert Headers object to array reference for handler
    my $headersArrayRef = $headers->to_arrayref();

    # Delegate to handler - it will connect to backend and buffer the request
    $handler->handleRequest($http3Server, $streamId, $headersArrayRef, undef);

    # Note: Response will be sent asynchronously when backend data is available
    # The main loop will poll backends via handleHTTP3Backends()

    return;
}

sub handleHTTP3ConnectRequest($self, $quicConn, $http3Server, $streamId, $headers) {
    # HTTP/3 CONNECT request (WebSocket upgrade) - delegate to HTTP3Handler
    my $path = $headers->path() // '/';
    my $authority = $headers->authority() // 'unknown';
    my $protocol = $headers->protocol() // '';

    # print getISODate(), " HTTP/3: CONNECT request on stream $streamId: $path (Host: $authority, protocol: $protocol)\n";

    my $handler = $quicConn->{_http3Handler};
    if(!defined($handler)) {
        print STDERR getISODate(), " HTTP/3: No handler for connection, sending 500\n";
        $http3Server->response($streamId, 500, ['content-type', 'text/plain'], 'Internal Server Error');
        return;
    }

    # Convert Headers object to array reference for handler
    my $headersArrayRef = $headers->to_arrayref();

    # Delegate to handler - it will connect to backend and handle WebSocket upgrade
    $handler->handleConnectRequest($http3Server, $streamId, $headersArrayRef);

    # Note: Response will be sent asynchronously when backend responds
    # The main loop will poll backends via handleHTTP3Backends()

    return;
}

sub canSendUdp($self, $udpSocket) {
    # Check if UDP socket is writable using select() with 0 timeout
    # Returns true if we can send without blocking
    return 0 unless $udpSocket;
    my $wvec = '';
    vec($wvec, fileno($udpSocket), 1) = 1;
    my $ready = select(undef, $wvec, undef, 0);
    return $ready > 0;
}

sub isUdpBackPressured($self, $quicConn) {
    # Check if connection has pending UDP packets that couldn't be sent
    # Used for back-pressure to prevent overwhelming the UDP buffer
    return 0 unless $quicConn;
    return 0 unless $quicConn->{_pendingUdpPackets};
    return scalar(@{$quicConn->{_pendingUdpPackets}}) > 0;
}

sub sendQUICPackets($self, $quicConn, $udpSocket) {
    my $ts = PageCamel::XS::NGTCP2::timestamp();

    # Initialize pending buffer if not exists
    $quicConn->{_pendingUdpPackets} //= [];
    my $hadPending = scalar(@{$quicConn->{_pendingUdpPackets}});

    # ALWAYS generate new packets - this includes ACKs which are critical for
    # flow control and congestion control. Without ACKs, the client will time out.
    # Previously we skipped get_packets() when hadPending > 0, which caused deadlock.
    my @newPackets = $quicConn->get_packets($ts);

    # Debug: log packet generation
    my $newCount = scalar(@newPackets);
    $quicConn->{_getPacketsCalls} //= 0;
    $quicConn->{_getPacketsCalls}++;
    if($newCount > 0 || $quicConn->{_getPacketsCalls} % 500 == 0) {
        print STDERR getISODate() . " UDP get_packets: call #$quicConn->{_getPacketsCalls} new=$newCount pending=$hadPending\n";
    }

    # Combine pending packets with new packets (pending first to maintain order)
    my @allPackets = (@{$quicConn->{_pendingUdpPackets}}, @newPackets);
    $quicConn->{_pendingUdpPackets} = [];  # Clear pending, will re-add if needed

    my $totalBytesSent = 0;
    my $packetsSent = 0;
    my $blocked = 0;

    foreach my $pkt (@allPackets) {
        my $peerAddr = $pkt->{peer_addr};
        next if(!defined($peerAddr) || !defined($peerAddr->{host}) || !defined($peerAddr->{port}));

        # Cache sockaddr on the packet to avoid repeated packing
        if(!$pkt->{_sockaddr}) {
            if($peerAddr->{host} =~ /:/) {
                # IPv6
                $pkt->{_sockaddr} = Socket::pack_sockaddr_in6($peerAddr->{port}, Socket::inet_pton(Socket::AF_INET6, $peerAddr->{host}));
            } else {
                # IPv4
                $pkt->{_sockaddr} = Socket::pack_sockaddr_in($peerAddr->{port}, Socket::inet_aton($peerAddr->{host}));
            }
        }

        if($blocked) {
            # Already blocked, queue remaining packets
            push @{$quicConn->{_pendingUdpPackets}}, $pkt;
            next;
        }

        my $sent = $udpSocket->send($pkt->{data}, 0, $pkt->{_sockaddr});

        if(!defined($sent)) {
            # Send failed - check if it's EAGAIN/EWOULDBLOCK
            if($!{EAGAIN} || $!{EWOULDBLOCK}) {
                # Socket buffer full - queue this and remaining packets
                $blocked = 1;
                push @{$quicConn->{_pendingUdpPackets}}, $pkt;
            } else {
                # Other error - log and skip this packet
                print STDERR getISODate() . " sendQUICPackets: send failed: $!\n";
            }
        } elsif($sent < length($pkt->{data})) {
            # Partial send (shouldn't happen with UDP, but handle it)
            print STDERR getISODate() . " sendQUICPackets: partial send $sent/" . length($pkt->{data}) . "\n";
            $totalBytesSent += $sent;
            $packetsSent++;
        } else {
            # Full send success
            $totalBytesSent += $sent;
            $packetsSent++;
        }
    }

    # Debug: log packet stats
    my $pendingCount = scalar(@{$quicConn->{_pendingUdpPackets}});
    $quicConn->{_udpPacketsSent} //= 0;
    $quicConn->{_udpBytesSent} //= 0;
    $quicConn->{_udpPacketsSent} += $packetsSent;
    $quicConn->{_udpBytesSent} += $totalBytesSent;

    # Log every 100 packets or if we have pending packets
    if($pendingCount > 0 || ($packetsSent > 0 && $quicConn->{_udpPacketsSent} % 100 < $packetsSent)) {
        print STDERR getISODate() . " UDP: sent=$packetsSent bytes=$totalBytesSent pending=$pendingCount total_pkts=$quicConn->{_udpPacketsSent} total_bytes=$quicConn->{_udpBytesSent}\n";
    }

    # Return number of pending packets (for back-pressure detection)
    return $pendingCount;
}

sub flushPendingUdpPackets($self) {
    # Flush pending UDP packets for all QUIC connections
    # This is called from the main loop to retry packets that couldn't be sent earlier
    my %seen;

    foreach my $connId (keys %{$self->{quicConnections}}) {
        my $quicConn = $self->{quicConnections}->{$connId};
        next unless(defined($quicConn));

        # Skip if we already processed this connection (multiple IDs per connection)
        my $connPtr = "$quicConn";
        next if($seen{$connPtr}++);

        # Skip if no pending packets
        next unless($quicConn->{_pendingUdpPackets} && @{$quicConn->{_pendingUdpPackets}});

        my $udpSocket = $quicConn->{_udpSocket};
        next unless(defined($udpSocket));

        # Try to send pending packets (sendQUICPackets will handle the retry logic)
        # Pass an empty get_packets result by not generating new packets
        my $pendingBefore = scalar(@{$quicConn->{_pendingUdpPackets}});
        $self->sendQUICPackets($quicConn, $udpSocket);
        my $pendingAfter = $quicConn->{_pendingUdpPackets} ? scalar(@{$quicConn->{_pendingUdpPackets}}) : 0;

        if($pendingAfter < $pendingBefore) {
            # Some packets were sent, log progress
            my $sent = $pendingBefore - $pendingAfter;
            print STDERR getISODate() . " flushPendingUdpPackets: flushed $sent pending packets, $pendingAfter remaining\n";
        }
    }

    return;
}

sub handleQUICTimeouts($self) {
    my $ts = PageCamel::XS::NGTCP2::timestamp();

    foreach my $connId (keys %{$self->{quicConnections}}) {
        my $quicConn = $self->{quicConnections}->{$connId};
        next unless(defined($quicConn));

        # Skip if we already processed this connection (multiple IDs per connection)
        next if($quicConn->{_timeoutHandled});

        my $expiry = $quicConn->get_expiry();
        if($expiry <= $ts) {
            # Rate limit: don't call handle_expiry more than once per millisecond per connection
            my $lastExpiry = $quicConn->{_lastExpiryHandled} // 0;
            if($ts - $lastExpiry < 1_000_000) {  # 1ms in nanoseconds
                $quicConn->{_timeoutHandled} = 1;
                next;
            }
            $quicConn->{_lastExpiryHandled} = $ts;

            my $rv = $quicConn->handle_expiry($ts);

            # Debug: log if handle_expiry returned an error
            if(defined($rv) && $rv < 0) {
                my $handler = $quicConn->{_http3Handler};
                my $bytesSent = $handler ? ($handler->{streamBytesSent}->{0} // 0) : 0;
                print STDERR getISODate() . " DEBUG handleQUICTimeouts: handle_expiry returned $rv (bytesSent=$bytesSent)\n";
            }

            # Send any resulting packets (probe packets for congestion control)
            my $udpSocket = $quicConn->{_udpSocket};
            $self->sendQUICPackets($quicConn, $udpSocket) if(defined($udpSocket));

            # After timeout handling, try to flush pending stream data
            my $handler = $quicConn->{_http3Handler};
            my $http3Server = $quicConn->{_http3Server};
            if(defined($handler) && defined($http3Server)) {
                my $sendCb = sub { $self->sendQUICPackets($quicConn, $udpSocket); };
                my $maxFlushIterations = 100;
                while($handler->flushPendingStreams($http3Server, $sendCb) && --$maxFlushIterations > 0) {
                    $self->sendQUICPackets($quicConn, $udpSocket);
                }
                $self->sendQUICPackets($quicConn, $udpSocket);
            }

            # Check if connection closed
            if($quicConn->is_closed()) {
                my $handler = $quicConn->{_http3Handler};
                my $bytesSent = $handler ? ($handler->{streamBytesSent}->{0} // 0) : 0;
                print STDERR getISODate() . " DEBUG handleQUICTimeouts: connection closed after handle_expiry (bytesSent=$bytesSent)\n";
                $self->cleanupQUICConnection($quicConn);
            }
        }

        $quicConn->{_timeoutHandled} = 1;
    }

    # Reset timeout handled flags
    foreach my $connId (keys %{$self->{quicConnections}}) {
        my $quicConn = $self->{quicConnections}->{$connId};
        delete $quicConn->{_timeoutHandled} if(defined($quicConn));
    }

    return;
}

sub cleanupQUICConnection($self, $quicConn) {
    return unless(defined($quicConn));

    # Cleanup HTTP3Handler if present
    my $handler = $quicConn->{_http3Handler};
    if(defined($handler)) {
        $handler->cleanup();
        delete $quicConn->{_http3Handler};
    }

    # Remove from connection ID map
    foreach my $cid ($quicConn->get_connection_ids()) {
        delete $self->{quicConnections}->{$cid};
    }

    # Remove from address map
    my $peerAddr = $quicConn->peer_addr();
    if(defined($peerAddr)) {
        my $peerkey = "$peerAddr->{host}:$peerAddr->{port}";
        delete $self->{quicConnectionsByAddr}->{$peerkey};
    }

    # Destroy connection
    $quicConn->destroy();

    return;
}

sub handleHTTP3Backends($self) {
    # Poll backend sockets for all QUIC connections and process responses
    # This is called from the main loop to handle async backend I/O

    my $blocksize = 16_384;
    my $maxBufferSize = 50_000_000;

    # Debug: track call frequency
    $self->{_h3bCalls} //= 0;
    $self->{_h3bCalls}++;
    if($self->{_h3bCalls} % 100 == 0) {
        my $numConns = scalar(keys %{$self->{quicConnections}});
        print STDERR getISODate() . " DEBUG handleHTTP3Backends: call #$self->{_h3bCalls} numConnections=$numConns\n";
    }

    # Collect all backends from all handlers
    my @allBackends;
    my %backendToQuicConn;  # backend socket → QUIC connection mapping

    my $numConnections = scalar(keys %{$self->{quicConnections}});

    my %seen;  # Track seen QUIC connections to avoid duplicates
    foreach my $connId (keys %{$self->{quicConnections}}) {
        my $quicConn = $self->{quicConnections}->{$connId};
        next unless(defined($quicConn));

        # Skip if we've already processed this connection (multiple IDs per connection)
        my $connPtr = "$quicConn";
        next if($seen{$connPtr}++);

        my $handler = $quicConn->{_http3Handler};
        next unless(defined($handler));

        # Get all backend sockets from this handler
        # Apply back-pressure: skip backends whose response buffer is too large OR congestion-blocked
        my $maxResponseBuffer = 32768;  # 32KB - lower than congestion window to avoid buildup
        foreach my $streamId (keys %{$handler->{streamBackends}}) {
            my $backend = $handler->{streamBackends}->{$streamId};
            next unless(defined($backend));

            # NOTE: Removed congestion-blocked skip that was contributing to deadlock.
            # The buffer size check below provides sufficient back-pressure.
            # We want to keep reading from backends (up to buffer limit) so data
            # is ready when congestion clears.

            # Check response buffer size for back-pressure
            my $responseLen = length($handler->{streamResponses}->{$streamId} // '');
            if($responseLen > $maxResponseBuffer) {
                # Buffer too large - don't read more until client catches up
                print STDERR "DEBUG handleHTTP3Backends: stream=$streamId SKIPPED (buffer full) responseBuffer=$responseLen\n";
                next;
            }

            push @allBackends, $backend;
            $backendToQuicConn{$backend} = $quicConn;
        }
    }

    # Debug: show how many backends we're polling
    if($self->{_h3bCalls} % 100 == 0) {
        print STDERR getISODate() . " DEBUG handleHTTP3Backends: backends_to_poll=" . scalar(@allBackends) . "\n";
    }

    # Build select sets for backends (may be empty if all congestion-blocked)
    my $readSet = IO::Select->new(@allBackends);
    my $writeSet = IO::Select->new();

    # Add backends with pending writes to write set
    my $pendingWrites = 0;
    %seen = ();
    foreach my $connId (keys %{$self->{quicConnections}}) {
        my $quicConn = $self->{quicConnections}->{$connId};
        next unless(defined($quicConn));

        my $connPtr = "$quicConn";
        next if($seen{$connPtr}++);

        my $handler = $quicConn->{_http3Handler};
        next unless(defined($handler));

        foreach my $streamId (keys %{$handler->{tobackendbuffers}}) {
            my $backend = $handler->{streamBackends}->{$streamId};
            if(defined($backend) && length($handler->{tobackendbuffers}->{$streamId} // '')) {
                $writeSet->add($backend);
                $pendingWrites++;
            }
        }
    }

    # Poll backends for read/write (only if we have sockets to poll)
    my $canRead = [];
    my $canWrite = [];
    my %canWriteHash;

    if($readSet->count() > 0 || $writeSet->count() > 0) {
        $ERRNO = 0;
        # Use 0 timeout (non-blocking) - main loop handles wait timing
        my ($r, $w, undef) = IO::Select->select($readSet, $writeSet, undef, 0);

        # Handle EINTR - but don't return early, still need to flush
        if(!defined($r) && $ERRNO{EINTR}) {
            $r = [];
            $w = [];
        }

        $canRead = $r // [];
        $canWrite = $w // [];
        %canWriteHash = map { $_ => 1 } @{$canWrite};

        # Process readable sockets
        foreach my $socket (@{$canRead}) {
            my $quicConn = $backendToQuicConn{$socket};
            next unless(defined($quicConn));

            my $handler = $quicConn->{_http3Handler};
            my $http3Server = $quicConn->{_http3Server};
            next unless(defined($handler) && defined($http3Server));

            my $dummyBuffer = '';  # HTTP3Handler appends to toclientbuffer but we don't use it here
            $handler->handleBackendData($http3Server, $socket, \$dummyBuffer, $maxBufferSize);

            # Send any resulting QUIC packets
            my $udpSocket = $quicConn->{_udpSocket};
            $self->sendQUICPackets($quicConn, $udpSocket) if(defined($udpSocket));

            # CRITICAL: Process incoming ACKs after each backend read to prevent RTT inflation
            $self->processIncomingUdpNonBlocking($udpSocket, $quicConn) if(defined($udpSocket));
        }
    }

    %seen = ();
    foreach my $connId (keys %{$self->{quicConnections}}) {
        my $quicConn = $self->{quicConnections}->{$connId};
        next unless(defined($quicConn));

        my $connPtr = "$quicConn";
        next if($seen{$connPtr}++);

        my $handler = $quicConn->{_http3Handler};
        my $http3Server = $quicConn->{_http3Server};
        next unless(defined($handler) && defined($http3Server));

        # Write to backends
        $handler->writeToBackends($blocksize, 100, 0, \%canWriteHash);

        # Process any waiting streams
        $handler->processWaitingStreams($http3Server);

        # Flush pending stream data (retry sends blocked by flow control)
        # Pass callback to send packets during flush to keep congestion window open
        # Loop until no more progress can be made
        # CRITICAL: Process incoming ACKs on each iteration to prevent RTT inflation
        my $udpSocket = $quicConn->{_udpSocket};
        my $sendPacketsCallback = sub {
            $self->sendQUICPackets($quicConn, $udpSocket) if(defined($udpSocket));
        };
        my $maxFlushIterations = 100;
        my $flushedBytes = 1;  # Start with true to enter loop at least once
        while($flushedBytes && --$maxFlushIterations > 0) {
            $flushedBytes = $handler->flushPendingStreams($http3Server, $sendPacketsCallback);
            $self->sendQUICPackets($quicConn, $udpSocket) if(defined($udpSocket));

            # CRITICAL: Process any pending incoming ACKs to prevent RTT inflation
            # This MUST happen inside the loop, even when flush returns 0 (blocked).
            # Without this, ACKs pile up, cwnd stays full, and data transfer stalls.
            if(defined($udpSocket)) {
                $self->processIncomingUdpNonBlocking($udpSocket, $quicConn);
            }
        }

        # CRITICAL: Always process ACKs after the loop, even if we never entered it
        # (e.g., when flushPendingStreams returns 0 on first call)
        if(defined($udpSocket)) {
            $self->processIncomingUdpNonBlocking($udpSocket, $quicConn);
        }

        # Send any remaining QUIC packets after the flush
        $self->sendQUICPackets($quicConn, $udpSocket) if(defined($udpSocket));
    }

    return;
}

sub extractQUICConnectionId($self, $packet) {
    # Extract Destination Connection ID from QUIC packet header
    # QUIC long header: first byte has 0x80 set, DCID length at byte 5
    # QUIC short header: first byte has 0x80 clear, DCID based on known length

    return unless(defined($packet) && length($packet) >= 6);

    my $firstByte = ord(substr($packet, 0, 1));

    if($firstByte & 0x80) {
        # Long header
        my $dcidLen = ord(substr($packet, 5, 1));
        return unless(length($packet) >= 6 + $dcidLen);
        return substr($packet, 6, $dcidLen);
    } else {
        # Short header - DCID length is based on connection configuration
        # Default to 8 bytes for new connections
        return substr($packet, 1, 8) if(length($packet) >= 9);
    }

    return;
}

sub extractQUICConnectionIds($self, $packet) {
    # Extract BOTH Destination and Source Connection IDs from QUIC Initial packet
    # Returns (dcid, scid) or () on failure
    #
    # QUIC Long Header format:
    # Byte 0: Header byte (0x80 set for long header)
    # Bytes 1-4: Version (4 bytes)
    # Byte 5: DCID Length
    # Bytes 6 to 6+DCID_LEN-1: DCID
    # Byte 6+DCID_LEN: SCID Length
    # Bytes 6+DCID_LEN+1 onwards: SCID

    return unless(defined($packet) && length($packet) >= 7);

    my $firstByte = ord(substr($packet, 0, 1));

    # Only long headers have SCID
    return unless($firstByte & 0x80);

    my $dcidLen = ord(substr($packet, 5, 1));
    return unless(length($packet) >= 7 + $dcidLen);

    my $dcid = substr($packet, 6, $dcidLen);

    my $scidLenOffset = 6 + $dcidLen;
    my $scidLen = ord(substr($packet, $scidLenOffset, 1));
    return unless(length($packet) >= $scidLenOffset + 1 + $scidLen);

    my $scid = substr($packet, $scidLenOffset + 1, $scidLen);

    return ($dcid, $scid);
}

sub generateQUICConnectionId($self) {
    # Generate a random 8-byte connection ID
    my $cid = '';
    for(my $i = 0; $i < 8; $i++) {
        $cid .= chr(int(rand(256)));
    }
    return $cid;
}

sub endprogram($self) { ## no critic (Subroutines::RequireFinalReturn)
    sleep(1);
    while(1) {
        kill 9, $PID;
        sleep(1);
    }
}

sub _get590Html($self) {
    my $html = '<html><head><title>590 Connection to backend server failed</title></head><body onload="starttimer();">';

    $html .= '<script>function starttimer() { setTimeout(() => {doreload();}, 15000); };function doreload() {window.location.reload();};</script>';

    my $b64 = Logo590();
    $html .= '<p align="center"><img src="data:image/png;base64, ' . $b64 . '" onclick="doreload();" title="Net cat"></p>';
    $html .= '<p align="center">Connection to the backend server failed.<br/>&nbsp;<br/>The server is most likely undergoing maintenance,<br/>please <strike>check your cat</strike> check back in a few minutes.</p>';
    $html .= '<p align="center">Click on the cat to reload the page.</p>';

    $html .= "</body></html>";

    return $html;
}

sub get590($self) {
    my $html = $self->_get590Html();

    my $reply = "HTTP/1.1 590 Connection to backend server failed\r\n";
    $reply .= "Content-Type: text/html; charset=UTF-8\r\n";
    $reply .= "Content-Length: " . length($html) . "\r\n";
    $reply .= "\r\n";
    $reply .= $html;

    return $reply;
}

sub get408($self) {
    my $html = '<html><head><title>408 Request Timeout</title></head><body onload="starttimer();">';

    $html .= '<script>function starttimer() { setTimeout(() => {doreload();}, 15000); };function doreload() {window.location.reload();};</script>';

    my $b64 = Logo590();
    $html .= '<p align="center"><img src="data:image/png;base64, ' . $b64 . '" onclick="doreload();" title="Net cat"></p>';
    $html .= '<p align="center">Your browser did not send a full set of request headers within the alotted time.</p>';
    $html .= '<p align="center">Click on the cat to reload the page.</p>';

    $html .= "</body></html>";

    my $reply = "HTTP/1.1 408 Request Timeout\r\n";
    $reply .= "Content-Type: text/html; charset=UTF-8\r\n";
    $reply .= "Content-Length: " . length($html) . "\r\n";
    $reply .= "\r\n";
    $reply .= $html;

    return $reply;
}

sub parseheaders($self, $rawheaders) {
    my @headers;

    # Split on newlines - O(n) instead of O(n²) character-by-character parsing
    my @lines = split(/\r?\n/, $rawheaders);
    foreach my $line (@lines) {
        last if $line eq '';  # Empty line marks end of headers
        push @headers, $line;
    }

    return @headers;
}

sub _getLocalIPs($self) {
    my $starttime = time;
    my @lines = `ifconfig`;

    my @ips;

    my $ignorenext = 0;
    my $backupip;
    my $isbackupip = 0;
    foreach my $line (@lines) {
        chomp $line;
        if($line =~ /^docker\d\:/ || $line =~ /^lo\:/) {
            $ignorenext = 1;
        }
        if($line =~ /^wlo\d\:/) {
            $isbackupip = 1;
        }
        if($ignorenext && $line eq '') {
            $ignorenext = 0;
            $isbackupip = 0;
        }
        if($ignorenext) {
            #print "Ignoring $line\n";
            next;
        }
        if($line =~ /inet\ (.*)\ netmask/) {
            my $ip = $1;
            $ip =~ s/^\ +//g;
            $ip =~ s/\ +$//g;
            if($ip !~ /127\./) {
                if(!$isbackupip) {
                    push @ips, $ip;
                } else {
                    $backupip = $ip;
                }
            }
        }
    }

    if(!scalar @ips && defined($backupip)) {
        push @ips, $backupip;
    }

    my $allips = join(',', sort @ips);
    my $endtime = time;

    print "Dynamic IP check took ", $endtime - $starttime, " seconds\n";

    return $allips;
}


1;
