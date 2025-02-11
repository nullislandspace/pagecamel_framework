package PageCamel::Web::Testing::Microphone;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.6;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseWebSocket);
use PageCamel::Helpers::DateStrings;
use MIME::Base64;
use PageCamel::Helpers::FileSlurp qw(writeBinFile slurpBinFile);

# play -t raw -r 11025 -e signed-integer -b 16 -c 1 rawaudio.dat

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class
    
    $self->{extrasettings} = [qw/audio_buffer_size target_sample_rate/];
    $self->{template} = 'testing/microphone';

    return $self;
}

sub wsregister($self) {
    # Nothing to register
    
    return;
}

sub wsreload($self) {

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
                    settingvalue => 11_000,
                    description => 'Output Sample rate (bytes)',
                    value_min => 100.0,
                    value_max => 48_000,
                    processinghints => [
                        'decimal=0',
                    ],
                    )
        or croak("Failed to create setting audio_buffer_size!");
        
    return;
}

sub wshandlerstart($self, $ua, $settings) {

    my %audio = (
        playbackbuffer => [],
        playbackchunksize => 256,
        playbackfh => undef,
        playbackqueue => [],
        echoon => 0,
        vocoder1 => 0,
        vocoder2 => 0,
        vocoderon => 0,
        vocoderecho1 => [],
        vocoderecho2 => [],
        settings => $settings,
    );
    
    $self->{audio} = \%audio;
    
    return;
}

sub wscleanup($self) {
    
    delete $self->{audio};
    
    if(defined($self->{ofh})) {
        close $self->{ofh};
        delete $self->{ofh};
    }
    
    return;
}

