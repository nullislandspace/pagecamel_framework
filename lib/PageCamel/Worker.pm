package PageCamel::Worker;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.6;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---
use Module::Load;

#=!=START-AUTO-INCLUDES
use PageCamel::Worker::AXFRSync;
use PageCamel::Worker::Accesslog;
use PageCamel::Worker::AdminCommands;
use PageCamel::Worker::AutoScheduler;
use PageCamel::Worker::BackupCommand;
use PageCamel::Worker::BaseModule;
use PageCamel::Worker::Clacks::Bridge;
use PageCamel::Worker::Clacks::LocalCache;
use PageCamel::Worker::ClacksCache;
use PageCamel::Worker::Commands;
use PageCamel::Worker::DNSCache;
use PageCamel::Worker::Debuglog2DB;
use PageCamel::Worker::DirCleaner;
use PageCamel::Worker::DirSync::Scheduler;
use PageCamel::Worker::DirSync::SyncLinux;
use PageCamel::Worker::DynDNSCommand;
use PageCamel::Worker::DynamicFiles::Blob;
use PageCamel::Worker::DynamicFiles::External;
use PageCamel::Worker::ExtraConfig;
use PageCamel::Worker::Firewall::BadBot;
use PageCamel::Worker::Firewall::BlockCIDRWhois;
use PageCamel::Worker::Firewall::DNS;
use PageCamel::Worker::Firewall::Dovecot;
use PageCamel::Worker::Firewall::Floodcheck;
use PageCamel::Worker::Firewall::Honeypot;
use PageCamel::Worker::Firewall::IPTables;
use PageCamel::Worker::Firewall::PermaBlock;
use PageCamel::Worker::Firewall::Postfix;
use PageCamel::Worker::Firewall::SSH;
use PageCamel::Worker::Firewall::SyslogForwarder;
use PageCamel::Worker::ForceVacuumAnalyze;
use PageCamel::Worker::Foscam::Stream;
use PageCamel::Worker::HomeAutomation::Allnet4076;
use PageCamel::Worker::HomeAutomation::FritzBox;
use PageCamel::Worker::HomeAutomation::HWGSTE;
use PageCamel::Worker::HomeAutomation::KeepRange;
use PageCamel::Worker::HomeAutomation::PowerShare;
use PageCamel::Worker::HomeAutomation::ResetDevice;
use PageCamel::Worker::HomeAutomation::Tasmota;
use PageCamel::Worker::HomeAutomation::Timer;
use PageCamel::Worker::Logging::PluginBase;
use PageCamel::Worker::Logging::Plugins::DummyPlugin;
use PageCamel::Worker::Logging::Plugins::PageCamelStats;
use PageCamel::Worker::Logging::Plugins::Ping;
use PageCamel::Worker::Logging::Plugins::Raid3ware;
use PageCamel::Worker::Logging::Plugins::RaidMega;
use PageCamel::Worker::Logging::Plugins::SmartStatus;
use PageCamel::Worker::Logging::Plugins::SystemStatus;
use PageCamel::Worker::Logging::Plugins::TempSensor_HWG_STE;
use PageCamel::Worker::Logging::Scheduler;
use PageCamel::Worker::MYCPAN::AutoScheduler;
use PageCamel::Worker::MYCPAN::LocalCommands;
use PageCamel::Worker::Minecraft::Mapcrafter;
use PageCamel::Worker::Minecraft::PlayerCoords;
use PageCamel::Worker::Minecraft::RCON;
use PageCamel::Worker::PostfixCommands;
use PageCamel::Worker::PostgresDB;
use PageCamel::Worker::Reporting;
use PageCamel::Worker::SendMail;
use PageCamel::Worker::SerialCommands;
use PageCamel::Worker::SystemSettings;
use PageCamel::Worker::TableStatistics;
use PageCamel::Worker::Twitter::BlogTweet;
use PageCamel::Worker::Twitter::HistoryTweet;
use PageCamel::Worker::Twitter::TweetOutbox;
use PageCamel::Worker::Wansview::Stream;
#=!=END-AUTO-INCLUDES


sub new {
    my $class = shift;
    my $self = bless {}, $class;

    return $self;
}

sub startconfig {
    my ($self, $isDebug) = @_;

    if(!defined($isDebug)) {
        $isDebug = 0;
    }
    $self->{debug} = $isDebug;

    my @workers;
    $self->{workers} = \@workers;

    my @cleanup;
    $self->{cleanup} = \@cleanup;

    my %tmpModules;
    $self->{modules} = \%tmpModules;

    return;
}

