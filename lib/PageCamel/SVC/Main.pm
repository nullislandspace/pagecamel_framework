package PageCamel::SVC::Main;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---
# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license

use Unix::PID;
use DBI;
use Cwd;
use PageCamel::SVC::Settings;
use Time::HiRes qw[sleep];
use Net::Clacks::Client;
use PageCamel::Helpers::Logo;

sub new {
    my ($class, $isService, $basePath, $db, $clacks,
        $APPNAME, $APPVERSION) = @_;
    PageCamelLogo($APPNAME, $APPVERSION);
    my $self = bless {}, $class;

    $self->{APPNAME} = $APPNAME;
    $self->{APPVERSION} = $APPVERSION;
    $self->{isService} = $isService;

    $basePath =~ s/\//\\/g; # Convert to Win32 Path
    $self->{basePath} = $basePath;
    $self->{db} = $db;
    $self->{clacksconf} = $clacks;

    if(defined($self->{clacksconf}->{socket}) && $self->{clacksconf}->{socket} ne '') {
        $self->{clacks} = Net::Clacks::Client->newSocket($self->{clacksconf}->{socket},
                                                   $self->{clacksconf}->{user},
                                                   $self->{clacksconf}->{password},
                                                   "PageCamelSVC $APPVERSION");
    } else {
        $self->{clacks} = Net::Clacks::Client->new($self->{clacksconf}->{host},
                                                   $self->{clacksconf}->{port},
                                                   $self->{clacksconf}->{user},
                                                   $self->{clacksconf}->{password},
                                                   "PageCamelSVC $APPVERSION");
    }
    $self->{clacks}->store("VERSION::" . $APPNAME, $APPVERSION);
    $self->{clacks}->remove("StopSVC");
    $self->{clacks}->doNetwork();
    $self->{is_configured} = 0;


    $self->checkDatabase();
    if(!defined($self->{dbh})) {
        croak("Can't connect to database");
    }
    $self->{sysh} = PageCamel::SVC::Settings->new($self->{dbh}, $self->{clacks});

    $self->{sysh}->set_softupdates(0);

    $self->{nextkeepalive} = 0;


    return $self;
}

sub checkDatabase($self) {

    if(defined($self->{dbh}) && !$self->{dbh}->ping) {
        $self->{dbh}->disconnect;
        delete $self->{dbh};
    }
    if(!defined($self->{dbh})) {
        my $dbh = DBI->connect($self->{db}->{dburl}, $self->{db}->{dbuser}, $self->{db}->{dbpassword}, {AutoCommit => 0, RaiseError => 0});
        if(defined($dbh)) {
            $self->{dbh} = $dbh;

            my $appname = $self->{APPNAME} . "/Main.pm $PID";
            if($dbh->do("SET application_name = '$appname'; ")) {
                $dbh->commit;
            }
        }
    }

    return;
}

sub setRealPerlBinary($self, $binary) {

    print "** SETTING REAL PERL BINARY TO $binary **\n";
    $self->{realperlbinary} = $binary;
    return;
}

sub requestStop($self) {

    my $tmp = 1;
    $self->{clacks}->store("StopSVC", $tmp);
    return;
}

sub shouldStop($self) {

    my $stop = $self->{clacks}->retrieve("StopSVC");
    if(!defined($stop) || $stop != 1){
        return 0;
    } else {
        return 1;
    }

}

sub setServerStatus($self, $status) {

    $self->{clacks}->store("SVCRunningStatus", $status);
    return;
}

sub getServerStatus($self) {

    my $status = $self->{clacks}->retrieve("SVCRunningStatus");
    if(!defined($status)){
        return "stopped";
    } else {
        return $status;
    }

}

sub startconfig($self) {

    $self->{apps} = ();
    $self->{startup_scripts} = ();
    $self->{shutdown_scripts} = ();
    return;
}

