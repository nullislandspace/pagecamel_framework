package PageCamel::CMDLine::WebGUI;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.2;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use PageCamel::Web;
use PageCamel::Helpers::ConfigLoader;
use Time::HiRes qw(sleep usleep);
use PageCamel::Helpers::Logo;
use Data::Dumper;

# For turning off SSL session cache
use Readonly;
Readonly my $SSL_SESS_CACHE_OFF => 0x0000;

sub new {
    my ($class, $isDebugging, $forceForking, $forceSSL, $useDebugPort, $traceflag, $configfile) = @_;
    my $self = bless {}, $class;
    
    $self->{isDebugging} = $isDebugging;
    $self->{forceForking} = $forceForking;
    $self->{forceSSL} = $forceSSL;
    $self->{useDebugPort} = $useDebugPort;
    $self->{trace} = $traceflag;
    $self->{configfile} = $configfile;
    
    croak("Config file $configfile not found!") unless(-f $configfile);
    
    return $self;
}

sub init {
    my ($self) = @_;
    
    print "Loading config file ", $self->{configfile}, "\n";
    my $config = LoadConfig($self->{configfile},
                        ForceArray => [ 'module', 'redirect', 'menu', 'view', 'userlevel', 'rootfile', 'item', 'header' ],);
    
    $self->{config} = $config;
    
    my $APPNAME = $config->{appname};
    PageCamelLogo($APPNAME, $VERSION);
    print "Changing application name to '$APPNAME'\n\n";
    my $isForking = $config->{server}->{forking} || 0;
    my $ps_appname = lc($APPNAME);
    $ps_appname =~ s/[^a-z0-9]+/_/gio;
    
    if($self->{isDebugging} && !$self->{forceSSL}) {
        $config->{server}->{usessl} = 0;
    }
    
    if(!-d '/run/lock/pagecamel') {
        mkdir '/run/lock/pagecamel';
        chmod 0755, '/run/lock/pagecamel';
    }
    
    my $weblockname = "/run/lock/pagecamel_webgui.lock";
    if($config->{server}->{usessl}) {
        $weblockname = "/run/lock/pagecamel_webgui_ssl.lock";
    }
    if($self->{isDebugging}) {
        $weblockname = "/run/lock/pagecamel_webgui_debug.lock";
    }

    if(-f $weblockname) {
        carp("LOCKFILE $weblockname ALREADY EXISTS!");
        carp("REMOVING LOCKFILE $weblockname!");
        unlink $weblockname;
    }


    $0 = $ps_appname;
    
    # ugly hack to provide the files usually provided in @INC during run-time
    # for the basic pagecamel framework files (templates, images, javascript). In
    # most cases, this is whereever the PageCamel framework is unpacked (or installed,
    # if perl runtime with installed PageCamel is available)
    my $extraincpaths = $config->{extraincpaths} || "";
    my @extrainc = split/\;/, $extraincpaths;
    
    my @modlist = @{$config->{module}};
    
    my @runargs;
    
    # Debugging on port 8080 only on 127.0.0.1!
    if($self->{isDebugging}) {
        if($self->{useDebugPort}) {
            $config->{server}->{port} = 8080;
        }
        $isForking = 0;
        if($self->{forceForking}) {
            $isForking = 1;
        }
        $config->{server}->{forking} = $isForking;
        #push @runargs, (host    => '127.0.0.1');
    }

    push @runargs, (lock_file => $weblockname);
    push @runargs, (serialize => 'pipe');
    push @runargs, (SSL_accept_timeout => 10);
    
    if($isForking) {
        push @runargs, %{$config->{server}->{prefork_config}};
        push @runargs, (prefork => 1);
    } else {
        push @runargs, (prefork => 0);
    }
    
    if($config->{server}->{usessl}) {
        if(!defined($config->{server}->{ssldefaultdomain})) {
            croak("SSL ssldefaultdomain not configured!");
        }
        my $defaultdomain = $config->{server}->{ssldefaultdomain};
        if(!defined($config->{server}->{ssldomains}->{$defaultdomain})) {
            croak("SSL domain $defaultdomain not configured");
        }
        if(!-f $config->{server}->{ssldomains}->{$defaultdomain}->{sslkey}) {
            croak("SSL Key file not found! " . $config->{server}->{ssldomains}->{$defaultdomain}->{sslkey});
        }
        if(!-f $config->{server}->{ssldomains}->{$defaultdomain}->{sslcert}) {
            croak("SSL Cert file not found! " . $config->{server}->{ssldomains}->{$defaultdomain}->{sslcert});
        }
        push @runargs, (proto => 'ssl',
                        usessl=>1,
                        SSL_key_file=>  $config->{server}->{ssldomains}->{$defaultdomain}->{sslkey},
                        SSL_cert_file=> $config->{server}->{ssldomains}->{$defaultdomain}->{sslcert},
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
                                    print STDERR "SSL: No Hostname given during SSL setup\n";
                                    return;
                                }

                                if(!defined($config->{server}->{ssldomains}->{$h})) {
                                    print STDERR "SSL: Hostname $h not configured\n";
                                    return;
                                }
                                if($h eq $config->{server}->{ssldefaultdomain}) {
                                    # Already the correct CTX setting, just return
                                    return;
                                }

                                #print STDERR "§§§§§§§§§§§§§§§§§§§§§§§   Requested Hostname: $h §§§\n";
                                my $newctx;
                                if(defined($config->{server}->{ssldomains}->{$h}->{ctx})) {
                                    $newctx = $config->{server}->{ssldomains}->{$h}->{ctx};
                                } else {
                                    $newctx = Net::SSLeay::CTX_new or croak("Can't create new SSL CTX");
                                    Net::SSLeay::CTX_set_cipher_list($newctx, $config->{server}->{sslciphers});
                                    Net::SSLeay::set_cert_and_key($newctx, $config->{server}->{ssldomains}->{$h}->{sslcert},
                                                                        $config->{server}->{ssldomains}->{$h}->{sslkey})
                                            or croak("Can't set cert and key file");
                                    $config->{server}->{ssldomains}->{$h}->{ctx} = $newctx;
                                }
                                Net::SSLeay::set_SSL_CTX($ssl, $newctx);
                            });

                            #    Prepared/tested for future ALPN needs (e.g. HTTP/2)
                            ## Advertise supported HTTP versions
                            #Net::SSLeay::CTX_set_alpn_select_cb($ctx, ['http/1.1', 'http/2.0']);

                        },
                       );
        if(defined($config->{server}->{sslciphers})) {
            push @runargs, (SSL_cipher_list => $config->{server}->{sslciphers});
        }
    }

    if(!$self->{forceSSL} && $self->{isDebugging} || !defined($config->{server}->{bind_adresses})) {
        # fallback to classic behaviour
        # When forceSSL is in use, we assume we want modern behaviour anyway
        push  @runargs, (port => $config->{server}->{port});
    } else {
        my @ports;
        foreach my $address (@{$config->{server}->{bind_adresses}->{item}}) {
            my %item = (
                host    => $address,
                port    => $config->{server}->{port},
                #proto   => 'tcp',
            );
            if($address =~ /\:/) {
                # IPv6 address
                $item{host} = '[' . $address . ']';
            }
            push @ports, \%item;
        }
        push @runargs, (port => \@ports);
    }
    
    #my $webserver = new PageCamel::Web($config->{server}->{port});
    my $webserver = PageCamel::Web->new($isForking);
    $webserver->startconfig($config->{server}, $self->{isDebugging}, $self->{trace}, $ps_appname);
    
    foreach my $module (@modlist) {
        if($self->{isDebugging}) {
            print "(Debug) Going to configure module ", $module->{modname}, "\n";
        }
        $module->{options}->{EXTRAINC} = \@extrainc;
        
        # Notify all modules if we are debugging (for example for "no compression=faster startup")
        $module->{options}->{isDebugging} = $self->{isDebugging};
        $module->{options}->{APPNAME} = $APPNAME;
        $module->{options}->{PSAPPNAME} = $ps_appname;
        
        # Notify all modules if we are using ssl
        $module->{options}->{usessl} = $config->{server}->{usessl};
        
        $webserver->configure_module($module->{modname}, $module->{pm}, %{$module->{options}});
    }
    
    
    $webserver->endconfig();
    
    $self->{runargs} = \@runargs;
    $self->{webserver} = $webserver;
    
    return;
}

sub run {
    my ($self) = @_;
    
    # Let STDOUT/STDERR settle down first
    sleep(0.1);
    
    $self->{webserver}->run(@{$self->{runargs}});
    return;
}

1;
