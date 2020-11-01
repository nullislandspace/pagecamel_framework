package PageCamel::SVC::Main;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
use Data::Dumper;
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
    $self->{is_configured} = 0;


    $self->checkDatabase();
    if(!defined($self->{dbh})) {
        croak("Can't connect to database");
    }
    $self->{sysh} = PageCamel::SVC::Settings->new($self->{dbh}, $self->{clacks});

    $self->{nextkeepalive} = 0;


    return $self;
}

sub checkDatabase {
    my ($self) = @_;

    if(defined($self->{dbh}) && !$self->{dbh}->ping) {
        $self->{dbh}->disconnect;
        delete $self->{dbh};
    }
    if(!defined($self->{dbh})) {
        my $dbh = DBI->connect($self->{db}->{dburl}, $self->{db}->{dbuser}, $self->{db}->{dbpassword}, {AutoCommit => 0, RaiseError => 0});
        if(defined($dbh)) {
            $self->{dbh} = $dbh;
        }
    }

    return;
}

sub setRealPerlBinary {
    my ($self, $binary) = @_;

    print "** SETTING REAL PERL BINARY TO $binary **\n";
    $self->{realperlbinary} = $binary;
    return;
}

sub requestStop {
    my ($self) = @_;

    my $tmp = 1;
    $self->{clacks}->store("StopSVC", $tmp);
    return;
}

sub shouldStop {
    my ($self) = @_;

    my $stop = $self->{clacks}->retrieve("StopSVC");
    if(!defined($stop) || $stop != 1){
        return 0;
    } else {
        return 1;
    }

}

sub setServerStatus {
    my ($self, $status) = @_;

    $self->{clacks}->store("SVCRunningStatus", $status);
    return;
}

sub getServerStatus {
    my ($self) = @_;

    my $status = $self->{clacks}->retrieve("SVCRunningStatus");
    if(!defined($status)){
        return "stopped";
    } else {
        return $status;
    }

}

sub startconfig {
    my ($self) = @_;

    $self->{apps} = ();
    $self->{startup_scripts} = ();
    $self->{shutdown_scripts} = ();
    return;
}

sub configure_module {
    my ($self, $module) = @_;

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
                        settingvalue => "0",
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

sub configure_startup {
    my ($self, $command) = @_;

    $command =~ s/\//\\/g;
    push @{$self->{startup_scripts}}, $command;
    return;
}

sub configure_shutdown {
    my ($self, $command) = @_;

    $command =~ s/\//\\/g;
    push @{$self->{shutdown_scripts}}, $command;
    return;
}


sub endconfig {
    my ($self) = @_;
    $self->{shutdown_complete} = 1;
    $self->{is_configured} = 1;
    return;

}

sub startup {
    my ($self) = @_;

    # "Don't fear the Reaper"
    $SIG{CHLD} = 'IGNORE';

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
        $self->{sysh}->get('pagecamel_services', $app->{status_name}, 0);
        my ($ok, $refshouldrun) = $self->{sysh}->get('pagecamel_services', $app->{enable_name});
        if($ok && $refshouldrun->{settingvalue}) {
            $self->{clacks}->set($app->{clacks_name}, 2);
        } else {
            $self->{clacks}->set($app->{clacks_name}, 0);
        }
        $self->{clacks}->doNetwork();
    }

    foreach my $app (@{$self->{apps}}) {
        my ($ok, $refshouldrun) = $self->{sysh}->get('pagecamel_services', $app->{enable_name});
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
    return;
}

sub work {
    my ($self) = @_;

    my $workCount = 0;

    $self->{clacks}->ping();

    foreach my $app (@{$self->{apps}}) {
        my $didwork = $self->check_app($app);
        $self->{clacks}->doNetwork();

        $workCount++;

        $workCount += $self->handleClacksCommands();

        if($didwork) {
            # Update ALL app states
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

            ## Only handle ONE app startup/shutdown per cycle
            #last;
        }
    }

    return $workCount;
}

sub handleClacksCommands {
    my ($self) = @_;

    my $workCount = 0;
    my $done = 0;

    my $now = time;
    if($now > $self->{nextkeepalive}) {
        $self->{clacks}->notify('pagecamel_services::lifetick');
        $self->{clacks}->doNetwork();
        $self->{nextkeepalive} = $now + 10;
    }

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

sub shutdownsvc {
    my ($self) = @_;

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

#sub DESTROY {
#    my ($self) = @_;
#
#    # This might error out during DESTROY, so catch any errors
#    eval {
#        if(!$self->{shutdown_complete}) {
#            $self->shutdownsvc();
#        }
#    };
#    return;
#}

sub disable_service {
    my ($self, $svcname) = @_;

    $self->{sysh}->set('pagecamel_services', $svcname . '_enable', 0);
    return;
}

sub enable_service {
    my ($self, $svcname) = @_;

    $self->{sysh}->set('pagecamel_services', $svcname . '_enable', 1);
    return;
}

sub check_service {
    my ($self, $svcname) = @_;

    my ($ok, $refstatus) = $self->{sysh}->get('pagecamel_services', $svcname . '_status');

    if(!$ok) {
        return -1;
    }
    return $refstatus->{settingvalue};
}

sub check_app {
    my ($self, $app) = @_;


    my ($ok, $refshouldrun) = $self->{sysh}->get('pagecamel_services', $app->{enable_name});
    my $shouldrun;
    if(!$ok) {
        # Default on error: Run service (same as on old system)
        $shouldrun = 1;
    } else {
        $shouldrun = $refshouldrun->{settingvalue};
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
    if(!$checker->is_pid_running($app->{handle})) {
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
            # Client requested a temporary suspension of lifetick handling or has not sent a livetick yet
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
            $self->stop_app($app);
            $self->{clacks}->set($app->{clacks_name}, 3); # Purple ("lifetick error")
            $self->{clacks}->doNetwork();
            $self->start_app($app);
            return 1;
        } else {
            return 0;
        }

    }

    return 0;
}

sub start_app {
    my ($self, $app) = @_;

    my $pid = fork();

    if($pid) {
        #parent
        print "Forked " . $app->{app} . " has PID $pid\n";
        $app->{handle} = $pid;
        $app->{apptick} = -1;
        my $stime = time;
        for(1..3) {
            sleep(1); # Sleep a few seconds to allow the application to start up without
                      # too much conflicts with PageCamelSVC and other services to be started
            $self->{clacks}->doNetwork();
        }
        $self->{sysh}->set('pagecamel_services', $app->{status_name}, 1);
        $self->{clacks}->set($app->{clacks_name}, 1);
        $self->{clacks}->doNetwork();
    } else {
        # Child
        print "Running command ", $app->{app}, " ", $app->{conf}, "\n";
        open STDOUT, ">",  "/dev/null" or croak("$PROGRAM_NAME: open: $ERRNO");
        open STDERR, ">&", \*STDOUT    or exit 1;
        eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
            exec($app->{app} . " " . $app->{conf});
        };
        exec('false');
        print "Child done\n";
        exit(0);
    }
    return;
}

sub stop_app {
    my ($self, $app) = @_;

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
        $self->{clacks}->remove("LIFETICK::" . $pid);
    } else {
        print "App " . $app->{description} . " already killed\n";
    }
    return;
}

sub kill_app {
    my ($self, $app) = @_;

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

sub run_script {
    my ($self, $command) = @_;

    print "Running command '$command':\n";
    my @lines = `$command`;
    foreach my $line (@lines) {
    chomp $line;
    print ":: $line\n";
    }

    return 1;
}

sub resetServer {
    my ($self) = @_;

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
