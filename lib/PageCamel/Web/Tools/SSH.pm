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
                                            '/static/xterm/addon-attach.js',
                                          );
    push @{$webdata->{HeadExtraCSS}}, (
                                            '/static/xterm/xterm.css',
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
    
    $self->{bash} = IO::Pty::Easy->new;
    $self->{bash}->set_winsize(25, 120);
    $self->{bash}->spawn('/bin/bash');
    $self->{bash}->write("stty echo\r\n");

    return;
}

sub wscleanup($self) {
    delete $self->{bash};

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

    return 1;
}
    
sub wscyclic($self, $ua) {
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    #my $bytes;
    #read($self->{ifh}, $bytes, 100);
    my $bytes = $self->{bash}->read(0);
    if(defined($bytes) && length($bytes)) {
        #print STDERR "\n#### ", Dumper($bytes), "\n";
        #$self->dumpString($fixed);
        if(!$self->writeData($bytes)) {
            return 0;
        }
    }


    return 1;
}

sub writeData($self, $bytes) {
    my @parts = split//, $bytes;
    my $fixed = '';
    foreach my $part (@parts) {
        if($part eq "\n") {
            $part = "\r\n";
        }
        $fixed .= $part;
    }

    my %msg = (
        type => 'CONSOLEDATA',
        data => $fixed,
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
