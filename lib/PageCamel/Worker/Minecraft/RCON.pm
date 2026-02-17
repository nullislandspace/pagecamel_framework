# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license
package PageCamel::Worker::Minecraft::RCON;
#---AUTOPRAGMASTART---
use v5.42;
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
use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;

use Minecraft::RCON;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;
    
    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{rcon} = Minecraft::RCON->new({password => $self->{password},
                                            address => $self->{ip}, 
                                            port => $self->{port},
                                        });

    return $self;
}

sub run_command($self, $command) {
    my $workCount = 0;
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    $reph->debuglog("Connecting to Minecraft (" . $self->{modname} . ")");
    if(!$self->{rcon}->connect) {
        $reph->debuglog_overwrite("Connection failed to Minecraft (" . $self->{modname} . ")");
        return;
    }

    $reph->debuglog_overwrite("Command: $command");
    my $reply = $self->{rcon}->command($command);
    $reph->debuglog("Result: $reply");
    $self->{rcon}->disconnect;
    return $reply;
}

sub saveall($self) {
    my $reply = $self->run_command("save-all");
    if(defined($reply) && $reply =~ /Saved\ the\ world/i) {
        return 1;
    }
    return 0;
}

sub backup($self) {
    my $reply = $self->run_command("backup");
    if($reply =~ /Started/i) {
        return 1;
    }
    return 0;
}

sub say($self, $text) { ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my $reply = $self->run_command("say $text");
    if(defined($reply)) {
        return 1;
    }
    return 0;
}

sub listWhitelist($self) {
    my $rawlist = $self->run_command("whitelist list");
    if(!defined($rawlist)) {
        return;
    }
    chomp $rawlist;
    $rawlist =~ s/^.*\://g;
    $rawlist =~ s/\,//g;
    my @names = split /\ /, $rawlist;

    return @names;
}

sub addWhitelist($self, $username) {
    my $reply = $self->run_command("whitelist add $username");
    if(defined($reply) && $reply =~ /Added/) {
        return 1;
    }

    return 0;
}

sub removeWhitelist($self, $username) {
    my $reply = $self->run_command("whitelist remove $username");
    if(defined($reply) && $reply =~ /Removed/) {
        return 1;
    }

    return 0;
}

sub teleport($self, $username, $x, $y, $z) {
    my $reply = $self->run_command("tp $username $x $y $z");
    if(defined($reply) && $reply =~ /Teleported/) {
        return 1;
    }

    return 0;
}

1;
