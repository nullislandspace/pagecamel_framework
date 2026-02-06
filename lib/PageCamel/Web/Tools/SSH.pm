package PageCamel::Web::Tools::SSH;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 5.0;
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseWebSocket);
use PageCamel::Helpers::FileSlurp qw(slurpBinFile);
use JSON::XS;
#use IPC::Open2;
use IO::Pty::Easy;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{extrasettings} = [];
    $self->{template} = 'tools/ssh';

    return $self;
}

sub wsmaskget($self, $ua, $settings, $webdata) {
    foreach my $key (qw[HeadExtraScripts HeadExtraCSS]) {
        if(!defined($webdata->{$key})) {
            my @temp;
            $webdata->{$key} = \@temp;
        }
    }

    push @{$webdata->{HeadExtraScripts}}, (
                                            '/static/xterm/xterm.js',
                                            '/static/xterm/addon-fit.js',
                                          );
    push @{$webdata->{HeadExtraCSS}}, (
                                            '/static/xterm/xterm.css',
                                            '/static/xterm/ssh-terminal.css',
                                      );

    return 200;
}

sub wscrossregister($self) {

    return;
}

sub wshandlerstart($self, $ua, $settings) {
#   my ($ifh, $ofh);
#   my $pid = open2($ifh, $ofh, '/bin/bash');
#   binmode($ofh);
#   binmode($ifh);
#   $ofh->blocking(0);
#   $ifh->blocking(0);
#
#   $self->{bashpid} = $pid;
#   $self->{ifh} = $ifh;
#   $self->{ofh} = $ofh;
    
    # Set environment variables for proper terminal support
    $ENV{TERM} = 'xterm-256color';
    $ENV{LANG} = 'en_US.UTF-8';
    $ENV{LC_ALL} = 'en_US.UTF-8';

    # Create PTY with default size (will be resized by client)
    $self->{bash} = IO::Pty::Easy->new;
    $self->{bash}->set_winsize(24, 80);  # Default, client will send actual size
    $self->{bash}->spawn('/bin/bash');

    # Add PTY to IO::Select for low-latency reads (10ms instead of 100ms)
    $self->wsaddhandle($self->{bash});

    # Configure PTY: enable echo (LF->CRLF handled by xterm.js convertEol)
    $self->{bash}->write("stty echo\r\n");

    return;
}

sub wscleanup($self) {
    if(defined($self->{bash})) {
        $self->wsremovehandle($self->{bash});
        delete $self->{bash};
    }

    return;
}

sub wshandlemessage($self, $message) {
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    if($message->{type} eq 'CONSOLEDATA') {
        #print STDERR Dumper($message);
        #$self->{ofh}->write($message->{data});
        my $outval = $message->{data};
        #$outval =~ s/\r/\n/g;
        #$self->dumpString($outval);

        #$self->{ofh}->write($outval);
        $self->{bash}->write($outval,0);

        # echo input back to console
        #$self->writeData($outval);
    }
    elsif($message->{type} eq 'RESIZE') {
        my $rows = int($message->{data}->{rows} // 24);
        my $cols = int($message->{data}->{cols} // 80);

        # Validate bounds
        $rows = 24 if $rows < 1 || $rows > 500;
        $cols = 80 if $cols < 1 || $cols > 500;

        # Resize PTY and signal shell
        $self->{bash}->set_winsize($rows, $cols);
        if($self->{bash}->is_active) {
            kill 'WINCH', $self->{bash}->pid;
        }
    }

    return 1;
}
    
sub wscyclic($self, $ua) {
    # Drain entire PTY buffer to avoid 100ms latency per chunk
    my $allbytes = '';
    while(1) {
        my $bytes = $self->{bash}->read(0);
        last if !defined($bytes) || !length($bytes);
        $allbytes .= $bytes;
    }

    if(length($allbytes)) {
        if(!$self->writeData($allbytes)) {
            return 0;
        }
    }

    return 1;
}

sub writeData($self, $bytes) {
    # Decode PTY output as UTF-8 for proper JSON encoding
    my $decoded = decode_utf8($bytes);

    my %msg = (
        type => 'CONSOLEDATA',
        data => $decoded,
    );

    if(!$self->wsprint(\%msg)) {
        return 0;
    }

    return 1;
}

sub dumpString($self, $val) {
    my @parts = split//, $val;
    foreach my $part (@parts) {
        print STDERR ord($part), " ";
    };
    print STDERR "\n";
    return;
}


1;
__END__
