# PAGECAMEL  (C) 2008-2018 Rene Schickbauer
# Developed under Artistic license
package PageCamel::Worker::Bitcoin::CreateAccounts;
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

    $reph->debuglog("Create new accounts");
    
    my $selsth = $dbh->prepare_cached("SELECT u.username FROM users u
                                        WHERE NOT EXISTS (
                                            SELECT 1 FROM bitcoin_accounts b
                                            WHERE b.username = u.username
                                        ) AND EXISTS (
                                            SELECT 1 FROM users_permissions p
                                            WHERE u.username = p.username
                                            AND p.permission_name = 'has_trading'
                                            AND p.has_access = true
                                        )
                                        ORDER BY u.username")
            or croak($dbh->errstr);
            
    my $insth = $dbh->prepare_cached("INSERT INTO bitcoin_accounts (username, address, current_amount)
                                     VALUES (?, ?, 0.0)")
            or croak($dbh->errstr);
    my @users;
    $selsth->execute or croak($dbh->errstr);
    while((my $user = $selsth->fetchrow_hashref)) {
        push @users, $user->{username};
    }
    $selsth->finish;
    
    foreach my $user (@users) {
        my ($ok, $address) = $btch->getAddress($user);
        if(!$ok) {
            $reph->debuglog("Can't get address for user $user");
        } elsif(!$insth->execute($user, $address)) {
            $reph->debuglog("Can't create bitcoin account for user $user");
            $dbh->rollback;
        } else {
            $workCount++;
        }
        $dbh->commit;
    }

    $dbh->commit;
    return $workCount;
}


1;
