package PageCamel::CMDLine::DHCP;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.3;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use PageCamel::Helpers::ConfigLoader;
use PageCamel::Helpers::Logo;
use Sys::Hostname;
use DBI;
use Net::DHCP::Packet;
use Net::DHCP::Constants;
use IO::Socket::IP;


my $keepRunning = 1;
# generic signal handler to cause daemon to stop
sub signal_handler {
    $keepRunning = 0;
}
$SIG{INT} = $SIG{TERM} = $SIG{HUP} = \&signal_handler;

# trap or ignore $SIG{PIPE}

# Daemon behaviour
# ignore any PIPE signal: standard behaviour is to quit process
$SIG{PIPE} = 'IGNORE';


sub logger($str) {
    #print STDOUT strftime "[%d/%b/%Y:%H:%M:%S] ", localtime;
    print STDOUT "$str\n";
}



sub new($class, $isDebugging, $configfile) {
    my $self = bless {}, $class;

    $self->{isDebugging} = $isDebugging;
    $self->{configfile} = $configfile;

    croak("Config file $configfile not found!") unless(-f $configfile);

    return $self;
}

sub init($self) {

    print "Loading config file ", $self->{configfile}, "\n";
    my $config = LoadConfig($self->{configfile},
                        ForceArray => [ ],);

    $self->{config} = $config;

    my $APPNAME = $config->{appname};
    PageCamelLogo($APPNAME, $VERSION);
    print "Changing application name to '$APPNAME'\n\n";
    my $ps_appname = lc($APPNAME);
    $ps_appname =~ s/[^a-z0-9]+/_/gio;

    $0 = $ps_appname;

    my @runargs;

    # Debugging on port 6700
    if(0 && $self->{isDebugging}) {
        $config->{port} = 6700;
    } else {
        $config->{port} = 67;
    }

    my $hname = hostname();
    if(!defined($config->{$hname})) {
        die("Config has no config for " . hostname());
    }

    # Copy host specific config to root
    foreach my $key (keys %{$config->{$hname}}) {
        $config->{$key} = $config->{$hname}->{$key};
    }

    my $dbh = DBI->connect($config->{dburl}, $config->{dbuser}, $config->{dbpassword}, {AutoCommit => 0, RaiseError => 0})
            or croak("Can't connect to database: $!");
    $self->{dbh} = $dbh;

    my $selstmt = 'SELECT ' . $config->{dbhostname} . ' AS hname, ' . $config->{dbip} . ' AS dbip ' .
                  ' FROM ' . $config->{dbtable} .
                  ' WHERE ' . $config->{dbmac} . ' = ? LIMIT 1';
    my $selsth = $dbh->prepare_cached($selstmt)
            or croak($dbh->errstr);

    my $logsth = $dbh->prepare_cached("INSERT INTO dhcplog (requesttype, vendorclass, ipaddress, macaddress, hostname, is_refused) " .
                                      "VALUES (?, ?, ?, ?, ?, ?)")
            or croak($dbh->errstr);

    $self->{selsth} = $selsth;
    $self->{logsth} = $logsth;

    my $socket = IO::Socket::IP->new(
        LocalPort => $config->{port},
        LocalAddr => '255.255.255.255',
        #PeerAddr => '255.255.255.255',
        Proto     => 'udp',
        ReuseAddr => 1,
        Broadcast => 1,
    ) || die "Socket creation error: $@\n";

    $self->{socket} = $socket;

    print "Listening on " . $config->{ip} . ':' . $config->{port} . "\n";

    return;

}

sub run($self) {

    my $buf = undef;
    my $fromaddr;       # address & port from which packet was received
    my $dhcpreq;
    my $transaction = 0;    # report transaction number

    while($keepRunning) {

        eval {              # catch fatal errors
            logger("Waiting for incoming packet");

            # receive packet
            $fromaddr = $self->{socket}->recv( $buf, 4096 ) || logger("recv:$!");
            next if ($!);    # continue loop if an error occured
            $transaction++;  # transaction counter

            {
                use bytes;
                my ($port, $addr) = unpack_sockaddr_in($fromaddr);
                my $ipaddr = inet_ntoa($addr);
                logger("Got a packet tr=$transaction src=$ipaddr:$port length="
                      . length($buf));
            }

            my $dhcpreq = Net::DHCP::Packet->new($buf);
            $dhcpreq->comment($transaction);

            my $messagetype = $dhcpreq->getOptionValue( DHO_DHCP_MESSAGE_TYPE() );
            next if(!defined($messagetype));

            if($messagetype eq DHCPDISCOVER()) {
                print "DISCOVER...\n";
                $self->do_discover($dhcpreq);
            } elsif($messagetype eq DHCPREQUEST()) {
                print "REQUEST...\n";
                $self->do_request($dhcpreq);
            } elsif($messagetype eq DHCPINFORM()) {
                print "INFORM...\n";
                # ??????????
            } else {
                # bad messagetype, we drop it
                logger("Packet dropped");
            }
        };    # end of 'eval' blocks
        if ($@) {
            logger("Caught error in main loop:$@");
        }
    }
    return;
}