my $tmpaccu = 0;
my $tmpcnt = 0;
sub wshandlemessage($self, $message) {

    if($message->{type} eq 'START') {
        if(defined($self->{ofh})) {
            print STDERR "Got START but file is already OPEN!\n";
            next;
        }
        if(!-d $self->{tmpdir}) {
            print STDERR $self->{tmpdir}, " does not exist!\n";
            next;
        }
        print STDERR "Recording to ", $self->{tmpdir} . '/rawaudio.dat', "\n";
        print STDERR "Got START\n";
        open(my $ofh, '>', $self->{tmpdir} . '/rawaudio.dat') or croak("$ERRNO"); ## no critic (InputOutput::RequireBriefOpen)
        binmode $ofh;
        $self->{ofh} = $ofh;
    } elsif($message->{type} eq 'STOP') {
        if(!defined($self->{ofh})) {
            print STDERR "Got STOP but file is already CLOSED!\n";
            next;
        }
        print STDERR "Got STOP\n";
        close $self->{ofh};
        delete $self->{ofh};
    } elsif($message->{type} eq 'SAMPLE') {

        #print STDERR "Writing sample data\n";
        my $realchunk;
        if($self->{audio}->{settings}->{binary_mode}) {
            $realchunk = $message->{sample};
        } else {
            $realchunk = decode_base64($message->{sample});
        }
        
        #print STDERR "<<< ", length($realchunk), "\n";
        $tmpcnt++;
        $tmpaccu += length($realchunk);
        if($tmpcnt == 100) {
            $tmpaccu = int(($tmpaccu / $tmpcnt) * 100) / 100;
            #print STDERR "<<< ", $tmpaccu, "\n";
            $tmpaccu = 0;
            $tmpcnt = 0;
        }
        
        if($self->{audio}->{vocoderon}) { # Vocoder
            for(my $i = 0; $i < length($realchunk); $i += 2) {
                my $s1 = ord(substr $realchunk, $i, 1);
                my $s2 = ord(substr $realchunk, $i+1, 1);
                my $sval = ($s2 << 8) + $s1;
                if($sval > 32_767) {
                    $sval -= 65_536;
                }
                
                my $tval = $sval * sin($self->{audio}->{vocoder1});
                $tval /= 2;
                if(sin($self->{audio}->{vocoder2})) {
                    $tval *= -1;
                }

                push @{$self->{audio}->{vocoderecho1}}, $tval;
                push @{$self->{audio}->{vocoderecho2}}, $tval;

                $tval += shift @{$self->{audio}->{vocoderecho1}};
                $tval += shift @{$self->{audio}->{vocoderecho2}};
                
                #my $tval = $sval * (abs((sin($vocoder1) * 0.666) + (sin($vocoder2) * 0.333))/2 + 0.5);
                $self->{audio}->{vocoder1} += 0.11;
                $self->{audio}->{vocoder2} += 0.13;
                
                if($tval < 0) {
                    $tval += 65_536;
                }
                my $t1 = $tval % 256;
                my $t2 = int($tval >> 8);
                
                if($t1 > 255 || $t2 > 255) {
                    print STDERR "****** $t1 $t2 \n";
                }
                
                substr($realchunk, $i, 2, chr($t1) . chr($t2));
            }
        }
        
        if(defined($self->{ofh})) {
            syswrite($self->{ofh}, $realchunk);
        }
        
        if(!$self->{audio}->{echoon}) {
            $realchunk = chr(0) x length($realchunk);
        }
        
        if(defined($self->{audio}->{playbackfh})) {
            my $tempbuffer;
            read($self->{audio}->{playbackfh}, $tempbuffer, length($realchunk));
            #print STDERR "### LEN: ", length($tempbuffer), "\n";
            if(length($tempbuffer)) {
                push @{$self->{audio}->{playbackbuffer}}, split//, $tempbuffer;
            }
            if(eof $self->{audio}->{playbackfh}) {
                print STDERR "EOF. Closing filehandle.\n";
                close $self->{audio}->{playbackfh};
                delete $self->{audio}->{playbackfh};
            }
        }
        
        if(!defined($self->{audio}->{playbackfh}) && @{$self->{audio}->{playbackqueue}}) {
            my $ifname = shift @{$self->{audio}->{playbackqueue}};
            print STDERR "Opening file $ifname for playback.\n";
            open(my $ifh, "<", $ifname) or croak("$ERRNO"); ## no critic (InputOutput::RequireBriefOpen)
            #local $INPUT_RECORD_SEPARATOR = undef;
            binmode($ifh);
            $self->{audio}->{playbackfh} = $ifh;
        }
        
        if(@{$self->{audio}->{playbackbuffer}}) {
            if(@{$self->{audio}->{playbackbuffer}}) {
                for(my $i = 0; $i < length($realchunk); $i += 2) {
                    last unless(@{$self->{audio}->{playbackbuffer}});
                    my $s1 = ord(substr $realchunk, $i, 1);
                    my $s2 = ord(substr $realchunk, $i+1, 1);
                    my $sval = ($s2 << 8) + $s1;
                    if($sval > 32_767) {
                        $sval -= 65_536;
                    }
                    $sval /= 2;
                    
                    #my ($d1, $d2);
                    #($d1, $d2, $self->{audio}->{playbackbuffer}) = unpack('a1 a1 a*', $self->{audio}->{playbackbuffer});
                    my $d1 = ord(shift @{$self->{audio}->{playbackbuffer}});
                    my $d2 = ord(shift @{$self->{audio}->{playbackbuffer}});
                    my $dval = ($d2 << 8) + $d1;
                    if($dval > 32_767) {
                        $dval -= 65_536;
                    }
                    $dval /= 2;
                    
                    my $tval = $sval + $dval;
                    if($tval < 0) {
                        $tval += 65_536;
                    }
                    my $t1 = $tval % 256;
                    my $t2 = int($tval >> 8) & 0xff;
                    
                    if($t1 > 255 || $t2 > 255) {
                        print STDERR "****** $t1 $t2 \n";
                    }
                    
                    substr($realchunk, $i, 2, chr($t1) . chr($t2));
                }
            }
        }

        if(!$self->{audio}->{settings}->{binary_mode}) {
            $realchunk = encode_base64($realchunk);
        }
        #print STDERR "LEN: ", length($realchunk), "\n";
        my %echomsg = (
            type => 'OUTPUT',
            data => $realchunk,
        );
        #print STDERR ">>> ", length($realchunk), "\n";
        if(!$self->wsprint(\%echomsg)) {
            print STDERR "Write to socket failed, closing connection!\n";
            return 0;
        }
        
    } elsif($message->{type} eq 'PLAYBACK') {
        push @{$self->{audio}->{playbackqueue}}, $self->{tmpdir} . '/' . $message->{value};
        #my $tempdata = slurpBinFile($self->{tmpdir} . '/' . $message->{value});
        #push @{$self->{audio}->{playbackbuffer}}, split//, $tempdata;
        print STDERR "PLAYBACK queued for ", $message->{value}, "\n";
    } elsif($message->{type} eq 'ECHO') {
        $self->{audio}->{echoon} = $message->{value};
        print STDERR 'Set ECHO to ', $message->{value}, "\n";
    } elsif($message->{type} eq 'VOCODER') {
        $self->{audio}->{vocoderon} = $message->{value};
        print STDERR 'Set VOCODER to ', $message->{value}, "\n";
        if($self->{audio}->{vocoderon}) {
            @{$self->{audio}->{vocoderecho1}} = (0) x 200;
            @{$self->{audio}->{vocoderecho2}} = (0) x 300;
        }
    }
    
    return 1;
}


1;
__END__
