package PageCamel::CMDLine::WebFrontend;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.0;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

use IO::Socket::INET;
use IO::Socket::SSL;
use IO::Select;
use IO::Socket::UNIX;
use PageCamel::Helpers::ConfigLoader;
use Time::HiRes qw(sleep usleep);
use PageCamel::Helpers::Logo;
use Data::Dumper;
use Sys::Hostname;
use POSIX ":sys_wait_h";

# For turning off SSL session cache
use Readonly;
Readonly my $SSL_SESS_CACHE_OFF => 0x0000;

my $childcount = 0;
$SIG{CHLD} = \&REAPER;
sub REAPER {
    my $stiff;
    while (($stiff = waitpid(-1, &WNOHANG)) > 0) {
        print "Child PID $stiff has gone the way of the Dodo\n";
        $childcount--;
    }
    $SIG{CHLD} = \&REAPER; # install *after* calling waitpid
}


sub new {
    my ($class, $isDebugging, $configfile) = @_;
    my $self = bless {}, $class;
    
    $self->{isDebugging} = $isDebugging;
    $self->{configfile} = $configfile;
    
    croak("Config file $configfile not found!") unless(-f $configfile);

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
    
    my $weblockname = "/run/lock/pagecamel_webgui_frontend.lock";

    if(-f $weblockname) {
        carp("LOCKFILE $weblockname ALREADY EXISTS!");
        carp("REMOVING LOCKFILE $weblockname!");
        unlink $weblockname;
    }

    # FIXME Add exclusive locked open for $weblockname


    $PROGRAM_NAME = $ps_appname;


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

                if($childcount >= $self->{config}->{max_childs}) {
                    print "Too many children already!\n";
                    $client->close;
                    next;
                }

                my $childpid = fork();
                if(!defined($childpid)) {
                    print "FORK FAILED!\n";
                    $client->close;
                    next;
                } elsif($childpid == 0) {
                    # Child
                    $self->handleClient($client);
                    print "Child PID $PID is done, exiting...\n";
                    exit(0);
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
    
    my $finishcountdown = 0;
    $SIG{USR1} = sub {
        if(!$finishcountdown) {
            $finishcountdown = time + 10;
            print "Backend finished, 10 second countdown before closing socket\n";
        } else {
            print "Backend finished, countdown already started\n";
        }
        return;
    };
    

    print "Doing some network stuff in child PID $PID\n";

    my $lhost = $client->sockhost();
    my $lport = $client->sockport();
    my $peerhost = $client->peerhost();
    my $peerport = $client->peerport();

    my $usessl = 0;
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
        my $encrypted = IO::Socket::SSL->start_SSL($client,
            SSL_server => 1,
            SSL_key_file=>  $self->{config}->{sslconfig}->{ssldomains}->{$defaultdomain}->{sslkey},
            SSL_cert_file=> $self->{config}->{sslconfig}->{ssldomains}->{$defaultdomain}->{sslcert},
            SSL_cipher_list => $self->{config}->{sslconfig}->{sslciphers},
            SSL_create_ctx_callback => sub {
                my $ctx = shift;

                print STDERR "******************* CREATING NEW CONTEXT ********************\n";

                # Enable workarounds for broken clients
                Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_ALL); ## no critic (Subroutines::ProhibitAmpersandSigils)

                # Disable session resumption completely
                Net::SSLeay::CTX_set_session_cache_mode($ctx, $SSL_SESS_CACHE_OFF);

                # Disable session tickets
                Net::SSLeay::CTX_set_options($ctx, &Net::SSLeay::OP_NO_TICKET); ## no critic (Subroutines::ProhibitAmpersandSigils)

                # Check requested server name
                Net::SSLeay::CTX_set_tlsext_servername_callback($ctx, sub {
                    my $ssl = shift;
                    my $h = Net::SSLeay::get_servername($ssl);

                    if(!defined($h)) {
                        print STDERR "SSL: No Hostname given during SSL setup\n";
                        return;
                    }

                    if(!defined($self->{config}->{sslconfig}->{ssldomains}->{$h})) {
                        print STDERR "SSL: Hostname $h not configured\n";
                        print STDERR Dumper($self->{config}->{sslconfig}->{ssldomains});
                        return;
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
                        $self->{config}->{sslconfig}->{ssldomains}->{$h}->{ctx} = $newctx;
                    }
                    Net::SSLeay::set_SSL_CTX($ssl, $newctx);
                });

                #    Prepared/tested for future ALPN needs (e.g. HTTP/2)
                ## Advertise supported HTTP versions
                #Net::SSLeay::CTX_set_alpn_select_cb($ctx, ['http/1.1', 'http/2.0']);
            },
        );
        if(!$encrypted) {
            print "startSSL failed: ", $SSL_ERROR, "\n";
            exit(0);
        }
    }

    my $backend = IO::Socket::UNIX->new(
            Peer => $self->{config}->{internal_socket},
            Type => SOCK_STREAM,
        ) or croak("Failed to connect to backend: $ERRNO");

    syswrite($backend, "PAGECAMEL $lhost $lport $peerhost $peerport $usessl $PID HTTP/1.1\r\n");

    my $select = IO::Select->new($client, $backend);

    my $done = 0;
    my $failcount = 0;
    my $toclientbuffer = '';
    my $tobackendbuffer = '';
    while(!$done) {
        my $totalread = 0;
        my $rawbuffer;

        # Wait long if we currently have nothing to send, only wait a very short time for new data if we already got
        # something in out output buffers
        my $waittime = 0.3;
        if(length($toclientbuffer) || length($tobackendbuffer)) {
            $waittime = 0.05;
        }
        
        my @connections = $select->can_read($waittime);
        foreach my $connection (@connections) {
            sysread($connection, $rawbuffer, 1_000_000); # Read at most 1 Meg at a time
            if(!length($rawbuffer)) {
                $failcount++;
            } else {
                $failcount = 0;
                if(ref $connection eq 'IO::Socket::UNIX') {
                    # data FROM the backend
                    $toclientbuffer .= $rawbuffer;
                } else {
                    $tobackendbuffer .= $rawbuffer;
                }
            }
        }

        if(length($toclientbuffer)) {
            my $written;

            my $writebuffer = substr($toclientbuffer, 0, 1_000_000); # write at most one meg at a time
            eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                $written = syswrite($client, $writebuffer);
            };
            if($EVAL_ERROR) {
                print STDERR "Write error: $EVAL_ERROR\n";
                $failcount++;
            }
            $toclientbuffer = substr($toclientbuffer, $written);
        }

        if(length($tobackendbuffer)) {
            my $written;

            my $writebuffer = substr($tobackendbuffer, 0, 1_000_000); # write at most one meg at a time
            eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                $written = syswrite($backend, $writebuffer);
            };
            if($EVAL_ERROR) {
                print STDERR "Write error: $EVAL_ERROR\n";
                $failcount++;
            }
            $tobackendbuffer = substr($tobackendbuffer, $written);
        }

        if($failcount >= 5) {
            print "Possible disconnect detected!\n";
            if(length($toclientbuffer)) {
                print "   !!! toclientbuffer still has ", length($toclientbuffer), " bytes unsent!\n";
            }
            if(length($tobackendbuffer)) {
                print "   !!! tobackendbuffer still has ", length($tobackendbuffer), " bytes unsent!\n";
            }
            if(length($toclientbuffer) || length($toclientbuffer)) {
                if(!$finishcountdown) {
                    print "Still trying to send buffer data, starting 10 second countdown\n";
                    $finishcountdown = time + 10;
                }
            } else {
                print "Errors but outgoing buffers are empty, shutting down right now\n";
                $done = 1;
            }
        }
        
        if($finishcountdown > 0) {
            if($finishcountdown > time) {
                print "Time to shutdown: ", $finishcountdown - time, "\n";
            } else {
                print "Finally done!\n";
                $done = 1;
            }
        }
        
    }
    
    print "Shutting down child PID $PID\n";
    
    close $backend;
    close $client;

    exit(0);
}
