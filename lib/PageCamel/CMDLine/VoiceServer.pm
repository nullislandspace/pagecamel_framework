package PageCamel::CMDLine::VoiceServer;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.7;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use PageCamel::Helpers::ConfigLoader;
use Time::HiRes qw(sleep usleep time);
use PageCamel::Helpers::Logo;
use Sys::Hostname;
use Errno;
use MIME::Base64;

use Readonly;

Readonly my $SAMPLERATE => 8000.0;
Readonly my $CFACTOR => 2048.0 / 44_100.0; # Original timing in browser (most likely) 44100 Sample/s in 2048 samples "batches"
Readonly my $BUFFERTARGET => int($SAMPLERATE * 0.75); # Try to hold about 3/4 of a second
Readonly my $BIASFACTOR => $BUFFERTARGET / 0.16;

sub new {
    my ($class, $isDebugging, $configfile) = @_;
    
    croak("Config file $configfile not found!") unless(-f $configfile);
    
    my $self = bless {}, $class;

    $self->{isDebugging} = $isDebugging;
    $self->{configfile} = $configfile;

    return $self;
}

sub init {
    my ($self) = @_;
    
    print "Loading config file ", $self->{configfile}, "\n";
    my $config = LoadConfig($self->{configfile},
                        ForceArray => ['ip' ],);
    
    my $hname = hostname;
    
    # Copy hostname-specific stuff to root if it exists
    if(defined($config->{hosts}->{$hname})) {
        foreach my $key (keys %{$config->{hosts}->{$hname}}) {
            $config->{$key} = $config->{hosts}->{$hname}->{$key};
        }
    }
    
    $self->{config} = $config;

    my $APPNAME = $config->{appname};
    PageCamelLogo($APPNAME, $VERSION);
    print "Changing application name to '$APPNAME'\n\n";
    my $isForking = $config->{server}->{forking} || 0;
    my $ps_appname = lc($APPNAME);
    $ps_appname =~ s/[^a-z0-9]+/_/gio;
    $PROGRAM_NAME = $ps_appname;
        
    my @tcpsockets;
    
    foreach my $ip (@{$config->{ip}}) {
        my $tcp = IO::Socket::IP->new(
            LocalHost => $ip,
            LocalPort => $config->{port},
            Listen => 1,
            Blocking => 0,
            ReuseAddr => 1,
            Proto => 'tcp',
        ) or croak($ERRNO);
        binmode($tcp, ':bytes');
        push @tcpsockets, $tcp;
        print "Listening on $ip:" . $config->{port} . "/tcp\n";
    }
    
    
    $self->{tcpsockets} = \@tcpsockets;
    
    print "Ready.\n";
    
    
    return;
}

