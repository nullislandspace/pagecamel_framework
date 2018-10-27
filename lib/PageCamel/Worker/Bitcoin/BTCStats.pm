# PAGECAMEL  (C) 2008-2018 Rene Schickbauer
# Developed under Artistic license
package PageCamel::Worker::Bitcoin::BTCStats;
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
use base qw(PageCamel::Worker::BaseModule);

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;
    
    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub register {
    my $self = shift;
    $self->register_worker("work");
    return;
}


sub work {
    my ($self) = @_;
    
    my $workCount = 0;
    
    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $btch = $self->{server}->{modules}->{$self->{handler}};
    
    $reph->debuglog("BTC Stats");
    
    my $incoming = $btch->get_stats_incoming;
    my $outgoing = $btch->get_stats_outgoing;
    my $transfer = $btch->get_stats_transfer;
    
    my $insth = $dbh->prepare_cached("INSERT INTO logging_log_bitcoins (hostname, device_type, total_amount,
                                        unconfirmed_amount, incoming_amount, outgoing_amount, transfer_amount)
                                     VALUES ('" . $self->{devicename} . "', 'BTCTrading', ?, ?, ?, ?, ?)")
            or croak($dbh->errstr);
    my $selsth = $dbh->prepare_cached("SELECT sum(current_amount) AS total, 
                                        sum(unconfirmed_amount) AS unconfirmed 
                                        FROM bitcoin_accounts")
            or croak($dbh->errstr);
            
    if(!$selsth->execute) {
        $dbh->rollback;
        $reph->debuglog("Stats failed (1)");
        return $workCount;
    }
    my ($total, $unconfirmed) = $selsth->fetchrow_array;
    $selsth->finish;
    
    if(!$insth->execute($total, $unconfirmed, $incoming, $outgoing, $transfer)) {
        $dbh->rollback;
        $reph->debuglog("Stats failed (2)");
        return $workCount;
    }
    
    $workCount++;
    $btch->resetStats();

    $dbh->commit;
    return $workCount;
}


1;
