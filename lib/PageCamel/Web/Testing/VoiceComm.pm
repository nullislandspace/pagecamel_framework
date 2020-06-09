package PageCamel::Web::Testing::VoiceComm;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseWebSocket);
use PageCamel::Helpers::DateStrings;
use MIME::Base64;
use PageCamel::Helpers::FileSlurp qw(writeBinFile slurpBinFile);
use PageCamel::Helpers::VoiceClient;

# play -t raw -r 11025 -e signed-integer -b 16 -c 1 rawaudio.dat

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class
    
    $self->{extrasettings} = [qw/audio_buffer_size target_sample_rate/];
    if(!$self->{lightmode}) {
        $self->{template} = 'testing/voicecomm';
    } else {
        $self->{template} = 'testing/voicecomm_light';
    }

    return $self;
}

sub wsregister {
    my $self = shift;
    # Nothing to register
    
    return;
}

sub wsreload {
    my ($self) = @_;

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    $sysh->createNumber(modulename => $self->{modname},
                    settingname => 'audio_buffer_size',
                    settingvalue => 2048,
                    description => 'Audio Buffer Size (bytes)',
                    value_min => 100.0,
                    value_max => 5 * 1024 * 1024, # max 5 MB per chunk
                    processinghints => [
                        'decimal=0',
                    ],
                    )
        or croak("Failed to create setting audio_buffer_size!");

    $sysh->createNumber(modulename => $self->{modname},
                    settingname => 'target_sample_rate',
                    settingvalue => 8000,
                    description => 'Output Sample rate (bytes)',
                    value_min => 100.0,
                    value_max => 48_000,
                    processinghints => [
                        'decimal=0',
                    ],
                    )
        or croak("Failed to create setting target_sample_rate!");
        
    return;
}

sub wshandlerstart {
    my ($self, $ua, $settings) = @_;
    
    my %webdata = (
        $self->{server}->get_defaultwebdata(),
    );
    my $username = $webdata{userData}->{user};
    my $vserv = PageCamel::Helpers::VoiceClient->new('127.0.0.1', '19999', $username);
    $vserv->setmike(1);
    $vserv->setspeaker(1);
    $vserv->ping();
    $vserv->doNetwork();

    my %audio = (
        settings => $settings,
        vserv => $vserv,
        nextping => time + 60,
    );
    
    $self->{audio} = \%audio;
    
    return;
}

sub wscleanup {
    my ($self) = @_;
    
    delete $self->{audio};
    
    if(defined($self->{ofh})) {
        close $self->{ofh};
        delete $self->{ofh};
    }
    
    return;
}

sub wscyclic {
    my ($self) = @_;
    
    $self->{audio}->{vserv}->doNetwork();
    my %outmsg;
    while((my $msg = $self->{audio}->{vserv}->getNext())) {
        if($msg->{type} eq 'getvoice') {
            %outmsg = (
                type => 'DATA',
                data => $msg->{data},
            );
            if(!$self->wsprint(\%outmsg)) {
                print STDERR "Write to socket failed, closing connection!\n";
                return 0;
            }            
        } elsif($msg->{type} eq 'mikebias') {
            %outmsg = (
                type => 'MIKEBIAS',
                bias => $msg->{bias},
                buffersize => $msg->{buffersize},
            );
            if(!$self->wsprint(\%outmsg)) {
                print STDERR "Write to socket failed, closing connection!\n";
                return 0;
            }  
        }
    }
          
    return 1;
    
}

sub wshandlemessage {
    my ($self, $message) = @_;

    if($message->{type} eq 'DATA') {

        $self->{audio}->{vserv}->sendvoice($message->{sample});
        if($self->{audio}->{nextping} < time) {
            $self->{audio}->{nextping} += 60;
            $self->{audio}->{vserv}->ping();
        }
        $self->{audio}->{vserv}->doNetwork();        
    }
    
    return 1;
}


1;
__END__
