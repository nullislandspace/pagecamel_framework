package PageCamel::Web::Tools::WorkerControl;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.5;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseWebSocket);
use PageCamel::Helpers::DateStrings;
use Net::Clacks::Client;

# play -t raw -r 11025 -e signed-integer -b 16 -c 1 rawaudio.dat

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{extrasettings} = [];
    $self->{template} = 'tools/workercontrol';

    return $self;
}

sub wsmaskget {
    my ($self, $ua, $settings, $webdata) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my @workers;
    my $selsth = $dbh->prepare_cached("SELECT * FROM system_settings
                                        WHERE modulename = 'pagecamel_services'
                                        AND settingname LIKE '%_enable'
                                        ORDER BY settingname")
            or croak($dbh->errstr);
    if(!$selsth->execute()) {
        $dbh->rollback;
        return;
    } else {
        while((my $line = $selsth->fetchrow_hashref)) {
            my $statusname = $line->{settingname};
            $statusname =~ s/\_enable$/_status/;
            my $workername;
            foreach my $hint (@{$line->{processinghints}}) {
                if($hint =~ /^modulename\=(.*)/) {
                    $workername = $1;
                }
            }
            if($line->{settingvalue} != 1) {
                $line->{settingvalue} = 0;
            }
            my $realworkername = lc $workername;
            $realworkername =~ s/\ /_/g;
            my %worker = (
                buttonname => $line->{settingname},
                buttonstatus => $line->{settingvalue},
                statusname => $statusname,
                workername => $workername,
                realworkername => $realworkername,
            );

            push @workers, \%worker;
        }
        $selsth->finish;
    }
    $webdata->{Workers} = \@workers;
    $dbh->commit;

    return;
}

sub wshandlerstart {
    my ($self, $ua, $settings) = @_;

    $self->{nextping} = time + 10;

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};

    $self->{clacks} = $self->newClacksFromConfig($clconf);

    return;
}

sub wscleanup {
    my ($self) = @_;

    delete $self->{nextping};
    delete $self->{clacks};

    return;
}

sub wshandlemessage {
    my ($self, $message) = @_;

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    if($message->{type} eq 'LISTEN') {
        $self->{clacks}->listen('pagecamel_services::' . $message->{varname});
    } elsif($message->{type} eq 'NOTIFY') {
        $self->{clacks}->notify('pagecamel_services::' . $message->{varname});
    } elsif($message->{type} eq 'SET') {
        $self->{clacks}->set('pagecamel_services::' . $message->{varname}, $message->{varvalue});
        if($message->{varname} ne 'restart::service') {
            $sysh->set('pagecamel_services', $message->{varname}, $message->{varvalue});
        }
    }


    return 1;
}

sub wscyclic {
    my ($self) = @_;

    my $now = time;
    if($now > $self->{nextping}) {
        $self->{clacks}->ping();
        $self->{nextping} = $now + 10;
    }

    while(1) {
        my $cmsg = $self->{clacks}->getNext();
        last unless defined($cmsg);

        if($cmsg->{type} eq 'set') {
            my $jtype;
            if($cmsg->{name} =~ /_status$/) {
                $jtype = 'LED';
            } elsif($cmsg->{name} =~ /_enable$/) {
                $jtype = 'SWITCH';
            } else {
                next;
            }
            my $webname = $cmsg->{name};
            $webname =~ s/^pagecamel_services\:\://;
            my %msg = (
                type => $jtype,
                varname => $webname,
                varval => $cmsg->{data},
            );
            if(!$self->wsprint(\%msg)) {
                print STDERR "Write to socket failed, closing connection!\n";
                return 0;
            }
        }
    }

    $self->{clacks}->doNetwork();

    return 1;
}

1;
__END__
