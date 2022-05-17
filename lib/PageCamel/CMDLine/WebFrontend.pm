package PageCamel::CMDLine::WebFrontend;
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

use IO::Socket::INET;
use IO::Socket::SSL;
use IO::Select;
use IO::Socket::UNIX;
use PageCamel::Helpers::ConfigLoader;
use Time::HiRes qw(sleep usleep);
use PageCamel::Helpers::Logo;
use Sys::Hostname;
use POSIX;

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


sub new {
    my ($class, $isDebugging, $configfile) = @_;
    my $self = bless {}, $class;
    
    $self->{isDebugging} = $isDebugging;
    $self->{configfile} = $configfile;
    
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

sub init {
    my ($self) = @_;
    
    print "Loading config file ", $self->{configfile}, "\n";
    my $config = LoadConfig($self->{configfile},
                        ForceArray => [ 'service', 'ip'],);
    
    $self->{config} = $config;

    # Turn any comma-separated ip addresses into their own entry
    foreach my $service (@{$config->{external_network}->{service}}) {
        my @newips;
        foreach my $ip (@{$service->{bind_adresses}->{ip}}) {
            if($ip !~ /\,/) {
                push @newips, $ip;
            } else {
                push @newips, split/\,/, $ip;
            }
        }
        $service->{bind_adresses}->{ip} = \@newips;
    }


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
    foreach my $service (@{$config->{external_network}->{service}}) {
        print '** Service at port ', $service->{port}, ' does ', $service->{usessl} ? '' : 'NOT', " use SSL/TLS\n";
        foreach my $ip (@{$service->{bind_adresses}->{ip}}) {
            my $tcp = IO::Socket::IP->new(
                    LocalHost => $ip,
                    LocalPort => $service->{port},
                    Listen => 1,
                    ReuseAddr => 1,
                    Proto => 'tcp',
            ) or croak("Failed to bind: " . $ERRNO);
            #binmode($tcp, ':bytes');
            push @tcpsockets, $tcp;
            print "   Listening on ", $ip, ":, ", $service->{port}, "/tcp\n";
        }
    }
    my $select = IO::Select->new(@tcpsockets);
    $self->{select} = $select;
    
    return;
}

sub run {
    my ($self) = @_;

    while(1) {
        while((my @connections = $self->{select}->can_read)) {
            foreach my $connection (@connections) {
                my $client = $connection->accept;

                #print "**** Connection from ", $client->peerhost(), "   \n";

                if(defined($self->{debugip})) {
                    my $peerhost = $client->peerhost();
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
    }

    print "run() loop finished.\n";
    return;
}

sub handleClient {
    my ($self, $client) = @_;

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
        $SIG{USR1} = sub {
            if(!$finishcountdown) {
                $finishcountdown = time + 20;
                #print "Backend finished, 20 second countdown before closing socket\n";
            } else {
                #print "Backend finished, countdown already started\n";
            }
            return;
        };
        

        #print "Doing some network stuff in child PID $PID\n";

        my $lhost = $client->sockhost();
        my $lport = $client->sockport();
        my $peerhost = $client->peerhost();
        my $peerport = $client->peerport();

        my $usessl = 0;
        my $selectedbackend = $self->{config}->{internal_socket};

        # Check if we need to use SSL
        foreach my $service (@{$self->{config}->{external_network}->{service}}) {
            # Search for the correct service
            if($service->{port} == $lport) {
                # Now check the IP address
                foreach my $ip (@{$service->{bind_adresses}->{ip}}) {
                    if($ip eq $lhost) {
                        # Found it
                        $usessl = $service->{usessl};
                    }
                }
            }
        }

        if($usessl) {
            my $defaultdomain = $self->{config}->{sslconfig}->{ssldefaultdomain};
            my $encrypted;
            my $ok = 0;
            eval {
                $encrypted = IO::Socket::SSL->start_SSL($client,
                    SSL_server => 1,
                    SSL_key_file=>  $self->{config}->{sslconfig}->{ssldomains}->{$defaultdomain}->{sslkey},
                    SSL_cert_file=> $self->{config}->{sslconfig}->{ssldomains}->{$defaultdomain}->{sslcert},
                    SSL_cipher_list => $self->{config}->{sslconfig}->{sslciphers},
                    SSL_create_ctx_callback => sub {
                        my $ctx = shift;

                        #print STDERR "******************* CREATING NEW CONTEXT ********************\n";

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
                                #print STDERR "Cert: ", $self->{config}->{sslconfig}->{ssldomains}->{$h}->{sslcert}, " Key: ", $self->{config}->{sslconfig}->{ssldomains}->{$h}->{sslkey}, "\n";
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

            if(!$ok) {
                print "EVAL ERROR: ", $EVAL_ERROR, "\n";
                $self->endprogram();
            } elsif(!$ok || !defined($encrypted) || !$encrypted) {
                print "startSSL failed: ", $SSL_ERROR, "\n";
                $self->endprogram();
            }
        }

        my $backend = IO::Socket::UNIX->new(
                Peer => $selectedbackend,
                Type => SOCK_STREAM,
            ) or croak("Failed to connect to backend: $ERRNO");

        binmode($client);
        binmode($backend);

        my $overhead = "PAGECAMEL $lhost $lport $peerhost $peerport $usessl $PID HTTP/1.1\r\n";
        my $overheadwritten;
        eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
            $overheadwritten = syswrite($backend, $overhead);
        };
        if($EVAL_ERROR) {
            print STDERR "EVAL ERROR on writing overhead to backend: $EVAL_ERROR\n";
            $self->endprogram();
        } elsif($overheadwritten != length($overhead)) {
            print STDERR "Could not write overheadline to backend!\n";
            $self->endprogram();
        }

        sleep(0.01);
        if($sigpipeseen) {
            print STDERR "SIGPIPE ON FIRST WRITE TO BACKEND - Bailing out\n";
            $self->endprogram();
        }

        my $select = IO::Select->new($client, $backend);

        my $done = 0;
        my $toclientbuffer = '';
        my $tobackendbuffer = '';
        my $debugincapture = '';
        my $debugoutcapture = '';
        my $clientdisconnect = 0;
        my $backenddisconnect = 0;
        while(!$done) {
            if($sigpipeseen > $sigpipehandled) {
                sleep(0.05);
                $sigpipehandled++;
            }
            if($sigpipehandled > 200) {
                print STDERR "Too many SIGPIPEs, bailing out.\n";
                print STDERR "*** Debug IN data: \n", $debugincapture, "\n";
                #print STDERR "*** Debug OUT data: \n", $debugoutcapture, "\n";
                $done = 1;
            }
            my $totalread = 0;
            my $rawbuffer;

            # Wait long if we currently have nothing to send, only wait a very short time for new data if we already got
            # something in out output buffers
            my $waittime = 0.1;
            if(length($toclientbuffer) || length($tobackendbuffer)) {
                $waittime = 0.05;
            }
            
            my @connections = $select->can_read($waittime);
            foreach my $connection (@connections) {
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
                    } else {
                        $tobackendbuffer .= $rawbuffer;
                        if(length($debugincapture) < 1000) {
                            $debugincapture .= $rawbuffer;
                        }
                    }
                }
            }

            if(length($toclientbuffer) && !$clientdisconnect) {
                my $written;

                my $writebuffer = substr($toclientbuffer, 0, 10_000_000); # write at most 10MB at a time
                eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                    $written = syswrite($client, $writebuffer);
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
                    $toclientbuffer = substr($toclientbuffer, $written);
                } else {
                    #print STDERR "No data written to client\n";
                }
            }

            if(length($tobackendbuffer) && !$backenddisconnect) {
                my $written;

                my $writebuffer = substr($tobackendbuffer, 0, 10_000_000); # write at most 10MB at a time
                eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                    $written = syswrite($backend, $writebuffer);
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
                    $tobackendbuffer = substr($tobackendbuffer, $written);

                    # Reset SIGPIPE counter whenever we have success writing to the backend
                    $sigpipeseen = 0;
                    $sigpipehandled = 0;
                } else {
                    #print STDERR "No data written to backend\n";
                }
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

sub endprogram { ## no critic (Subroutines::RequireFinalReturn)
    my ($self) = @_;

    sleep(1);
    while(1) {
        kill 9, $PID;
        sleep(1);
    }
}


1;