sub configure_module($self, $module) {

    print "Configuring module " . $module->{description} . "...\n";
    $module->{handle} = undef;

    my $fullapp = $module->{app};
    if(defined($self->{realperlbinary}) && $fullapp =~ /^perl\ /) {
        my $realperl = $self->{realperlbinary};
        $fullapp =~ s/^perl /$realperl /g;
    }
    $module->{app} = $fullapp;

    my $fullconf = $module->{conf};
    $module->{conf} = $fullconf;

    my $setname = lc $module->{description};
    $setname =~ s/[^a-z0-9]/_/g;

    $module->{enable_name} = $setname . '_enable';
    $module->{status_name} = $setname . '_status';
    $module->{clacks_name} = 'pagecamel_services::' . $setname . '_status';
    $module->{short_name} = $setname;
    print "      servicename: $setname\n";

    $self->{sysh}->createBool(modulename => 'pagecamel_services',
                        settingname => $module->{enable_name},
                        settingvalue => "1",
                        description => 'Enables pagecamel service ' . $module->{description},
                        processinghints => [
                            'type=switch',
                            'modulename=' . $module->{description},
                                            ])
            or print STDERR "Failed to create setting " . $module->{enable_name} . "!";
    $self->{dbh}->rollback;

    $self->{sysh}->createBool(modulename => 'pagecamel_services',
                        settingname => $module->{status_name},
                        settingvalue => "0",
                        description => 'pagecamel service ' . $module->{description} . ' status',
                        processinghints => [
                            'type=led',
                            'modulename=' . $module->{description},
                                            ])
            or print STDERR "Failed to create setting " . $module->{status_name} . "!";
    $self->{dbh}->rollback;


    push @{$self->{apps}}, $module;
    return;
}

sub configure_startup($self, $command) {

    $command =~ s/\//\\/g;
    push @{$self->{startup_scripts}}, $command;
    return;
}

sub configure_shutdown($self, $command) {

    $command =~ s/\//\\/g;
    push @{$self->{shutdown_scripts}}, $command;
    return;
}


sub endconfig($self) {
    $self->{shutdown_complete} = 1;
    $self->{is_configured} = 1;
    return;

}

sub startup($self) {

    # "Don't fear the Reaper"
    $SIG{CHLD} = 'IGNORE';

    my $ps_appname = lc($self->{APPNAME});
    $ps_appname =~ s/[^a-z0-9]+/_/gio;
    print "Changing ps app name to '$ps_appname'\n\n";
    $PROGRAM_NAME = $ps_appname;

    foreach my $script (@{$self->{startup_scripts}}) {
        $self->run_script($script);
    }
    print "Startup scripts complete\n";

    # Listen to certain clacks commands
    $self->{clacks}->listen('pagecamel_services::set_all');
    $self->{clacks}->listen('pagecamel_services::restart::service');
    $self->{clacks}->listen('pagecamel_services::enable::service');
    $self->{clacks}->listen('pagecamel_services::disable::service');
    $self->{clacks}->listen('pagecamel_services::LIFETICK');

    # Set status bit to "not started"
    foreach my $app (@{$self->{apps}}) {
        my ($ok, $refshouldrun) = $self->{sysh}->get('pagecamel_services', $app->{enable_name}, 1); # $forcedb = 1
        $self->{sysh}->set('pagecamel_services', $app->{status_name}, 0);
        if($ok && $refshouldrun->{settingvalue}) {
            $self->{clacks}->set($app->{clacks_name}, 2);
        } else {
            $self->{clacks}->set($app->{clacks_name}, 0);
        }

        $self->{clacks}->doNetwork();

        # Do NOT start all apps during startup, let them be handled by normal "work" callback
        #$self->check_app($app);
        #$self->handleClacksCommands();
    }

    print "Initial startup complete\n";
    $self->{shutdown_complete} = 0;

    # Enable soft updates to reduce postgresql calls to merge_systemsettings()
    $self->{sysh}->set_softupdates(1);

    return;
}

# Rewrote work() to cycle through the apps, only working on ONE per workcycle. It cycles through the
# apps in a round-robin fashion, so a single always-crashing app doesn't stop "later" apps from getting proper
# treatment.
# This should also allow better interactivity during startup. 
# Rewrote again: Still CHECK all apps round-robin if there is work to be done, until we either
# do a full loop-around or we find ONE that needed stuff to be done to it. This will give a better
# response time, since we don't have to wait a full loop time for a single app to be started/stopped.
sub work($self) {

    my $workCount = 0;

    if(!defined($self->{nextappindex})) {
        $self->{nextappindex} = 0;
    }

    $self->{clacks}->ping();
    $self->{clacks}->doNetwork();
    $workCount += $self->handleClacksCommands();

    {
        my $currentappindex = $self->{nextappindex};
        while(1) {
            my $app = $self->{apps}->[$self->{nextappindex}];
            $self->{nextappindex}++;
            if($self->{nextappindex} == scalar @{$self->{apps}}) {
                $self->{nextappindex} = 0;
            }

            my $didwork = $self->check_app($app);
            $self->{clacks}->doNetwork();

            if($didwork) {
                $workCount++;
                last;
            }

            if($self->{nextappindex} == $currentappindex) {
                last;
            }
        }
    }


    # Update ALL app states (only write if status actually changed)
    foreach my $app (@{$self->{apps}}) {
        my $oldstate = $self->{clacks}->retrieve($app->{clacks_name});
        if(!defined($oldstate)) {
            $oldstate = -1;
        }
        my $newstate = 0;
        my $running = defined($app->{handle});
        my ($ok, $refshouldrun) = $self->{sysh}->get('pagecamel_services', $app->{enable_name});

        if($running) {
            $self->{clacks}->setAndStore($app->{clacks_name}, 1);
            $newstate = 1;
        } elsif($ok && $refshouldrun->{settingvalue}) {
            $self->{clacks}->setAndStore($app->{clacks_name}, 2);
            $newstate = 2;
        } else {
            $self->{clacks}->setAndStore($app->{clacks_name}, 0);
            $newstate = 0;
        }
        if($newstate != $oldstate) {
            $self->{clacks}->setAndStore($app->{clacks_name}, $newstate);
        }
    }
    $self->{clacks}->ping();
    $self->{clacks}->doNetwork();

    return $workCount;
}

