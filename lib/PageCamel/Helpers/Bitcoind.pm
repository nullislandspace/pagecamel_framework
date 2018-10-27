package PageCamel::Helpers::Bitcoind;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 1;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use JSON::RPC::Legacy::Client;

sub new {
    my ($class, $host, $port, $user, $pass) = @_;


    my %data = (
        host    => $host,
        port    => $port,
        user    => $user,
        pass    => $pass,
    );

    my $self = bless \%data, $class;
    
    $self->{client} = JSON::RPC::Legacy::Client->new();

    $self->{client}->ua->credentials("$host:$port", "jsonrpc", $user => $pass);

    $self->{uri} = "http://$host:$port/";
    
    return $self;
}

sub call {
    my ($self, $method, @params) = @_;

    #print STDERR "*** ", $method, " ***\n";
    my $obj = {
        method  => $method,
        params  => \@params,
    };

    my $res = $self->{client}->call($self->{uri}, $obj);
    if(!defined($res)) {
        return(0, $self->{client}->status_line);
    }

    if($res->is_error) {
        return(0, $res->error_message);
    }

    return(1, $res->result);
}


sub getAddress {
    my ($self, $user) = @_;

    return $self->call('getaccountaddress', $user);
}

sub getUser {
    my ($self, $address) = @_;

    return $self->call('getaccount', $address);
}


sub move {
    my ($self, $fromAddress, $toAddress, $amount) = @_;
    
    $amount = $self->fixAmount($amount);

    my ($okFrom, $fromUser) = $self->getUser($fromAddress);
    my ($okTo, $toUser) = $self->getUser($toAddress);

    if(!$okFrom || !$okTo) {
        return(0, 'Error: not internal address(es)');
    }

    return $self->call('move', $fromUser, $toUser, $amount);
}

sub sendFrom {
    my ($self, $fromUser, $toAddress, $amount) = @_;
    
    $amount = $self->fixAmount($amount);

    my ($okTo, $toUser) = $self->getUser($toAddress);

    if(!$okTo) {
        return(0, 'Error: not internal address(es)');
    }

    return $self->call('sendfrom', $fromUser, $toAddress, $amount);
}

sub listIncoming {
    my ($self, $toAddress, $minconf) = @_;

    my ($okTo, $toUser) = $self->getUser($toAddress);

    if(!$okTo) {
        return(0, 'Error: not internal address(es)');
    }

    my ($ok, $trans) = $self->call('listtransactions', $toUser, 5000);

    if(!$ok) {
        return (0, $trans);
    }

    # Now, filter so we only show the confirmed incoming transactions
    my @transactions;
    foreach my $tra (@{$trans}) {
        next if(!defined($tra->{category}) || $tra->{category} ne 'receive');
        next if(!defined($tra->{confirmations}) || $tra->{confirmations} < $minconf);

        my %conf;
        foreach my $key (qw[address amount txid]) {
            $conf{$key} = $tra->{$key};
        }
        push @transactions, \%conf;
    }

    return(1, \@transactions);
}

sub getUnconfirmed {
    my ($self, $toAddress, $minconf) = @_;

    my ($okTo, $toUser) = $self->getUser($toAddress);

    if(!$okTo) {
        return(0, 'Error: not internal address(es)');
    }

    my ($ok, $trans) = $self->call('listtransactions', $toUser, 5000);

    if(!$ok) {
        return (0, $trans);
    }

    # Now, filter so we only show the confirmed incoming transactions
    my $unconfirmed = 0.0;
    my @transactions;
    foreach my $tra (@{$trans}) {
        next if(!defined($tra->{category}) || $tra->{category} ne 'receive');
        next if(!defined($tra->{confirmations}) || $tra->{confirmations} >= $minconf);

        $unconfirmed += $tra->{amount};
        my %unconf;
        foreach my $key (qw[address amount txid confirmations]) {
            $unconf{$key} = $tra->{$key};
        }
        push @transactions, \%unconf;
    }

    return(1, $unconfirmed, \@transactions);
}

sub settxfee {
    my ($self, $fee) = @_;

    $fee = $self->fixAmount($fee);
    
    return $self->call('settxfee', $fee);
}

sub backupwallet {
    my ($self, $filename) = @_;

    return $self->call('backupwallet', $filename);
}

sub getbalance {
    my ($self, $username, $minconf) = @_;
    
    return $self->call('getbalance', $username, 0 + $minconf);
}

sub fixAmount {
    my ($self, $amount) = @_;
    
    return $amount + 0.0;
    #return sprintf '%.8f', $amount;
    #return sprintf '%.0f', 1e8 * $amount;
    
}


1;
