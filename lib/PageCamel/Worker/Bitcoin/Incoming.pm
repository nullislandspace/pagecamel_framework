# PAGECAMEL  (C) 2008-2018 Rene Schickbauer
# Developed under Artistic license
package PageCamel::Worker::Bitcoin::Incoming;
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
    
    my $minconf = $btch->getSetting('min_confirmations');

    $reph->debuglog("Incoming transactions");
    
    my $usersth = $dbh->prepare_cached("SELECT * FROM bitcoin_accounts
                                        ORDER BY username")
            or croak($dbh->errstr);
            
    my $selsth = $dbh->prepare_cached("SELECT count(*) FROM bitcoin_transactions
                                      WHERE external_transaction_id = ?")
            or croak($dbh->errstr);
    
    my $insth = $dbh->prepare_cached("INSERT INTO bitcoin_transactions
                                     (address, amount, display_remote_address, booked_remote_address, external_transaction_id,
                                     transaction_type, is_complete, timestamp_booked)
                                     VALUES (?, ?, ?, ?, ?, 'RECIEVE', true, now())")
            or croak($dbh->errstr);
            
    my $upsth = $dbh->prepare_cached("UPDATE bitcoin_accounts SET current_amount = ?
                                     WHERE username = ?")
            or croak($dbh->errstr);
            
    my $unconfsth = $dbh->prepare_cached("UPDATE bitcoin_accounts SET unconfirmed_amount = ?
                                         WHERE username = ?")
            or croak($dbh->errstr);
            
    my $undelsth = $dbh->prepare_cached("DELETE FROM bitcoin_unconfirmed_transactions
                                        WHERE address = ?")
            or croak($dbh->errstr);
            
    my $uninssth = $dbh->prepare_cached("INSERT INTO bitcoin_unconfirmed_transactions
                                        (transaction_id, address, amount, confirmations) VALUES (?,?,?,?)")
            or croak($dbh->errstr);
            
    my @users;
    $usersth->execute or croak($dbh->errstr);
    while((my $user = $usersth->fetchrow_hashref)) {
        push @users, $user;
    }
    $usersth->finish;
    
    foreach my $user (@users) {
        # First, do the confirmed transactions
        {
            #my ($ok, $transactions) = $btch->listIncoming($user->{address}, $minconf);
            my ($ok, $transactions) = $btch->listIncoming($user->{address}, $minconf);
            if(!$ok) {
                $reph->debuglog("Can't get incoming transactions for " . $user->{username});
                next;
            }
            
            foreach my $transaction (@{$transactions}) {
                if(!$selsth->execute($transaction->{txid})) {
                    $reph->debuglog("Error reading transaction from database");
                    $dbh->rollback;
                    next;
                }
                my ($count) = $selsth->fetchrow_array;
                $selsth->finish;
                next if($count); # already exists
                
                if($insth->execute($user->{address},
                                   $transaction->{amount},
                                   $transaction->{address},
                                   $transaction->{address},
                                   $transaction->{txid},
                                   )) {
                    
                    $reph->debuglog("User " . $user->{username} . " recieved " . $transaction->{amount} . " BTC");
                    $dbh->commit;
                    $btch->add_stats_incoming($transaction->{amount});
                    $workCount++;
                    
                } else {
                    $reph->debuglog("Booking failed: " . $dbh->errstr);
                    $dbh->rollback;
                }
            }
            my $newbalance = $btch->getbalance($user->{username}, $minconf);
            if($upsth->execute($newbalance, $user->{username})) {
                $dbh->commit;
            } else {
                $dbh->rollback;
            }
            
        }
        
        # Now get a total amount for unconfirmed transactions for this user
        {
            my ($ok, $amount, $transactions) = $btch->getUnconfirmed($user->{address}, $minconf);
            if(!$ok) {
                $reph->debuglog("Can't get incoming transactions for " . $user->{username});
                next;
            }
            if($unconfsth->execute($amount, $user->{username})) {
                $dbh->commit;
            } else {
                $reph->debuglog("Booking failed: " . $dbh->errstr);
                $dbh->rollback;
            }
            
            # Update the unconfirmed transaction list
            if(!$undelsth->execute($user->{address})) {
                $reph->debuglog("Unconfirmed del failed: " . $dbh->errstr);
                $dbh->rollback;
            } else {
                foreach my $transaction (@{$transactions}) {
                    if(!$uninssth->execute($transaction->{txid},
                                   $transaction->{address},
                                   $transaction->{amount},
                                   $transaction->{confirmations},
                                   )) {
                        $reph->debuglog("Unconfirmed ins failed: " . $dbh->errstr);
                        $dbh->rollback;
                        last;
                    }
                }
                $dbh->commit;
            }
            
        }
    }

    $dbh->commit;
    return $workCount;
}


1;