sub configure {
    my ($self, $modname, $perlmodulename, %config) = @_;

    # Let the module know its configured module name...
    $config{modname} = $modname;

    # ...what perl module it's supposed to be...
    my $perlmodule = "PageCamel::Worker::$perlmodulename";
    if(!defined($perlmodule->VERSION)) {
        print "Dynamically loading $perlmodule...\n";
        load $perlmodule;
    }

    # Check again
    if(!defined($perlmodule->VERSION)) {
        croak("$perlmodule not loaded");
    }
    
    # Module must be the same version as this module
    if($perlmodule->VERSION ne $VERSION) {
        croak("$perlmodule has version " . $perlmodule->VERSION . " but we need $VERSION");
    }

    $config{pmname} = $perlmodule;

    # and its parent
    $config{server} = $self;

    if(defined($self->{modules}->{$modname})) {
        croak("Module with name '$modname' already configured!");
    }

    $self->{modules}->{$modname} = $perlmodule->new(%config);
    $self->{modules}->{$modname}->register; # Register handlers provided by the module
    print "Module $modname ($perlmodule) configured.\n";
    return;
}

sub endconfig {
    my ($self) = @_;

    #$self->{modules}->{$modname}->reload;   # (Re)load module's data
    print "Guidance is internal!\n"; # We REQUIRE an Apollo reference here!!1!
    print "Cross registering modules...\n";
    foreach my $modname (keys %{$self->{modules}}) {
        print "  crossregistering for $modname\n";
        $self->{modules}->{$modname}->crossregister;   # Reload module's data
    }
    print "Loading dynamic data...\n";
    foreach my $modname (keys %{$self->{modules}}) {
        print "  Loading data for $modname\n";
        $self->{modules}->{$modname}->reload;   # Reload module's data
    }
    print "Data loaded - calling endconfig...\n";
    foreach my $modname (keys %{$self->{modules}}) {
           $self->{modules}->{$modname}->endconfig;   # finish up configuration and prepare for cycling
    }
    print "Done.\n";

    print "\n";
    print "Startup configuration complete!\n\n";
    print "+------------------------------------+\n";
    print "| We are GO for auto-sequence start! |\n";
    print "+------------------------------------+\n\n";
    return;
}

sub run {
    my ($self) = @_;

    my $workCount = 0;

    # Run cleanup functions in case the last cycle bailed out with croak
    foreach my $worker (@{$self->{cleanup}}) {
        my $module = $worker->{Module};
        my $funcname = $worker->{Function} ;

        #$workCount += $module->$funcname();
        $module->$funcname();
    }

    # Run all worker functions
    foreach my $worker (@{$self->{workers}}) {
        my $module = $worker->{Module};
        my $funcname = $worker->{Function} ;

        $workCount += $module->$funcname();
    }

    # Run cleanup functions
    foreach my $worker (@{$self->{cleanup}}) {
        my $module = $worker->{Module};
        my $funcname = $worker->{Function} ;

        #$workCount += $module->$funcname();
        $module->$funcname();
    }

    return $workCount;
}

sub add_worker {
    my ($self, $module, $funcname) = @_;

    my %conf = (
        Module  => $module,
        Function=> $funcname
    );

    push @{$self->{workers}}, \%conf;
    return;
}

sub add_cleanup {
    my ($self, $module, $funcname) = @_;

    my %conf = (
        Module  => $module,
        Function=> $funcname
    );

    push @{$self->{cleanup}}, \%conf;
    return;
}

1;
__END__

=head1 NAME

PageCamel::Worker -

=head1 SYNOPSIS

  use PageCamel::Worker;



=head1 DESCRIPTION



=head2 new



=head2 startconfig



=head2 configure



=head2 endconfig



=head2 run



=head2 add_worker



=head2 add_cleanup



=head1 IMPORTANT NOTE

This module is part of the PageCamel framework. Currently, only limited support
and documentation exists outside my DarkPAN repositories. This source is
currently only provided for your reference and usage in other projects (just
copy&paste what you need, see license terms below).

To see PageCamel in action and for news about the project,
visit my blog at L<https://cavac.at>.

=head1 AUTHOR

Rene Schickbauer, E<lt>pagecamel@cavac.atE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