sub handleClacksCommands($self) {

    my $workCount = 0;
    my $done = 0;

    my $now = time;
    if($now > $self->{nextkeepalive}) {
        $self->{clacks}->notify('pagecamel_services::lifetick');
        $self->{clacks}->doNetwork();
        $self->{nextkeepalive} = $now + 10;
    }

    $self->{clacks}->doNetwork();

    while(1) {
        my $command = $self->{clacks}->getNext();
        last unless(defined($command));

        if($command->{type} eq 'notify') {
            if($command->{name} eq 'pagecamel_services::set_all') {
                foreach my $app (@{$self->{apps}}) {
                    my $running = defined($app->{handle});
                    my ($ok, $refshouldrun) = $self->{sysh}->get('pagecamel_services', $app->{enable_name});
                    if($running) {
                        $self->{clacks}->set($app->{clacks_name}, 1);
                    } elsif($ok && $refshouldrun->{settingvalue}) {
                        $self->{clacks}->set($app->{clacks_name}, 2);
                    } else {
                        $self->{clacks}->set($app->{clacks_name}, 0);
                    }
                    $self->{clacks}->set($app->{clacks_name}, defined($app->{handle}));
                }
                $self->{clacks}->ping();
                $self->{clacks}->doNetwork();
                $workCount++;
            }
        } elsif($command->{type} eq 'set') {
            if($command->{name} eq 'pagecamel_services::restart::service') {
                foreach my $app (@{$self->{apps}}) {
                    if($command->{data} eq $app->{short_name}) {
                        my ($ok, $refshouldrun) = $self->{sysh}->get('pagecamel_services', $app->{enable_name});
                        my $shouldrun;
                        if(!$ok) {
                            # Default on error: Run service (same as on old system)
                            $shouldrun = 1;
                        } else {
                            $shouldrun = $refshouldrun->{settingvalue};
                        }

                        if(!$shouldrun) {
                            # Can not reset stopped APP
                            print "Got RESET for ", $command->{data}, " but APP is disabled.\n";
                            next;
                        }
                        print "Killing APP ", $command->{data}, " due to RESET request...\n";
                        $self->kill_app($app);
                        $self->{clacks}->set($app->{clacks_name}, 4); # light blue-green to show this was a manual reset
                        $self->{clacks}->doNetwork();
                        print "DONE.\n";
                    }
                }
                $workCount++;
            } elsif($command->{name} eq 'pagecamel_services::enable::service') {
                foreach my $app (@{$self->{apps}}) {
                    if($command->{data} eq $app->{short_name}) {
                        $self->{sysh}->set('pagecamel_services', $app->{enable_name}, 1);
                        last;
                    }
                }
                $workCount++;
            } elsif($command->{name} eq 'pagecamel_services::disable::service') {
                foreach my $app (@{$self->{apps}}) {
                    if($command->{data} eq $app->{short_name}) {
                        $self->{sysh}->set('pagecamel_services', $app->{enable_name}, 0);
                        last;
                    }
                }
                $workCount++;
            } elsif($command->{name} eq 'pagecamel_services::LIFETICK') {
                my ($processid, $apptick) = split/\ /, $command->{data};
                foreach my $app (@{$self->{apps}}) {
                    next unless(defined($app->{handle}));
                    next unless(defined($app->{apptick}));
                    if($processid == $app->{handle}) {
                        $app->{apptick} = $apptick;
                    }
                }
                $workCount++;
            }
        } elsif($command->{type} eq 'disconnect') {
            # Try to reconnect
            $self->{clacks}->doNetwork();

            # and listen (again) to certain clacks commands
            $self->{clacks}->listen('pagecamel_services::set_all');
            $self->{clacks}->listen('pagecamel_services::restart::service');
            $self->{clacks}->listen('pagecamel_services::enable::service');
            $self->{clacks}->listen('pagecamel_services::disable::service');
            $self->{clacks}->listen('pagecamel_services::LIFETICK');

            $self->{clacks}->doNetwork();
        }
    }

    return $workCount;
}

