package PageCamel::CMDLine::DNS;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.0;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
use feature 'signatures';
no warnings qw(experimental::signatures);
#---AUTOPRAGMAEND---

use PageCamel::Helpers::ConfigLoader;
use Time::HiRes qw(sleep usleep);
use PageCamel::Helpers::Logo;
use Sys::Hostname;
use PageCamel::DNS;

sub new {
    my ($class, $isDebugging, $isVerbose, $configfile) = @_;
    my $self = bless {}, $class;

    $self->{isDebugging} = $isDebugging;
    $self->{isVerbose} = $isVerbose;
    $self->{configfile} = $configfile;

    return $self;
}

sub init {
    my ($self) = @_;

    print "Loading config file ", $self->{configfile}, "\n";
    my $config = LoadConfig($self->{configfile},
                        ForceArray => [ 'module', 'redirect', 'menu', 'view', 'userlevel', 'rootfile', 'item', 'columnprefix', ],);

    $self->{config} = $config;

    my $APPNAME = $config->{appname};
    PageCamelLogo($APPNAME, $VERSION);
    print "Changing application name to '$APPNAME'\n\n";
    my $ps_appname = lc($APPNAME);
    $ps_appname =~ s/[^a-z0-9]+/_/gio;
    if($self->{isDebugging}) {
        $ps_appname .= '_debug';
    }

    $PROGRAM_NAME = $ps_appname;

    my @runargs;

    # Debugging on port 5300 only on 127.0.0.1!
    if(0 && $self->{isDebugging}) {
        $config->{server}->{port} = 5300;
    }

    push @runargs, %{$config->{server}->{prefork_config}};

    if(0 && ($self->{isDebugging} || !defined($config->{server}->{bind_adresses}))) {
        # fallback to classic behaviour
        push  @runargs, (port => $config->{server}->{port}, proto => 'udp');
        push  @runargs, (port => $config->{server}->{port}, proto => 'tcp');
    } else {
        my @ports;
        foreach my $address (@{$config->{server}->{bind_adresses}->{item}}) {
            if($address =~ /\:/) {
                # quote IPv6 address
                $address = '[' . $address . ']';
            }
            my %udpitem = (
                host    => $address,
                port    => $config->{server}->{port},
                proto   => 'udp',
            );
            my %tcpitem = (
                host    => $address,
                port    => $config->{server}->{port},
                proto   => 'tcp',
            );
            push @ports, \%udpitem;
            push @ports, \%tcpitem;
        }
        push @runargs, (port => \@ports);
    }

    my $hname = hostname;
    PageCamel::DNS::setThreadingMode($self->{isDebugging});
    my $nameserver = PageCamel::DNS->new();
    $nameserver->doConfig($self->{isDebugging}, $self->{isVerbose}, $config->{$hname}, $config);

    $self->{runargs} = \@runargs;
    $self->{nameserver} = $nameserver;

    return;
}

sub run {
    my ($self) = @_;

    # Let STDOUT/STDERR settle down first
    sleep(0.1);

    my $ok = 0;
    eval {
        $self->{nameserver}->run(@{$self->{runargs}});
        $ok = 1;
    };
    if(!$ok) {
        print STDERR "ERROR: ", $EVAL_ERROR, "\n";
    }
    return;
}

1;
