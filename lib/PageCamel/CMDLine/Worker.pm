package PageCamel::CMDLine::Worker;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.3;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
use Data::Dumper;
#---AUTOPRAGMAEND---

use PageCamel::Worker;
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::ConfigLoader;
use PageCamel::Helpers::Logo;
use Time::HiRes qw(sleep time);

sub new {
    my ($class, $isDebugging, $configfile) = @_;
    my $self = bless {}, $class;
    
    $self->{isDebugging} = $isDebugging;
    $self->{configfile} = $configfile;
    
    croak("Config file $configfile not found!") unless(-f $configfile);
    
    return $self;
}


sub init {
    my ($self) = @_;
    
    my $worker = PageCamel::Worker->new();
    
    print "Loading config file ", $self->{configfile}, "\n";
    
    my $config = LoadConfig($self->{configfile},
                        ForceArray => [ 'module', 'directory', 'reciever', 'users', 'sourceip', 'item', 'argument', 'crop' ],);
    
    
    my $APPNAME = $config->{appname};
    PageCamelLogo($APPNAME, $VERSION);
    print "Changing application name to '$APPNAME'\n\n";
    my $ps_appname = lc($APPNAME);
    $ps_appname =~ s/[^a-z0-9]+/_/gio;
    $PROGRAM_NAME = $ps_appname;
    
    # set required values to default if they don't exist
    if(!defined($config->{mincycletime})) {
        $config->{mincycletime} = 10;
    }
    
    
    my @modlist = @{$config->{module}};
    
    $worker->startconfig($self->{isDebugging});
    
    
    foreach my $module (@modlist) {
        # Notify all modules if we are debugging (for example for "no compression=faster startup")
        $module->{options}->{isDebugging} = $self->{isDebugging};
        $module->{options}->{APPNAME} = $APPNAME;
        $module->{options}->{PSAPPNAME} = $ps_appname;
        
        $worker->configure($module->{modname}, $module->{pm}, %{$module->{options}});
    }
    
    $worker->endconfig();
    
    $self->{worker} = $worker;
    $self->{config} = $config;
    $self->{ps_appname} = $ps_appname;
    
    
    return;
}

sub run {
    my ($self) = @_;
    
    # Let STDOUT/STDERR settle down first
    sleep(0.1);
    
    my $nextCycleTime = $self->{config}->{mincycletime} + time;
    while(1) {
        my $workCount = $self->{worker}->run();
    
        my $now = time;
        if($now < $nextCycleTime) {
            my $sleeptime = $nextCycleTime - $now;
            #print "** Fast cycle ($sleeptime sec to spare), sleeping **\n";
            sleep($sleeptime);
            $nextCycleTime += $self->{config}->{mincycletime};
            #print "** Wake-up call **\n";
        } else {
            #print "** Slow cycle **\n";
            $nextCycleTime = $self->{config}->{mincycletime} + $now;
        }
    }
    
    return;
}

1;
