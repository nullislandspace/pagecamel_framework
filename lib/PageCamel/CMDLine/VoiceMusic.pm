package PageCamel::CMDLine::VoiceMusic;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use PageCamel::Helpers::ConfigLoader;
use Time::HiRes qw(sleep usleep time);
use PageCamel::Helpers::Logo;
use Sys::Hostname;
use Errno;
use MIME::Base64;
use PageCamel::Helpers::VoiceClient;

use Readonly;

Readonly my $SAMPLERATE => 8000.0;
Readonly my $CFACTOR => 2048.0 / 44_100.0; # Original timing in browser (most likely) 44100 Sample/s in 2048 samples "batches"

sub new($class, $isDebugging, $configfile) {
    
    my $self = bless {}, $class;

    $self->{isDebugging} = $isDebugging;
    $self->{configfile} = $configfile;

    return $self;
}

sub init($self) {
    
    print "Loading config file ", $self->{configfile}, "\n";
    my $config = LoadConfig($self->{configfile},
                        ForceArray => ['file' ],);
    
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
        
    print Dumper($self);
    my $vserv = PageCamel::Helpers::VoiceClient->new($self->{config}->{ip}, $self->{config}->{port}, $self->{config}->{username});
    $vserv->setmike(1);
    $vserv->setspeaker(0);
    $vserv->ping();
    $vserv->doNetwork();

    $self->{vserv} = $vserv;
    
    print "Ready.\n";
    
    
    return;
}

sub run($self) {
    
    # Let STDOUT/STDERR settle down first
    sleep(0.1);

    my $lastrun = time;
    my $cyclecount = 0;
    my $cyclesamples = 0;
    my $cycletime = $lastrun;
    my $samplefraction = 0.0;
    my $intsamplecount;
    my $nextping = 0;
    my @filenames;
    my $ifh;
    my @buffer;
    my $nextbiasdebug = time;
    
    while(1) {

        if(!@filenames) {
            push @filenames, @{$self->{config}->{songs}->{file}};
        }
        if(!defined($ifh)) {
            my $fname = shift @filenames;
            print "Now Playing $fname\n";
            open($ifh, '<', $fname) or croak($ERRNO);
            binmode $ifh;
        }
        if(scalar @buffer < ($SAMPLERATE * 5)) {
            my $temp;
            my $bytecount = read $ifh, $temp, $SAMPLERATE;
            if($bytecount < 1000 || eof($ifh)) {
                close $ifh;
                $ifh = undef;
            }
            my @parts = split//, $temp;
            while(@parts) {
                my $p1 = shift @parts;
                my $p2 = shift @parts;
                push @buffer, $p1 . $p2;
            }
        }

        if($intsamplecount) {
            my @outpart = splice @buffer, 0, $intsamplecount;
            #print Dumper(\@buffer);
            $self->{vserv}->sendvoice(encode_base64(join('', @outpart), ''));
        }
        $self->{vserv}->doNetwork();
        while(my $msg = $self->{vserv}->getNext()) {
            if($msg->{type} eq 'getvoice') {
                print "GOT VOICE WHEN I SHOULDN'T!\n";
            } elsif($msg->{type} eq 'mikebias') {
                if($nextbiasdebug < time) {
                    print 'NEW BIAS: ', $msg->{bias}, ' for server buffer size ', $msg->{buffersize}, "\n";
                    $nextbiasdebug += 10;
                }
            }
        }

        my $now = time;
        if($nextping < $now) {
            $self->{vserv}->ping();
            $nextping = $now + $self->{config}->{pingtimeout};
        }

        # Time calculation
        my $cyclenow = time;
        my $cyclediff = $cyclenow - $cycletime;
        if(0 && $cyclesamples > 8000) {
            #print STDERR "AVG: ", $cyclesamples / $cyclediff, "\n";
            $cyclesamples = 0;
            $cycletime = $cyclenow;
        }

        $now = time;
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
