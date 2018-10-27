# PAGECAMEL  (C) 2008-2018 Rene Schickbauer
# Developed under Artistic license
package PageCamel::Worker::Bitcoin::BTCHandler;
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

use PageCamel::Helpers::Bitcoind;

my @statskeys;
my @handlerfuncs;


sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;
    
    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my %stats = ();
    $self->{stats} = \%stats;

    $self->resetStats();

    return $self;
}

sub register {
    my $self = shift;
    $self->register_worker("work");
    return;
}

sub reload {
    my ($self) = shift;

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    
    foreach my $key (qw[networkfee domain subdomains]) {
        $sysh->createNumber(modulename => $self->{modname},
                            settingname => $key,
                            settingvalue => $self->{$key},
                            description => 'Trading: ' . $key,
                            value_min => 0.0,
                            value_max => 1.0,
                            processinghints => [
                                'decimal=8',
                                                ])
                or croak("Failed to create setting $key!");
    }

    foreach my $key (qw[min_confirmations]) {
        $sysh->createNumber(modulename => $self->{modname},
                            settingname => $key,
                            settingvalue => $self->{$key},
                            description => 'Trading: ' . $key,
                            value_min => 0,
                            value_max => 30,
                            processinghints => [
                                'decimal=0',
                                                ])
                or croak("Failed to create setting $key!");
    }
    
    $self->{btc} = PageCamel::Helpers::Bitcoind->new($self->{host}, $self->{port}, $self->{user}, $self->{pass});
    
    return;
}


sub work {
    my ($self) = @_;
    
    my $workCount = 0;
    
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};
    
    foreach my $key (qw[min_confirmations networkfee]) {
        # Reload fees from systemsettings
        my ($ok, $data) = $sysh->get($self->{modname}, $key);
        if($ok) {
            $self->{$key} = $data->{settingvalue};
            $workCount++;
        } else {
            croak("System setting $key missing!");
        }
    }
    return $workCount;
}

sub getSetting {
    my ($self, $key) = @_;
    
    my @keys = qw[min_confirmations networkfee];
    croak("Unknown setting $key") unless(contains($key, \@keys));
    
    return $self->{$key};
}

BEGIN {
    @statskeys = qw[incoming outgoing transfer];

    for my $a (@statskeys){
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
        *{__PACKAGE__ . "::add_stats_$a"} = sub { 
            $_[0]->{stats}->{$a} += abs($_[1]);
            return;
        };
        *{__PACKAGE__ . "::get_stats_$a"} = sub { 
            return $_[0]->{stats}->{$a};
        };
    }

    @handlerfuncs = qw[getAddress getUser move sendFrom listIncoming getUnconfirmed backupwallet settxfee
                        getbalance];
        
    for my $a (@handlerfuncs){
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
        *{__PACKAGE__ . "::$a"} = sub {
            my ($xself, @xargs) = @_;
            return $xself->{btc}->$a(@xargs);
        };
    }
}

sub resetStats {
    my ($self) = @_;

    foreach my $key (@statskeys) {
        $self->{stats}->{$key} = 0;
    }

    return;
}

1;
