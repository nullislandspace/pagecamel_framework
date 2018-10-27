# PAGECAMEL  (C) 2008-2018 Rene Schickbauer
# Developed under Artistic license
package PageCamel::Web::Bitcoin::Account;
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

use base qw(PageCamel::Web::BaseModule);

use PageCamel::Helpers::Strings qw[stripString];

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;
    
    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class
        
    return $self;
}

sub register {
    my $self = shift;

    $self->register_webpath($self->{webpath}, "get_account");
    return;
}

sub reload {
    my ($self) = @_;

    # Nothing to do

    return;
}

sub get_account {
    my ($self, $ua) = @_;
    
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    
    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        PostLink    =>  $self->{webpath},
    );
    
    my $mode = $ua->{postparams}->{'mode'} || 'view';
    my $method = $ua->{method} || '';
    
    if($mode eq 'send' && $method ne 'POST') {
        # some kind of trickery, i presume. While this should be prevented
        # already by the framework, this masks handles financial transacrions.
        # So, better double check
        return (status => 414,
                type => 'text/plain',
                data => 'Something went from with your webform submission.');
    }
    
    my $destaddress = $ua->{postparams}->{'destination_address'} || '';
    my $destamount = $ua->{postparams}->{'destination_amount'} || '';
    
    if($destaddress eq '' && $destamount eq '') {
        $mode = 'view';
    }    
    
    my $ready = 0;
    my $selsth = $dbh->prepare_cached("SELECT address, current_amount, unconfirmed_amount
                                      FROM bitcoin_accounts
                                      where username = ?")
            or croak($dbh->errstr);
    $selsth->execute($webdata{userData}->{user});
    my ($address, $amount, $unconfirmed) = $selsth->fetchrow_array;
    $selsth->finish;
    $dbh->rollback;
    
    if(defined($address)) {
        $ready = 1;
        $webdata{address} = $address;
        $webdata{current_amount} = sprintf "%.8f", $amount;
        $webdata{unconfirmed_amount} = sprintf "%.8f", $unconfirmed;
    }
    $webdata{account_ready} = $ready;
    
    if($ready && $mode eq 'send') {        
        $destaddress = stripString($destaddress);
        $destamount = 0.0 + stripString($destamount);
        
        if($destamount <= 0.0) {
            $webdata{statuscolor} = 'errortext';
            $webdata{statustext} = 'Invalid amount';
        } elsif(length($destaddress) < 25) {
            $webdata{statuscolor} = 'errortext';
            $webdata{statustext} = 'Invalid/incomplete destination address';            
        } else {
            my $insth = $dbh->prepare_cached("INSERT INTO bitcoin_transactions (address, amount, display_remote_address, transaction_type)
                                        values (?, ?, ?, 'TRANSMIT')")
                    or croak($dbh->errstr);
            if(!$insth->execute($address, $destamount, $destaddress)) {
                $dbh->rollback;
                $webdata{statuscolor} = 'errortext';
                $webdata{statustext} = 'Internal error while creating the transaction';
            } else {
                $dbh->commit;
                $webdata{statuscolor} = 'oktext';
                $webdata{statustext} = 'Transfer scheduled';
            }
        }
    }    
    
    my $abooksth = $dbh->prepare_cached("SELECT * FROM bitcoin_addressbook_by_username
                                        WHERE username = ?")
            or croak($dbh->errstr);
    my @abooks;
    if($abooksth->execute($webdata{userData}->{user})) {
        while((my $abook = $abooksth->fetchrow_hashref)) {
            push @abooks, $abook;
        }
        $abooksth->finish;
    }
    $dbh->rollback;
    $webdata{abooks} = \@abooks;
    
    foreach my $key (qw[bankfee internalbankfee networkfee]) {
        # Reload fees from systemsettings
        my ($ok, $data) = $sysh->get($self->{bitcoinhandler}, $key);
        if($ok) {
            $webdata{$key} = $data->{settingvalue};
        } else {
            croak("System setting $key missing!");
        }
    }    
    
    
    my $template = $self->{server}->{modules}->{templates}->get("bitcoin/account", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
    
}

1;
__END__