sub run { ## no critic (Subroutines::ProhibitExcessComplexity)
    my ($self) = @_;
    
    # Let STDOUT/STDERR settle down first
    sleep(0.1);

    my @toremove;
    my %clients;
    my $lastrun = time;
    my $cyclecount = 0;
    my $cyclesamples = 0;
    my $cycletime = $lastrun;
    my $samplefraction = 0.0;
    my $intsamplecount;
    my $sinoffs = 0;
    
    while(1) {
        foreach my $tcpsocket (@{$self->{tcpsockets}}) {
            my $clientsocket = $tcpsocket->accept;
            if(defined($clientsocket)) {
                my ($chost, $cport) = ($clientsocket->peerhost, $clientsocket->peerport);
                my $cid = "$chost:$cport";
                print "Got a new client $chost:$cport!\n";
                $clientsocket->blocking(0);
                my %tmp = (
                    buffer  => '',
                    socket => $clientsocket,
                    lastping => time,
                    monitor => 0,
                    inbuffer => [],
                    inworkbugger => [],
                    outworkbugger => [],
                    buffering => 1,
                    outbuffer => "PageCamel SPEAK Server $VERSION\r\n",
                    clientversion => '',
                    host => $chost,
                    port => $cport,
                    hasmicrophone => 0,
                    hasspeaker => 0,
                    username => '',
                );
                $clients{$cid} = \%tmp;
            }
        }
        
        # Check if there are any clients to disconnect...
        
        my $pingtime = time - $self->{config}->{pingtimeout};
        foreach my $cid (keys %clients) {
            if(!$clients{$cid}->{socket}->connected) {
                push @toremove, $cid;
                next;
            }
            if($clients{$cid}->{lastping} < $pingtime) {
                syswrite($clients{$cid}->{socket}, "TIMEOUT\r\n");
                push @toremove, $cid;
            }
        }
        
        # ...and disconnect them
        while((my $cid = shift @toremove)) {
            print "Removing client $cid\n";
            delete $clients{$cid};
        }
        
        foreach my $cid (keys %clients) {
            while(1) {
                my $buf;
                sysread($clients{$cid}->{socket}, $buf, 1);
                last if(!defined($buf) || !length($buf));
                if($buf eq "\r") {
                    next;
                } elsif($buf eq "\n") {
                    if($clients{$cid}->{buffer} =~ /^LISTEN\ (.*)/) {
                        $clients{$cid}->{listening}->{$1} = 1;
                    } elsif($clients{$cid}->{buffer} =~ /^UNLISTEN\ (.*)/) {
                        delete $clients{$cid}->{listening}->{$1};
                    } elsif($clients{$cid}->{buffer} =~ /^MONITOR\=(.*)/) {
                        if($1 eq 'on') {
                            $clients{$cid}->{monitor} = 1;
                        } else {
                            $clients{$cid}->{monitor} = 0;
                        }
                    } elsif($clients{$cid}->{buffer} =~ /^MIKE\=(.*)/) {
                        if($1 eq 'on') {
                            $clients{$cid}->{hasmicrophone} = 1;
                        } else {
                            $clients{$cid}->{hasmicrophone} = 0;
                        }
                    } elsif($clients{$cid}->{buffer} =~ /^SPEAKER\=(.*)/) {
                        if($1 eq 'on') {
                            $clients{$cid}->{hasspeaker} = 1;
                        } else {
                            $clients{$cid}->{hasspeaker} = 0;
                        }
                    } elsif($clients{$cid}->{buffer} =~ /^DATA\=(.*)/) {
                        my @dec = split//, decode_base64($1);
                        my @decarr;
                        while(@dec) {
                            my $s1 = ord(shift @dec);
                            my $s2 = ord(shift @dec);
                            my $sval = ($s2 << 8) + $s1;
                            if($sval > 32_767) {
                                $sval -= 65_536;
                            }
                            push @decarr, $sval;
                        }

                        push @{$clients{$cid}->{inbuffer}}, @decarr;
                        if(scalar @{$clients{$cid}->{inbuffer}} > $BUFFERTARGET) {
                            $clients{$cid}->{buffering} = 0;
                        }
                    } elsif($clients{$cid}->{buffer} =~ /^QUIT/) {
                        push @toremove, $cid;
                    } elsif($clients{$cid}->{buffer} =~ /^PING/) {
                        $clients{$cid}->{lastping} = time;
                        $clients{$cid}->{outbuffer} .= "PING\r\n";
                    } elsif($clients{$cid}->{buffer} =~ /^PageCamel SPEAK Client\ (.*)\ (.*)/) {
                        ($clients{$cid}->{clientversion}, $clients{$cid}->{username}) = ($1, $2);
                        print "Client at ", $clients{$cid}->{host}, ':', $clients{$cid}->{port}, " Version ", $clients{$cid}->{clientversion}, " with user ", $clients{$cid}->{username}, "\n";
                    } else {
                        print STDERR "ERROR Unknown_command ", $clients{$cid}->{buffer}, "\r\n";
                    }
                    $clients{$cid}->{buffer} = '';
                } else {
                    $clients{$cid}->{buffer} .= $buf;
                }
            }
            
        }

        # Prepare work buffers
        if($intsamplecount) {
            foreach my $cid (keys %clients) {
                if($clients{$cid}->{hasspeaker}) {
                    $clients{$cid}->{inworkbuffer} = [(0) x $intsamplecount];
                }
                if($clients{$cid}->{hasmicrophone} && !$clients{$cid}->{buffering}) {
                    if(scalar @{$clients{$cid}->{inbuffer}} < $intsamplecount) {
                        # Reached end of buffered data. Fill it up for this work round, then go
                        # to "buffering" mode
                        $clients{$cid}->{buffering} = 1;
                        my $missingcount = $intsamplecount - scalar @{$clients{$cid}->{inbuffer}};
                        for(1..$missingcount) {
                            push @{$clients{$cid}->{inbuffer}}, 0;
                        }
                    }
                    @{$clients{$cid}->{outworkbuffer}} = splice @{$clients{$cid}->{inbuffer}}, 0, $intsamplecount;;
                }
            }
        }

        # Merge voices
        if($intsamplecount) {
            foreach my $targetcid (keys %clients) {
                next unless($clients{$targetcid}->{hasspeaker});
                foreach my $sourcecid (keys %clients) {
                    next unless($clients{$sourcecid}->{hasmicrophone});
                    next if($sourcecid eq $targetcid);
                    next if($clients{$sourcecid}->{buffering});
                    for(my $i = 0; $i < $intsamplecount; $i++) {
                        $clients{$targetcid}->{inworkbuffer}->[$i] += $clients{$sourcecid}->{outworkbuffer}->[$i];
                    }
                }
            }
        }
        
        # add sinus
        if(0 && $intsamplecount) {
            foreach my $targetcid (keys %clients) {
                next unless($clients{$targetcid}->{hasspeaker});
                for(my $i = 0; $i < $intsamplecount; $i++) {
                    $clients{$targetcid}->{inworkbuffer}->[$i] += int(sin($sinoffs) * 1000);
                    $sinoffs += 0.03;
                }
            }
        }

        # Add calculated voices to outbuffer
        if($intsamplecount) {
            foreach my $cid (keys %clients) {
                next unless($clients{$cid}->{hasspeaker});
                if(scalar @{$clients{$cid}->{inworkbuffer}}) {
                    my $out = '';
                    for(my $i = 0; $i < $intsamplecount; $i++) {
                        my $tval = $clients{$cid}->{inworkbuffer}->[$i];
                        if($tval > 32_767) {
                            $tval = 32_767;
                        } elsif($tval < -32_769) {
                            $tval = -32_769;
                        }
                        $tval = int($tval);
                        if($tval < 0) {
                            $tval += 65_536;
                        }
                        my $t1 = $tval % 256;
                        my $t2 = int($tval >> 8) & 0xff;
                        $out .= chr($t1) . chr($t2);
                    }
                    $clients{$cid}->{outbuffer} .= "DATA=" . encode_base64($out, '') . "\r\n";
                    $clients{$cid}->{inworkbuffer} = [];
                }
            }
        }

        # Update clients knowledge about our input microphone buffer (if applicable)
        if($intsamplecount) {
            foreach my $cid (keys %clients) {
                next unless($clients{$cid}->{hasmicrophone});
                my $bufsize = scalar @{$clients{$cid}->{inbuffer}};
                # var tdelta = ((sampleSize * 6) - audioOutput.length) / (sampleSize *24);
                my $tdelta = ($BUFFERTARGET - $bufsize) / $BIASFACTOR;
                if($tdelta < -0.08) {
                    $tdelta = -0.08;
                } elsif($tdelta > 0.08) {
                    $tdelta = 0.08;
                }
                # Round
                $tdelta = int($tdelta * 10_000) / 10_000;
                $clients{$cid}->{outbuffer} .= "MIKEBIAS=$tdelta|$bufsize\r\n";
                #print STDERR "$tdelta | $bufsize\n";
            }
        }
        
        
        # Send as much as possible
        foreach my $cid (keys %clients) {
            next if(!length($clients{$cid}->{outbuffer}));
            
            # Output bandwidth-limited stuff, in as big chunks as possible
            my $written;
            eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                $written = syswrite($clients{$cid}->{socket}, $clients{$cid}->{outbuffer});
            };
            if($EVAL_ERROR) {
                print STDERR "Write error: $EVAL_ERROR\n";
                push @toremove, $cid;
                next;
            }
            if(!$clients{$cid}->{socket}->opened || $clients{$cid}->{socket}->error || ($ERRNO ne '' && !$!{EWOULDBLOCK})) { ## no critic (Variables::ProhibitPunctuationVars)
                print STDERR "webPrint write failure: $ERRNO\n";
                push @toremove, $cid;
                next;
            }
            
            if(defined($written) && $written) {
                $clients{$cid}->{outbuffer} = substr($clients{$cid}->{outbuffer}, $written);
            }
        }

        my $cyclenow = time;
        my $cyclediff = $cyclenow - $cycletime;
        if(0 && $cyclesamples > 8000) {
            #print STDERR "AVG: ", $cyclesamples / $cyclediff, "\n";
            $cyclesamples = 0;
            $cycletime = $cyclenow;
        }

        my $now = time;
        my $runtime = $now - $lastrun;
        my $sleeptime = $CFACTOR - $runtime;
        $intsamplecount = int($SAMPLERATE * $CFACTOR);
        $samplefraction += ($SAMPLERATE * $CFACTOR) - ($intsamplecount * 1.0);
        if($samplefraction >= 1.0) {
            $samplefraction -= 1.0;
            $intsamplecount++;
        }
        $cyclesamples += $intsamplecount;

        #print STDERR "ST: $now  $lastrun $runtime $sleeptime\n";
        if($sleeptime > 0) {
            sleep($sleeptime);
        }
        $lastrun += $CFACTOR;
    }

    return;
}

1;