sub shutdownsvc($self) {

    if($self->{is_configured} == 1) {
        print "Shutdown started.\n";

        foreach my $app (reverse @{$self->{apps}}) {
            $self->stop_app($app);
        }

        print "Apps shut down.\n";

        foreach my $script (@{$self->{shutdown_scripts}}) {
            $self->run_script($script);
        }
        print "Shutdown scripts complete\n";
    }
    $self->{shutdown_complete} = 1;
    return;
}

sub disable_service($self, $svcname) {

    $self->{sysh}->set('pagecamel_services', $svcname . '_enable', 0);
    return;
}

sub enable_service($self, $svcname) {

    $self->{sysh}->set('pagecamel_services', $svcname . '_enable', 1);
    return;
}

sub check_service($self, $svcname) {

    my ($ok, $refstatus) = $self->{sysh}->get('pagecamel_services', $svcname . '_status');

    if(!$ok) {
        return -1;
    }
    return $refstatus->{settingvalue};
}

sub check_app($self, $app) {


    my ($ok, $refshouldrun) = $self->{sysh}->get('pagecamel_services', $app->{enable_name});
    if(!$ok) {
        # Oh well, something happened. Ignore this $app until the next cycle
        return 0;
    }
    my $shouldrun = $refshouldrun->{settingvalue};

    if(0 && $app->{status_name} eq 'demo_pos_worker_status') {
        print $app->{status_name}, ": Shouldrun: ", $shouldrun, " Running: ", defined($app->{handle}), "\n";
    }
    if($shouldrun && !defined($app->{handle})) {
        $self->{clacks}->set($app->{clacks_name}, 2); # Blue
        $self->{clacks}->doNetwork();
        $self->start_app($app);
        return 1;
    }

    if(!$shouldrun && defined($app->{handle})) {
        return $self->stop_app($app);
    }

    if(!$shouldrun) {
        # App not running and it shouldn't run anyway, just return with "did nothing"
        return 0;
    }


    my $checker = Unix::PID->new();

    # First, check if the process exited
    if(!defined($app->{handle}) || !$checker->is_pid_running($app->{handle})) {
        # Process exited, so, restart
        $self->{clacks}->set($app->{clacks_name}, 2); # Blue
        $self->{sysh}->set('pagecamel_services', $app->{status_name}, 0);
        $self->{clacks}->doNetwork();
        print "Process exit detected: " . $app->{description} . "!\n";
        $self->start_app($app);
        return 1;
    }

    if(!defined($app->{lifetick}) || $app->{lifetick} == 0) {
        #$self->{clacks}->set($app->{clacks_name}, 1);
        $self->{sysh}->set('pagecamel_services', $app->{status_name}, 1);
        return 0;
    } else {
        # Process itself is still running, so check its lifetick
        # to see if it hangs
        my $pid = $app->{handle};
        my $apptick = $app->{apptick};
        if($apptick == -1) {
            # Client requested a temporary suspension of lifetick handling
            $self->{clacks}->set($app->{clacks_name}, 1);
            $self->{sysh}->set('pagecamel_services', $app->{status_name}, 1);
            $self->{clacks}->doNetwork();
            return 0;
        }
        my $tickage = time - $apptick;
        if($tickage > $app->{lifetick}) {
            # Stale lifetick
            print "Stale Lifetick detected: " . $app->{description} . "!\n";
            $self->{sysh}->set('pagecamel_services', $app->{status_name}, 0);
            $self->kill_app($app);
            $self->{clacks}->set($app->{clacks_name}, 3); # Purple ("lifetick error")
            $self->{clacks}->doNetwork();

            # Don't start app immediately, let it start "naturally" in the course of cycling through all apps
            #$self->start_app($app);
            return 1;
        } else {
            return 0;
        }

    }

    return 0;
}

