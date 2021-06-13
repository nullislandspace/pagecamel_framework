package PageCamel::Worker::Logging::Plugins::Ping;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.6;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::Logging::PluginBase);

use Net::Ping;
use Net::Ping::External; # For more reliable ICMP. We don't use this
                         # directly, just making sure it is included in the Makefile.PL requirements

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub crossregister {
    my $self = shift;

    $self->register_plugin('work', 'PING', 'ICMP');
    $self->register_plugin('work', 'PING', 'TCP');
    $self->register_plugin('work', 'PING', 'UDP');
    return;
}

sub work {
    my ($self, $device, $dbh, $reph, $memh) = @_;

    my $workCount = 0;

    $reph->debuglog("Logging PING for " . $device->{hostname});
    # Refresh Lifetick every now and then
    $memh->refresh_lifetick;
    my $okcount = 0;
    my $failcount = 0;
    my $proto = lc $device->{device_subtype};
    if($proto eq 'icmp') {
        # Use system ping utility. This solves the problem with
        # requiring root user to send ICMP packets, because the
        # command line ping is already allowed to do that for ALL
        # users anyway (SUID ROOT)
        $proto = 'external'; 
    }
    my $pinger = Net::Ping->new($proto);
    my $timeout = 3;
    my $deviceok = 1;
    for(1..5) {
        my $pingevalok = 0;
        eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
            $workCount++;
            if($pinger->ping($device->{hostname}, $timeout)) {
                $okcount++;
            } else {
                $failcount++;
                $deviceok = 0;
            }
            $pingevalok = 1;
        };
        if(!$pingevalok) {
            $deviceok = 0;
            $failcount++;
        }
    }
    
    $reph->debuglog("    OK: $okcount  FAIL: $failcount");
    my $insth = $dbh->prepare_cached('INSERT INTO logging_log_ping (hostname, device_type, device_ok, ping_ok_count, ping_fail_count)
                                     VALUES (?, ?, ?, ?, ?)')
            or croak($dbh->errstr);
    if(!$insth->execute($device->{hostname}, $device->{device_type}, $deviceok, $okcount, $failcount)) {
        $reph->debuglog("INSERT FAILED: " . $dbh->errstr);
        $dbh->rollback;
        
    } else {
        $dbh->commit;
    }

    return $workCount;
}

1;
__END__
