package PageCamel::Worker::Clacks::Bridge;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.3;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

# Do some updates and advanced parsing for accesslog. Run at once an hour. The
# Exception here is: If workCount > 0 then it will ru in the next loop too

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DBSerialize;
use MIME::Base64;
use Net::Clacks::Client;
use PageCamel::Helpers::FileSlurp qw(slurpBinFile);
use MIME::Base64;
use Data::Dumper;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class


    # Sanitize data (empty values get parsed as empty hash instead of empty string)
    if(ref $self->{local2remote}->{addprefix} eq 'HASH') {
        $self->{local2remote}->{addprefix} = '';
    }
    if(ref $self->{local2remote}->{removeprefix} eq 'HASH') {
        $self->{local2remote}->{removeprefix} = '';
    }
    if(ref $self->{remote2local}->{addprefix} eq 'HASH') {
        $self->{remote2local}->{addprefix} = '';
    }
    if(ref $self->{remote2local}->{removeprefix} eq 'HASH') {
        $self->{remote2local}->{removeprefix} = '';
    }

    
    my $clconf = $self->{server}->{modules}->{$self->{local}};
    $self->{localclacks} = Net::Clacks::Client->new($clconf->get('host'), $clconf->get('port'), $clconf->get('user'), $clconf->get('password'), $self->{PSAPPNAME} . ':' . $self->{modname});

    $clconf = $self->{server}->{modules}->{$self->{remote}};
    $self->{remoteclacks} = Net::Clacks::Client->new($clconf->get('host'), $clconf->get('port'), $clconf->get('user'), $clconf->get('password'), $self->{PSAPPNAME} . ':' . $self->{modname});

    return $self;
}


sub register {
    my $self = shift;
    $self->register_worker("work");
    return;
}

sub crossregister {
    my ($self) = @_;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    $self->initLocal();
    $self->initRemote();

    # Listen for new files
    $self->{remoteclacks}->doNetwork();
    $self->{localnextping} = 0;
    $self->{remotenextping} = 0;

    return;

}

sub initLocal {
    my ($self) = @_;

    my $now = time;

    foreach my $varname (@{$self->{local2remote}->{item}}) {
        print "Listening for local $varname\n";
        $self->{localclacks}->listen($varname);
    }
    $self->{localclacks}->ping();
    $self->{localclacks}->doNetwork();
    $self->{localnextping} = $now + 30;

    return;
}

sub initRemote {
    my ($self) = @_;

    my $now = time;

    foreach my $varname (@{$self->{remote2local}->{item}}) {
        print "Listening for remote $varname\n";
        $self->{remoteclacks}->listen($varname);
    }
    $self->{remoteclacks}->ping();
    $self->{remoteclacks}->doNetwork();
    $self->{remotenextping} = $now + 30;

    return;
}


sub work {
    my ($self) = @_;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $workCount = 0;

    my $now = time;
    if($now > $self->{localnextping}) {
        $self->{localclacks}->ping();
        $self->{localnextping} = $now + 30;
        $workCount++;
    }
    if($now > $self->{remotenextping}) {
        $self->{remoteclacks}->ping();
        $self->{remotenextping} = $now + 30;
        $workCount++;
    }

    $self->{localclacks}->doNetwork();
    $self->{remoteclacks}->doNetwork();

    my $first = 1;
    my %sentkeys;
    while((my $message = $self->{localclacks}->getNext())) {
        $workCount++;
        if($message->{type} eq 'disconnect') {
            $self->initLocal();
            $self->{localclacks}->doNetwork();
            next;
        } elsif($message->{type} eq 'set') {
            my $key = $message->{name};

            # Change key prefix according to XML prefix settings
            if(substr($key, 0, length($self->{local2remote}->{removeprefix})) eq $self->{local2remote}->{removeprefix}) {
                substr($key, 0, length($self->{local2remote}->{removeprefix}), '');
            }
            $key = $self->{local2remote}->{addprefix} . $key;
            $reph->debuglog("Sending " . length($message->{data}) . " bytes of data for " . $key);

            # Only send one message for each key in a cycle, ignore all the others.
            # This should eliminate the lag observed during the last few days after DSL disconnects
            if(!defined($sentkeys{$key})) {
                $self->{remoteclacks}->set($key, $message->{data});
                $sentkeys{$key} = 1;
            }
        } elsif($message->{type} eq 'notify') {
            my $key = $message->{name};
            
            # Change key prefix according to XML prefix settings
            if(substr($key, 0, length($self->{local2remote}->{removeprefix})) eq $self->{local2remote}->{removeprefix}) {
                substr($key, 0, length($self->{local2remote}->{removeprefix}), '');
            }
            $key = $self->{local2remote}->{addprefix} . $key;
            $reph->debuglog("Sending notify for " . $key);

            # Only send one message for each key in a cycle, ignore all the others.
            # This should eliminate the lag observed during the last few days after DSL disconnects
            if(!defined($sentkeys{$key})) {
                $self->{remoteclacks}->notify($key);
                $sentkeys{$key} = 1;
            }
        }

    }

    while((my $message = $self->{remoteclacks}->getNext())) {
        $workCount++;
        if($message->{type} eq 'disconnect') {
            # Empty local queue
            $self->{localclacks}->doNetwork();
            while((my $message = $self->{localclacks}->getNext())) {
                $reph->debuglog("Ignoring local data due to remote disconnect");
            }
            $self->initRemote();
            next;

        } elsif($message->{type} eq 'set') {
            my $key = $message->{name};

            # Change key prefix according to XML prefix settings
            if(substr($key, 0, length($self->{remote2local}->{removeprefix})) eq $self->{remote2local}->{removeprefix}) {
                substr($key, 0, length($self->{remote2local}->{removeprefix}), '');
            }
            $key = $self->{remote2local}->{addprefix} . $key;
            $reph->debuglog("Receiving " . length($message->{data}) . " bytes of data for " . $key);

            # Only send one message for each key in a cycle, ignore all the others.
            # This should eliminate the lag observed during the last few days after DSL disconnects
            if(!defined($sentkeys{$key})) {
                $self->{localclacks}->set($key, $message->{data});
                $sentkeys{$key} = 1;
            }
        } elsif($message->{type} eq 'notify') {
            my $key = $message->{name};
            
            # Change key prefix according to XML prefix settings
            if(substr($key, 0, length($self->{remote2local}->{removeprefix})) eq $self->{remote2local}->{removeprefix}) {
                substr($key, 0, length($self->{remote2local}->{removeprefix}), '');
            }
            $key = $self->{remote2local}->{addprefix} . $key;
            $reph->debuglog("Receiving notify for " . $key);

            # Only send one message for each key in a cycle, ignore all the others.
            # This should eliminate the lag observed during the last few days after DSL disconnects
            if(!defined($sentkeys{$key})) {
                $self->{localclacks}->notify($key);
                $sentkeys{$key} = 1;
            }
        }
    }
    $self->{localclacks}->doNetwork();
    $self->{remoteclacks}->doNetwork();

    return $workCount;
}


1;