sub start_app($self, $app) {

    my $pid = fork();

    if($pid) {
        #parent
        print "Forked " . $app->{app} . " has PID $pid\n";
        $app->{handle} = $pid;
        $app->{apptick} = -1;
        if($app->{lifetick} > 0) {
            # Make sure we start checking apptick right away after starting the application. This prevents indefinite hangs on startup of applications
            $app->{apptick} = time;
        }

        #for(1..3) {
            sleep(1); # Sleep a few seconds to allow the application to start up without
                      # too much conflicts with PageCamelSVC and other services to be started
            $self->{clacks}->doNetwork();
        #}
        $self->{sysh}->set('pagecamel_services', $app->{status_name}, 1);
        $self->{clacks}->set($app->{clacks_name}, 1);
        $self->{clacks}->doNetwork();
    } else {
        # Child
        print "Running command ", $app->{app}, " ", $app->{conf}, "\n";
        if(defined($ENV{PC_SVC_VERBOSE}) && $ENV{PC_SVC_VERBOSE} eq '1') {
            # Don't reroute STDOUT / STDERR
        } else {
            open STDOUT, ">",  "/dev/null" or croak("$PROGRAM_NAME: open: $ERRNO");
            open STDERR, ">&", \*STDOUT    or exit 1;
        }
        eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
            exec($app->{app} . " " . $app->{conf});
        };
        exec('false');
        print "Child done\n";
        exit(0);
    }
    return;
}

sub stop_app($self, $app) {

    $self->{sysh}->set('pagecamel_services', $app->{status_name}, 0);
    $self->{clacks}->set($app->{clacks_name}, 0);
    $self->{clacks}->doNetwork();
    if(defined($app->{handle}) && $app->{handle}) {
        my $pid = $app->{handle};
        print "Killing app " . $app->{description} . " with PID $pid...\n";
        kill 15, $pid; # SIGTERM

        my $countdown = 4;
        my $checker = Unix::PID->new();
        while($checker->is_pid_running($app->{handle})) {
            sleep 0.5;
            $countdown -= 0.5;
            if($countdown <= 0) {
                print "    force-killing\n";
                kill 9, $pid;  #SIGKILL
                last;
            }
            print "    waiting max. $countdown more seconds...\n"
        }

        $app->{handle} = undef;
        if(defined($app->{killcmd})) {
            print "...running extra killcmd >>", $app->{killcmd}, "<<...\n";
            my $killcmd = $app->{killcmd};
            `$killcmd`;
        }
        print "...killed.\n";
    } else {
        print "App " . $app->{description} . " already killed\n";
    }
    return;
}

sub kill_app($self, $app) {

    if(defined($app->{handle}) && $app->{handle}) {
        $self->{clacks}->set($app->{clacks_name}, 1); # Red
        $self->{clacks}->doNetwork();
        my $pid = $app->{handle};
        print "Killing app " . $app->{description} . " with PID $pid...\n";
        kill 15, $pid; # SIGTERM

        my $countdown = 4;
        my $checker = Unix::PID->new();
        while($checker->is_pid_running($app->{handle})) {
            sleep 0.5;
            $countdown -= 0.5;
            if($countdown <= 0) {
                print "    force-killing\n";
                kill 9, $pid;  #SIGKILL
                last;
            }
            print "    waiting max. $countdown more seconds...\n"
        }
        if(defined($app->{killcmd})) {
            print "...running extra killcmd >>", $app->{killcmd}, "<<...\n";
            my $killcmd = $app->{killcmd};
            `$killcmd`;
        }
        $self->{clacks}->set($app->{clacks_name}, 2); # Blue
        $self->{clacks}->doNetwork();
    }
    return;
}

sub run_script($self, $command) {

    print "Running command '$command':\n";
    my @lines = `$command`;
    foreach my $line (@lines) {
        chomp $line;
        print ":: $line\n";
    }

    return 1;
}

sub resetServer($self) {

    print"  Flushing ClacksCache...\n";
    $self->{clacks}->clearcache();
    my $dbh = DBI->connect($self->{db}->{dburl}, $self->{db}->{dbuser}, $self->{db}->{dbpassword}, {AutoCommit => 0})
        or croak("Can't connect to database!");

    print "  Flushing tables...\n";
    foreach my $command (@{$self->{db}->{resetcommands}->{command}}) {
        print "    $command\n";
        my $sth = $dbh->prepare($command) or croak($dbh->errstr);
        $sth->execute or croak($dbh->errstr);
        $dbh->commit;
    }
    print "  All Flushed!\n";

    return 1;
}

1;
