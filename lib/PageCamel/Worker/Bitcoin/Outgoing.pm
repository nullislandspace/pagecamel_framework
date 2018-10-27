# PAGECAMEL  (C) 2008-2018 Rene Schickbauer
# Developed under Artistic license
package PageCamel::Worker::Bitcoin::Outgoing;
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

    $reph->debuglog("Outgoing transactions");
    
    my $minconf = $btch->getSetting('min_confirmations');
    my $networkfee = $btch->getSetting('networkfee');
    
    my ($feeok, $feeerror) = $btch->settxfee($networkfee);
    if(!$feeok) {
        $reph->debuglog("Can't set network fee");
        return $workCount;
    }
    
    my $selsth = $dbh->prepare_cached("SELECT * FROM bitcoin_transactions
                                      WHERE is_complete = false
                                      AND transaction_type = 'TRANSMIT'
                                      ORDER BY transaction_id
                                      LIMIT 100")
            or croak($dbh->errstr);

    my $upsth = $dbh->prepare_cached("UPDATE bitcoin_transactions
                                     SET transaction_type = ?,
                                     is_complete = ?,
                                     has_error = ?,
                                     errortext = ?,
                                     booked_remote_address = ?,
                                     transaction_fee = ?
                                     WHERE transaction_id = ?")
            or croak($dbh->errstr);
            
    my $insth = $dbh->prepare_cached("INSERT INTO bitcoin_transactions
                                     (address, amount, display_remote_address, booked_remote_address, external_transaction_id,
                                     transaction_type, is_complete, timestamp_booked)
                                     VALUES (?, ?, ?, ?, ?, ?, true, now())")
            or croak($dbh->errstr);
            
    my $booksth = $dbh->prepare_cached("UPDATE bitcoin_accounts SET current_amount = ?
                                     WHERE username = ?")
            or croak($dbh->errstr);
            
    my $accountsth = $dbh->prepare_cached("SELECT * FROM bitcoin_accounts WHERE address = ?")
            or croak($dbh->errstr);
            
    $selsth->execute or croak($dbh->errstr);
    my @transactions;
    while((my $transaction = $selsth->fetchrow_hashref)) {
        $transaction->{amount} = abs($transaction->{amount});
        push @transactions, $transaction;
    }
    $selsth->finish;
    
    foreach my $transaction (@transactions) {
        my $fee = $networkfee;
        my ($ok, $destuser) = $btch->getUser($transaction->{display_remote_address});
        if($ok && defined($destuser) && $destuser ne '') {
            $transaction->{transaction_type} = 'MOVE_OUT';
            $fee = 0.0;
        }
        
        $accountsth->execute($transaction->{address}) or croak($dbh->errstr);
        my $account = $accountsth->fetchrow_hashref;
        $accountsth->finish;
        
        if($account->{current_amount} < ($transaction->{amount} + $fee)) {
            # No money left on device ;-)
            $reph->debuglog("User " . $account->{username} . " is bankrupt");
            $upsth->execute($transaction->{transaction_type}, 1, 1, 'Not enough BTC to complete transaction', '', 0, $transaction->{transaction_id})
                    or croak($dbh->errstr);
            $dbh->commit;
            next;
        }
        
        if($transaction->{transaction_type} eq 'MOVE_OUT') {
            
            if($upsth->execute($transaction->{transaction_type}, 1, 0, '', $transaction->{address}, $fee, $transaction->{transaction_id}) &&
               $insth->execute($transaction->{display_remote_address}, $transaction->{amount}, $transaction->{address}, $transaction->{address}, $transaction->{transaction_id}, 'MOVE_IN')) {
                
                my ($ok1, $error1) = $btch->move($transaction->{address}, $transaction->{display_remote_address}, $transaction->{amount});
                if(!$ok1) {
                    $reph->debuglog("Error1: $error1");
                    $dbh->rollback;
                    next;
                }
                
                $btch->add_stats_transfer($transaction->{amount});
                $workCount++;
                $dbh->commit;
             
                foreach my $upaddress (($transaction->{address}, $transaction->{display_remote_address})) {
                    $accountsth->execute($upaddress);
                    my $accountdata = $accountsth->fetchrow_hashref;
                    $accountsth->finish;
                    my $newbalance = $btch->getbalance($accountdata->{username}, $minconf);
                    if($booksth->execute($newbalance, $accountdata->{username})) {
                        $dbh->commit;
                    } else {
                        $dbh->rollback;
                    }
                }
                
                next;
                
            } else {
                $reph->debuglog("DB Error: " . $dbh->errstr);
                $dbh->rollback;
                next;
            }

        } elsif($transaction->{transaction_type} eq 'TRANSMIT') {
            # Transmitting is very similar, but a bit simpler, since we basically only
            # do one side of the transaction, while the other one is done by the bitcoin
            # network: First me move amount and fee into the pool account, the we transmit
            # the amount (including the preset network fee across the network)

            if($upsth->execute($transaction->{transaction_type}, 1, 0, '', $transaction->{display_remote_address}, $fee, $transaction->{transaction_id})) {
                $accountsth->execute($transaction->{address});
                my $accountdata = $accountsth->fetchrow_hashref;
                $accountsth->finish;
                                
                my ($ok2, $error2) = $btch->sendFrom($accountdata->{username}, $transaction->{display_remote_address}, $transaction->{amount});
                if(!$ok2) {
                    $reph->debuglog("Error2: $error2");
                    $dbh->rollback;
                    next;
                }
                
                $btch->add_stats_outgoing($transaction->{amount});
                $workCount++;
                $dbh->commit;
                
                my $newbalance = $btch->getbalance($accountdata->{username}, $minconf);
                if($booksth->execute($newbalance, $accountdata->{username})) {
                    $dbh->commit;
                } else {
                    $dbh->rollback;
                }
                
                next;
                
            } else {
                $reph->debuglog("DB Error: " . $dbh->errstr);
                $dbh->rollback;
                next;
            }
        }
    }
    
    $dbh->commit;
    return $workCount;
}


1;
