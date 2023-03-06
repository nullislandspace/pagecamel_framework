package PageCamel::Worker::Foscam::Stream;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.2;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);

use WWW::Mechanize::GZip;
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::FileSlurp qw[writeBinFile slurpBinFile];
use Image::Imlib2;
use Time::HiRes qw(sleep);
use MIME::Base64;
use XML::Simple;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    if(!defined($self->{tmpname})) {
        $self->{tmpname} = '/run/pagecamel_webcamfile.jpg';
    }

    # run startup commands (init camera on first cycle)
    $self->{needInit} = 1;

    $self->{lastimagetime} = '';

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);
    $self->{clacks}->listen($self->{camname} . '::Command');
    $self->{clacks}->doNetwork();

    return $self;
}

sub register($self) {

    $self->register_worker('work');
    return;
}

sub reload($self) {

    if(defined($self->{archivepath}) && !-d $self->{archivepath}) {
        croak($self->{modname} . 'error: Directory does not exist: ' . $self->{archivepath});
    }

}

sub startupCommands($self) {

    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    $reph->debuglog("Initializing camera");

    foreach my $item (@{$self->{startupcommands}->{item}}) {
        if($item->{cmd} eq 'wait') {
            my $waittime = $item->{argument}->{seconds}->{content};
            $reph->debuglog("Waiting for $waittime seconds...");
            sleep($waittime);
        } else {
            my %args;
            if(defined($item->{argument})) {
                foreach my $key (keys %{$item->{argument}}) {
                    my $val = $item->{argument}->{$key}->{content};
                    $args{$key} = $val;
                }
            }
            my ($ok, undef) = $self->runCommand($item->{cmd}, \%args);
            if($ok) {
                $reph->debuglog("Command " . $item->{cmd} . " OK");
            } else {
                $reph->debuglog("Command " . $item->{cmd} . " FAILED");
            }
        }
    }


    $reph->debuglog("Initializing camera ... done");
    return;
}

sub work($self) {

    my $workCount = 0;

    if($self->{needInit}) {
        $self->startupCommands();
        $self->{needInit} = 0;
    }

    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    $self->{clacks}->doNetwork();
    while((my $message = $self->{clacks}->getNext())) {
        if($message->{type} eq 'disconnect') {
            $self->{clacks}->listen($self->{camname} . '::Command');
            $self->{clacks}->ping();
            $self->{clacks}->doNetwork();
            next;
        }

        if($message->{type} eq 'set' && $message->{name} eq $self->{camname} . '::Command') {
            $reph->debuglog("Running command " . $message->{data} . ' ...');
            my ($ok, $value) = $self->runCommand($message->{data});
            if($ok) {
                $reph->debuglog("  OK");
            } else {
                $reph->debuglog("  Failed");
            }

            if($message->{data} eq 'getImageSetting' && $ok) {
                # Need to return the current image settings to frontend
                my $camconf = XMLin($value);
                my @parts;
                foreach my $key (keys %{$camconf}) {
                    push @parts, $key . '=' . $camconf->{$key};
                }
                my $clackscamconf = join('&', @parts);
                print STDERR '######: ', $clackscamconf, "\n";
                $self->{clacks}->set($self->{camname} . '::Config', $clackscamconf);
            }
            $self->{lastimagetime} = ''; # Trigger new image automatically
        }

    }

    my $now = getFileDate();
    my $filedate = substr $now, 0, length($now) - 1; # "round down" = only exact to 10 seconds
    if($filedate eq $self->{lastimagetime}) {
        return $workCount;
    }
    $self->{lastimagetime} = $filedate;
    $self->{clacks}->ping();

    $reph->debuglog("Getting image for " . $self->{modname});

    my $mech = WWW::Mechanize::GZip->new(ssl_opts => {verify_hostname => 0});

    my ($gotimage, $imagedata) = $self->runCommand('snapPicture2');
    if($gotimage) {
        my $fname;
        my $tmpname = $self->{tmpname};
        if(defined($self->{archivepath})) {
           $fname = $self->{archivepath} . '/' . getFileDate() . '.jpg';
        } else {
           $fname = $tmpname;
        } 
        writeBinFile($tmpname, $imagedata);
        if(defined($self->{saverawimages})) {
            my $rawimgname = $self->{saverawimages} . '/' . $now . '.jpg';
            writeBinFile($rawimgname, $imagedata);
        }
        foreach my $crop (@{$self->{crop}}) {
            my $img = Image::Imlib2->load($tmpname);
            $img->set_quality(100);

            # Crop image if required
            $img = $img->crop($crop->{x}, $crop->{y}, $crop->{w}, $crop->{h});
            $fname = $crop->{finaltmpname};

            if(defined($crop->{scale})) {
                $img = $img->create_scaled_image($crop->{scale}->{x}, $crop->{scale}->{y});
            }

            if(defined($crop->{timestamp}) && $crop->{timestamp}) {
                drawTimestamp($img);
            }

            $img->save($fname);

            my $imgkeyname = 'Webcam::' . $self->{camname} . '::' . $crop->{clacksname} . '::imagedata';
            my $encoded = encode_base64(slurpBinFile($fname), '');
            $reph->debuglog(length($encoded) . " base64 bytes @ $imgkeyname");
            $self->{clacks}->set($imgkeyname, $encoded); # real time notification via SET
            $self->{clacks}->doNetwork();
            $self->{clacks}->store($imgkeyname, $encoded); # store in clacks memory
            $self->{clacks}->doNetwork();
        }
        $workCount++;
    } else {
        $reph->debuglog("Access failed to " . $self->{modname} . "!");
    }

    return $workCount;
}