sub do_discover($self, $dhcpreq) {

    # Get IP from database
    my $mac = $self->parseMac($dhcpreq->chaddr());
    my $vendor = $dhcpreq->getOptionValue( DHO_VENDOR_CLASS_IDENTIFIER() ) || '';

    if(!$self->{selsth}->execute($mac)) {
        logger("DB ERROR: " . $self->{dbh}->errstr);
        $self->{dbh}->rollback;
    }
    my $line = $self->{selsth}->fetchrow_hashref;
    $self->{selsth}->finish;
    $self->{dbh}->commit;

    if(!defined($line)) {
        #(requesttype, vendorclass, ipaddress, macaddress, hostname, is_refused)
        $self->logdb('DISCOVER', $vendor, undef, $mac, undef, 1);
        return;
    } elsif(!defined($line->{dbip})) {
        $self->logdb('DISCOVER', $vendor, undef, $mac, $line->{hname}, 1);
        return;
    } else {
        $self->logdb('DISCOVER', $vendor, $line->{dbip}, $mac, $line->{hname}, 1);
    }

    my $dhcpresp = Net::DHCP::Packet->new(
        Comment                 => $dhcpreq->comment(),
        Op                      => BOOTREPLY(),
        Hops                    => $dhcpreq->hops(),
        Xid                     => $dhcpreq->xid(),
        Flags                   => $dhcpreq->flags(),
        Ciaddr                  => $dhcpreq->ciaddr(),
        Yiaddr                  => $line->{dbip},
        Siaddr                  => $self->{config}->{ip},
        Giaddr                  => $self->{config}->{gateway},
        Chaddr                  => $dhcpreq->chaddr(),
        DHO_DHCP_MESSAGE_TYPE() => DHCPOFFER(),
    );

    logger("Sending response");

    # Socket object keeps track of whom sent last packet
    # so we don't need to specify target address
    logger( "Sending OFFER tr=" . $dhcpresp->comment() );
    $self->{socket}->send( $dhcpresp->serialize() ) || die "Error sending OFFER:$!\n";
    return;
}

sub do_request($self, $dhcpreq) {

    # Get IP from database
    my $mac = $self->parseMac($dhcpreq->chaddr());
    my $vendor = $dhcpreq->getOptionValue( DHO_VENDOR_CLASS_IDENTIFIER() ) || '';

    if(!$self->{selsth}->execute($mac)) {
        logger("DB ERROR: " . $self->{dbh}->errstr);
        $self->{dbh}->rollback;
    }
    my $line = $self->{selsth}->fetchrow_hashref;
    $self->{selsth}->finish;
    $self->{dbh}->commit;

    my $iperror = 0;
    if($line->{dbip} ne $dhcpreq->getOptionValue(DHO_DHCP_REQUESTED_ADDRESS())) {
        $iperror = 1;
    }

    if(!defined($line)) {
        #(requesttype, vendorclass, ipaddress, macaddress, hostname, is_refused)
        $self->logdb('REQUEST', $vendor, undef, $mac, undef, 1);
        return;
    } elsif(!defined($line->{dbip})) {
        $self->logdb('REQUEST', $vendor, undef, $mac, $line->{hname}, 1);
        return;
    } else {
        $self->logdb('REQUEST', $vendor, $line->{dbip}, $mac, $line->{hname}, $iperror);
    }

    my $dhcpresp;
    if(!$iperror){
        # address is correct, we send an ACK
        $dhcpresp = Net::DHCP::Packet->new(
            Comment                 => $dhcpreq->comment(),
            Op                      => BOOTREPLY(),
            Hops                    => $dhcpreq->hops(),
            Xid                     => $dhcpreq->xid(),
            Flags                   => $dhcpreq->flags(),
            Ciaddr                  => $dhcpreq->ciaddr(),
            Yiaddr                  => $line->{dbip},
            Siaddr                  => $self->{config}->{ip},
            Giaddr                  => $self->{config}->{gateway},
            Chaddr                  => $dhcpreq->chaddr(),
            DHO_DHCP_MESSAGE_TYPE() => DHCPACK(),
        );
    } else {
        # bad request, we send a NAK
        $dhcpresp = Net::DHCP::Packet->new(
            Comment                 => $dhcpreq->comment(),
            Op                      => BOOTREPLY(),
            Hops                    => $dhcpreq->hops(),
            Xid                     => $dhcpreq->xid(),
            Flags                   => $dhcpreq->flags(),
            Ciaddr                  => $dhcpreq->ciaddr(),
            Yiaddr                  => "0.0.0.0",
            Siaddr                  => $dhcpreq->siaddr(),
            Giaddr                  => $dhcpreq->giaddr(),
            Chaddr                  => $dhcpreq->chaddr(),
            DHO_DHCP_MESSAGE_TYPE() => DHCPNAK(),
            DHO_DHCP_MESSAGE()      => "Bad request...",
        );
    }


    logger("Sending response");

    # Socket object keeps track of whom sent last packet
    # so we don't need to specify target address
    logger( "Sending ACK/NACK tr=" . $dhcpresp->comment() );
    $self->{socket}->send( $dhcpresp->serialize() ) || die "Error sending OFFER:$!\n";
    return;
}

sub logdb($self, $type, $vendor, $ip, $mac, $hname, $refused) {

    if(!$self->{logsth}->execute($type, $vendor, $ip, $mac, $hname, $refused)) {
        logger("DB ERROR: " . $self->{dbh}->errstr);
        $self->{dbh}->rollback;
    } else {
        $self->{dbh}->commit;
    }

    return;
}

sub parseMac($self, $rawmac) {

    $rawmac = substr($rawmac, 0, 12);
    my @parts = split//, $rawmac;
    my $mac = '';
    while(@parts) {
        if($mac ne '') {
            $mac .= ':';
        }
        $mac .= shift @parts;
        $mac .= shift @parts;
    }

    return $mac;
}


1;
