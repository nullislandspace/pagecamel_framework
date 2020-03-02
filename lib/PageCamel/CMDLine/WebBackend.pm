package PageCamel::CMDLine::WebBackend;
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

use IO::Select;
use IO::Socket::UNIX;
use PageCamel::Helpers::ConfigLoader;
use Time::HiRes qw(sleep usleep);
use PageCamel::Helpers::Logo;
use Data::Dumper;
use Sys::Hostname;
use POSIX ":sys_wait_h";

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
    
    my $weblockname = "/run/lock/pagecamel_webgui_backend.lock";

    if(-f $weblockname) {
        carp("LOCKFILE $weblockname ALREADY EXISTS!");
        carp("REMOVING LOCKFILE $weblockname!");
        unlink $weblockname;
    }

    # FIXME Add exclusive locked open for $weblockname


    $PROGRAM_NAME = $ps_appname;


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
    binmode($socket, ':bytes');
    my $select = IO::Select->new($socket);
    $self->{select} = $select;
    
    return;
}

sub run {
    my ($self) = @_;

    while(1) {
        while((my @connections = $self->{select}->can_read)) {
            foreach my $connection (@connections) {
                my $client = $connection->accept;

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

    print "Doing some network stuff in child PID $PID\n";

    my $header = $self->readFrontendheader($client);
    print Dumper($header);

    $client->syswrite("BLA!!!!!\n");
    sleep(1);
    $client->close();
    kill 'USR1', $header->{pid}; # Notify frontend that we are done

    print "Done with client PID $PID\n";


    exit(0);
}

sub readFrontendheader {
    my ($self, $client) = @_;

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
        usessl => $parts[5],
        pid => $parts[6],
        httpversion => $parts[7],
    );

    return \%header;
}