sub runCommand($self, $command, $params = undef) {

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $mech = WWW::Mechanize::GZip->new(ssl_opts => {verify_hostname => 0});
    
    my $url = $self->{url};
    # Add command
    $url .= '?cmd=' . $command;

    if(defined($params)) {
        foreach my $key (keys %{$params}) {
            my $val = $params->{$key};
            $url .= '&' . $key . '=' . $val;
        }
    }

    # Add auth
    $url .= '&usr=' . $self->{user};
    if($self->{password} ne 'NONE') {
        $url .= '&pwd=' . $self->{password};
    } else {
        $url .= '&pwd=';
    }

    #$reph->debuglog('URL: ' . $url);

    my $success = 0;
    my $result;
    if(!(eval {
        $mech->timeout(3);
        $result = $mech->get($url);
        $success = 1;
        1;
    })) {
        $success = 0;
    }
    if($success && defined($result) && $result->is_success) {
        my $content = $result->content;
        return (1, $content);
    }
    return(0);
}

sub drawTimestamp($img) {
    my $datestring = getISODate();
    #$datestring = '01234567890-:';
    my $xlen = length($datestring) * 10 + 3;
    
    $img->set_color(0, 0, 255, 255);
    #$img->fill_rectangle(3, 3, $xlen, 15);
    
    $img->set_color(255, 255, 0, 255);
    my @parts = split//, $datestring;
    my $offs = 0;
    foreach my $part (@parts) {
        $img->set_color(255, 255, 255, 255);
        drawLetter($img, 5 + $offs + 1, 5 + 1, $part);
        drawLetter($img, 5 + $offs - 1, 5 + 1, $part);
        drawLetter($img, 5 + $offs + 1, 5 - 1, $part);
        drawLetter($img, 5 + $offs - 1, 5 - 1, $part);
        $img->set_color(0, 0, 0, 255);
        drawLetter($img, 5 + $offs, 5, $part);
        $offs += 10;
    }
    
    return;
}

sub drawLetter($img, $x, $y, $letter) {
    
    my $segments;
    if($letter eq ' ') {
        $segments = ""
    } elsif($letter eq '0') {
        $segments = "123456";
    } elsif($letter eq '1') {
        $segments = "35";
    } elsif($letter eq '2') {
        $segments = "13746";
    } elsif($letter eq '3') {
        $segments = "13756";
    } elsif($letter eq '4') {
        $segments = "2735";
    } elsif($letter eq '5') {
        $segments = "12756";
    } elsif($letter eq '6') {
        $segments = "127456";
    } elsif($letter eq '7') {
        $segments = "135";
    } elsif($letter eq '8') {
        $segments = "1234567";
    } elsif($letter eq '9') {
        $segments = "12375";
    } elsif($letter eq '0') {
        $segments = "123456";
    } elsif($letter eq ':') {
        $segments = "8";
    } elsif($letter eq '-') {
        $segments = "7";
    }
    
    my @parts = split//, $segments;
    foreach my $part (@parts) {
        drawSegment($img, $x, $y, $part);
    }
    
    return;
}

sub drawSegment($img, $x, $y, $segment) {
if(0) {
    if($segment eq '1') {
        $img->draw_rectangle($x, $y, 10, 2);
    } elsif($segment eq '2') {
        $img->draw_rectangle($x, $y, 2, 10);
    } elsif($segment eq '3') {
        $img->draw_rectangle($x + 10, $y, 2, 10);
    } elsif($segment eq '4') {
        $img->draw_rectangle($x, $y + 10, 2, 10);
    } elsif($segment eq '5') {
        $img->draw_rectangle($x + 10, $y + 10, 2, 10);
    } elsif($segment eq '6') {
        $img->draw_rectangle($x, $y + 20, 10, 2);
    } elsif($segment eq '7') {
        $img->draw_rectangle($x, $y + 10, 10, 2);
    } elsif($segment eq '8') {
        $img->draw_rectangle($x + 5, $y + 5, 2, 2);
        $img->draw_rectangle($x + 5, $y + 15, 2, 2);
    }
}
    
    if($segment eq '1') {
        $img->draw_rectangle($x, $y, 5, 1);
    } elsif($segment eq '2') {
        $img->draw_rectangle($x, $y, 1, 5);
    } elsif($segment eq '3') {
        $img->draw_rectangle($x + 5, $y, 1, 5);
    } elsif($segment eq '4') {
        $img->draw_rectangle($x, $y + 5, 1, 5);
    } elsif($segment eq '5') {
        $img->draw_rectangle($x + 5, $y + 5, 1, 5);
    } elsif($segment eq '6') {
        $img->draw_rectangle($x, $y + 10, 5, 1);
    } elsif($segment eq '7') {
        $img->draw_rectangle($x, $y + 5, 5, 1);
    } elsif($segment eq '8') {
        $img->draw_rectangle($x + 2, $y + 2, 1, 1);
        $img->draw_rectangle($x + 2, $y + 7, 1, 1);
    }
    
    return;
}

1;
__END__

=head1 NAME

PageCamel::Worker::AxisCam - Grab images from AXIS cameras

=head1 SYNOPSIS

  use PageCamel::Worker::AxisCam;

=head1 DESCRIPTION

Grab a new image from AXIS cameras every few seconds

=head2 new

Create new instance

=head2 register

Register work callback

=head2 reload

Check if destination directory exists

=head2 work

Grab an image

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
