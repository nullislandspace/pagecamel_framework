package PageCamel::CMDLine::WebBackend;
#---AUTOPRAGMASTART---
use v5.38;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.3;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use IO::Select;
use IO::Socket::UNIX;
use PageCamel::Helpers::ConfigLoader;
use Time::HiRes qw(sleep usleep);
use PageCamel::Helpers::Logo;
use PageCamel::Helpers::DateStrings;
use Sys::Hostname;
use PageCamel::WebBase;
#use POSIX ":sys_wait_h";
use POSIX;

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
    
    $self->init();

    $Carp::Verbose = 1;
    
    return $self;
}

sub init($self) {
    
    print "Loading config file ", $self->{configfile}, "\n";
    my $config = LoadConfig($self->{configfile},
                        ForceArray => [ 'module', 'redirect', 'menu', 'view', 'userlevel', 'rootfile', 'item', 'header' ],);
    
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
    
    # Initialize web base
    $config->{isDebugging} = $self->{isDebugging};
    my $extraincpaths = $config->{extraincpaths} || "";
    my @extrainc = split/\;/, $extraincpaths;
    
    my $webserver = PageCamel::WebBase->new($config);
    
    $webserver->startconfig();

    if(defined($config->{baseprojects})) {
        foreach my $item (@{$config->{baseprojects}->{item}}) {
            $webserver->load_base_project($item);
        }
    }
    
    my @modlist = @{$config->{module}};
    foreach my $module (@modlist) {
        if(0 && $self->{isDebugging}) {
            print "(Debug) Going to configure module ", $module->{modname}, "\n";
        }
        $module->{options}->{EXTRAINC} = \@extrainc;
        
        # Notify all modules if we are debugging (for example for "no compression=faster startup")
        $module->{options}->{isDebugging} = $self->{isDebugging};
        $module->{options}->{APPNAME} = $APPNAME;
        $module->{options}->{PSAPPNAME} = $ps_appname;
        
        # Notify all modules if we are using ssl (make it a TRUE until we can patch out those checks altogether)
        $module->{options}->{usessl} = 1;
        
        $webserver->configure_module($module->{modname}, $module->{pm}, %{$module->{options}});
    }
    
    $webserver->endconfig();
    
    $self->{webserver} = $webserver;
    
    

    if(-S $config->{server}->{internal_socket}) {
        print "*** Removing old websocket\n";
        unlink $config->{server}->{internal_socket};
    }
    print '** Service at Unix Domain Socket ', $config->{server}->{internal_socket}, "\n";
    my $socket = IO::Socket::UNIX->new(
            Type => SOCK_STREAM(),
            Local => $config->{server}->{internal_socket},
            Listen => 1,
    ) or croak("Failed to bind: " . $ERRNO);
    if(defined($config->{server}->{socketcommands})) {
        foreach my $cmd (@{$config->{server}->{socketcommands}->{item}}) {
            print "Running Socket command: $cmd\n";
            `$cmd`;
        }
    }

    binmode($socket, ':bytes');
    my $select = IO::Select->new($socket);
    $self->{select} = $select;
    
    return;
}

sub run($self) {

    while(1) {
        my @connections = $self->{select}->can_read();
        foreach my $connection (@connections) {
            my $client = $connection->accept;
            
            #$self->handleClient($client);
            #next;

            if($childcount >= $self->{config}->{server}->{max_childs}) {
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
                $PROGRAM_NAME = $self->{ps_appname};
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

    print "run() loop finished.\n";
    return;
}

sub handleClient($self, $client) {

    my $ok = 0;

    my $header = $self->readFrontendheader($client);

    # We need to tell all modules if we are using ssl
    $self->{webserver}->set_usessl($header->{ssl});

    $ok = 0;
    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
        $self->{webserver}->child_init_hook();
        $ok = 1;
    };
    if(!$ok) {
        $self->endprogram($header, "!!!!! FAILED child_init_hook $EVAL_ERROR");
    }

    my $allowclient;
    $ok = 0;
    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
        $allowclient = $self->{webserver}->allow_deny_hook($header->{peerhost});
        $ok = 1;
    };
    if(!$ok) {
        $self->endprogram($header, "!!!!! FAILED allow_deny_hook $EVAL_ERROR");
    }

    if($allowclient) {
        if($self->{isDebugging}) {
            $self->{webserver}->process_request($client, $header);
        } else {
            $ok = 0;
            eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                $self->{webserver}->process_request($client, $header);
                $ok = 1;
            };
            if(!$ok) {
                $self->endprogram($header, "!!!!! FAILED process_request $EVAL_ERROR");
            }
        }
    }
    
    $ok = 0;
    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
        $self->{webserver}->post_process_request_hook();
        $ok = 1;
    };

    if(!$ok) {
        $self->endprogram($header, "!!!!! FAILED post_process_request_hook $EVAL_ERROR");
    }
    
    $ok = 0;
    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
        $self->{webserver}->child_finish_hook();
        $ok = 1;
    };
    if(!$ok) {
        $self->endprogram($header, "!!!!! FAILED child_finish_hook $EVAL_ERROR");
    }


    $ok = 0;
    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
        $client->close();
        kill 'USR1', $header->{pid}; # Notify frontend that we are done

        #print "Done with client PID $PID\n";
        $ok = 1;
    };

    if(!$ok) {
        $self->endprogram($header, "!!!!! FAILED stopping process $EVAL_ERROR");
    }


    $self->endprogram($header, "exit(0)");
}

sub endprogram($self, $header, $debugmessage) {

    if($debugmessage !~ /exit\(0\)/) {
        print STDERR "EVAL ERROR: ", $debugmessage, "\n";
    }

    kill 'USR1', $header->{pid}; # Notify frontend that we are done
    #exit(0);

    sleep(1);
    while(1) {
        kill 9, $PID;
        POSIX::_exit(0); # Don't run END{} / DESTROY{} handlers and stuff
        sleep(10);
    }
}

sub readFrontendheader($self, $client) {

    my $line = '';
    while(1) {
        my $temp;
        $client->sysread($temp, 1);
        if(!defined($temp) || !length($temp)) {
            sleep(0.05);
            next;
        }
        if($temp eq "\r") {
            next;
        }

        if($temp eq "\n") {
            last;
        }
        $line .= $temp;
    }

    my @parts = split/\ /, $line;
    my %header = (
        # "PAGECAMEL $lhost $lport $peerhost $peerport $usessl $PID HTTP/1.1
        progname => $parts[0],
        lhost => $parts[1],
        lport => $parts[2],
        peerhost => $parts[3],
        peerport => $parts[4],
        ssl => $parts[5],
        pid => $parts[6],
        httpversion => $parts[7],
    );

    return \%header;
}

1;
