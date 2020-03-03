package PageCamel::DNS;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.0;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

#use base qw(PageCamel::Net::Server::PreFork);

use Data::Dumper;
use Net::DNS::Packet;
use Net::DNS::Resolver;
use Net::DNS::Resolver::Recurse;
use DBI;
use PageCamel::Helpers::DateStrings;
use Readonly;
use Time::HiRes qw[time sleep];
use PageCamel::Helpers::WebPrint;
use Errno qw( EINPROGRESS EWOULDBLOCK EISCONN );
use Net::Clacks::Client;
use MIME::Base64;

Readonly my $RECURSIVELOOKUP => '999.999.999.999';

use Net::Server::PreFork;
use Net::Server::Single;

our @ISA; ## no critic (ClassHierarchies::ProhibitExplicitISA)
sub setThreadingMode {
    my($isDebugging) = @_;

    if(0 && $isDebugging) {
        push @ISA, 'Net::Server::Single'; ## no critic (ClassHierarchies::ProhibitExplicitISA)
    } else {
        push @ISA, 'Net::Server::PreFork'; ## no critic (ClassHierarchies::ProhibitExplicitISA)
    }

    return;
}


sub doConfig {
    my ($self, $isDebugging, $isVerbose, $dbconf, $config) = @_;

    $self->{isDebugging} = $isDebugging;
    $self->{isVerbose} = $isVerbose;
    $self->{dbconf} = $dbconf;
    $self->{config} = $config;

    if($isDebugging) {
        $self->child_init_hook();
    }

    # Preload the forcenx list (needs service restart to update)
    print "Preloading ForceNX list...\n";
    my @forcenx;
    my @forcenxraw;
    my @forcenxstringmatch;
    my $dbh = DBI->connect($dbconf->{dburl}, $dbconf->{dbuser}, $dbconf->{dbpassword}, {AutoCommit => 0, RaiseError => 0})
            or croak("Can't connect to database: $ERRNO");

    my $forcenxsth = $dbh->prepare_cached("SELECT * FROM nameserver_forcenxdomain")
            or croak($dbh->errstr);

    if(!$forcenxsth->execute()) {
        print STDERR $dbh->errstr, "\n";
        $dbh->rollback;
    } else {
        while((my $line = $forcenxsth->fetchrow_hashref)) {
            if($line->{is_regex}) {
                push @forcenxraw, $line->{domain_match};
            } else {
                push @forcenxstringmatch, $line->{domain_match};
            }
        }
        $forcenxsth->finish;
        $dbh->commit;
    }

    print "Precompiling ForceNX regex list...\n";
    foreach my $rex (@forcenxraw) {
        push @forcenx, qr/$rex/;
    }

    $self->{forcenxraw} = \@forcenxraw;
    $self->{forcenx} = \@forcenx;
    $self->{forcenxstringmatch} = \@forcenxstringmatch;
    $dbh->disconnect;
    print STDERR "Done preloading...\n";
    return;
}

sub child_init_hook {
    my ($self) = @_;

    if(!defined($self->{config}->{remotelookup})) {
        $self->{config}->{remotelookup} = 0;
    }

    if(!defined($self->{config}->{usegoogle})) {
        $self->{config}->{usegoogle} = 0;
    }


    # Re-init randomness after fork()
    srand();

    my $clacksconf = $self->{config}->{clacks};
    my $clacks;
    if(defined($clacksconf->{socket}) && $clacksconf->{socket} ne '') {
        $clacks = Net::Clacks::Client->newSocket($clacksconf->{socket},
                                           $clacksconf->{user},
                                           $clacksconf->{password},
                                           'DNS_Server',
                                           0 # no caching
        );
    } else {
        $clacks = Net::Clacks::Client->new($clacksconf->{host},
                                           $clacksconf->{port},
                                           $clacksconf->{user},
                                           $clacksconf->{password},
                                           'DNS_Server',
                                           0 # no caching
        );
    }
    $clacks->disablePing();
    $clacks->doNetwork();
    $self->{clacks} = $clacks;

    my $childpid = $PID;
    while(length($childpid < 5)) {
        $childpid = ' ' . $childpid;
    }
    $self->{debuglogpid} = $childpid;

    $self->debuglog("******************** CHILD START *********************");

    my $dbconf = $self->{dbconf};
    $self->{dbh} = DBI->connect($dbconf->{dburl}, $dbconf->{dbuser}, $dbconf->{dbpassword}, {AutoCommit => 0, RaiseError => 0})
            or croak("Can't connect to database: $ERRNO");
    my $dbh = $self->{dbh};

    $dbh->do("SET SESSION CHARACTERISTICS AS TRANSACTION ISOLATION LEVEL READ COMMITTED");
    $dbh->commit;

    $self->{nameselsth} = $dbh->prepare_cached('SELECT * FROM nameserver_domain_entry
                                      WHERE host_fqdn = ?
                                      AND record_type = ?
                                      ORDER BY record_type, mxpriority')
            or croak($dbh->errstr);

    $self->{spfselsth} = $dbh->prepare_cached("SELECT * FROM nameserver_domain_entry
                                      WHERE host_fqdn = ?
                                      AND record_type = 'TXT'
                                      AND textrecord LIKE 'v=spf%'
                                      ORDER BY record_type, mxpriority")
            or croak($dbh->errstr);

    $self->{domainselsth} = $dbh->prepare_cached("SELECT * FROM nameserver_domain_entry
                                      WHERE host_fqdn = ?
                                      AND record_type IN ('NS','MX','A', 'AAAA', 'TXT', 'CNAME', 'SOA', 'LOC', 'SSHFP')
                                      ORDER BY decode_nameserver_record_type(record_type), record_type, mxpriority")
            or croak($dbh->errstr);

    $self->{axfrselsth} = $dbh->prepare_cached("SELECT * FROM nameserver_domain_entry
                                      WHERE domain_fqdn = ?
                                      AND record_type IN ('NS','MX','A', 'AAAA', 'TXT', 'CNAME', 'SOA', 'LOC', 'SSHFP')
                                      ORDER BY decode_nameserver_record_type(record_type), record_type, mxpriority")
            or croak($dbh->errstr);

    $self->{domainexistssth} = $dbh->prepare_cached("SELECT true FROM nameserver_domain_entry
                                      WHERE host_fqdn = ?
                                      OR domain_fqdn = ?
                                      LIMIT 1")
            or croak($dbh->errstr);

    $self->{soaserialsth} = $dbh->prepare_cached("SELECT soa_serial FROM nameserver_domain
                                                WHERE domain_fqdn = ?")
            or croak($dbh->errstr);

    $self->{soadatasth} = $dbh->prepare_cached("SELECT * FROM nameserver_domain
                                          WHERE domain_fqdn = ?")
            or croak($dbh->errstr);

    $self->{soaselsth} = $dbh->prepare_cached("SELECT * FROM nameserver_domain_entry ent
                                        WHERE record_type = 'SOA'
                                        AND domain_fqdn IN (
                                            SELECT domain_fqdn FROM nameserver_domain_entry
                                            WHERE host_fqdn = ?
                                        )")
            or croak($dbh->errstr);

    $self->{caaselsth} = $dbh->prepare_cached("SELECT * FROM nameserver_domain_entry ent
                                        WHERE record_type = 'CAA'
                                        AND domain_fqdn IN (
                                            SELECT domain_fqdn FROM nameserver_domain_entry
                                            WHERE host_fqdn = ?
                                        )
                                        ORDER BY mxpriority")
            or croak($dbh->errstr);

    $self->{computersth} = $dbh->prepare_cached('SELECT * FROM computers WHERE computer_name = ?')
            or croak($dbh->errstr);



    # Block faked IP DDOS
    $self->{ipfloodinssth} = $dbh->prepare_cached("INSERT INTO nameserver_floodcontrol_ip (external_sender) VALUES (?)")
            or croak($dbh->errstr);

    $self->{ipblockchecksth} = $dbh->prepare_cached("SELECT true AS isblocked
                                             FROM nameserver_blocklist_ip
                                             WHERE external_sender = ?
                                             LIMIT 1")
            or croak($dbh->errstr);


    # Block DDOS to Nameserver
    $self->{hostfloodinssth} = $dbh->prepare_cached("INSERT INTO nameserver_floodcontrol_hostname (domain_fqdn) VALUES (?)")
            or croak($dbh->errstr);

    $self->{hostblockchecksth} = $dbh->prepare_cached("SELECT true AS isblocked
                                             FROM nameserver_blocklist_hostname
                                             WHERE domain_fqdn = ?
                                             LIMIT 1")
            or croak($dbh->errstr);




    $self->{loginssth} = $dbh->prepare_cached("INSERT INTO nameserver_log (host_fqdn, record_type, external_sender, result, proto, remotelookup, extrainfo)
                                               VALUES (?, ?, ?, ?, ?, ?, ?)")
            or croak($dbh->errstr);

    $self->{ptrsth} = $dbh->prepare_cached("SELECT * FROM nameserver_reverselookup WHERE ip_address = ?")
            or croak($dbh->errstr);

    if($self->{config}->{remotelookup}) {
            $self->{checkdomainsth} = $dbh->prepare_cached("SELECT 1 FROM nameserver_domain WHERE domain_fqdn like ?")
                    or croak($dbh->errstr);
    }

    $self->{cacheinssth} = $dbh->prepare_cached("INSERT INTO nameserver_extern_cache (qname, qtype, packetdata, lookuperror, validuntil)
                                                    VALUES(?, ?, ?, ?, now() + ?::interval)")
                                                #VALUES(?, ?, ?, ?, now() + interval '" . $self->{config}->{extern_cachetime} ."')")
            or croak($dbh->errstr);

    $self->{cacheselsth} = $dbh->prepare_cached("SELECT packetdata, lookuperror FROM nameserver_extern_cache
                                                    WHERE qname = ?
                                                    AND qtype = ?
                                                    ORDER BY validuntil DESC
                                                    LIMIT 1")
            or croak($dbh->errstr);

    $self->{axfrmaster} = $dbh->prepare_cached("SELECT is_axfr_master, axfr_slave from nameserver_domain
                                                    WHERE domain_fqdn = ?
                                                    LIMIT 1")
            or croak($dbh->errstr);


    return;
}

sub child_finish_hook {
    my ($self) = @_;

    $self->debuglog("******************** CHILD STOP *********************");
    delete $self->{clacks};
    if(defined($self->{dbh})) {
        $self->{dbh}->disconnect;
        delete $self->{dbh};
    }

    return;
}

sub isownip {
    my ($self, $ip) = @_;

    $ip =~ s/\/.*//;

    foreach my $ownip (@{$self->{config}->{server}->{bind_adresses}->{item}}) {
        $ownip =~ s/\[//;
        $ownip =~ s/\]//;
        if($ip eq $ownip) {
            return 1;
        }
    }

    return 0;
}

sub debuglog {
    my ($self, @loglineparts) = @_;
    my $logline;
    if(defined($self->{debuglogpid})) {
        $logline = getISODate() . ' ' .  $self->{debuglogpid} . ' ' . join('', @loglineparts);
    } else {
        $logline = getISODate() . ' ? ' .  join('', @loglineparts);
    }

    print STDERR $logline, "\n";

    if(!defined($self->{clacks})) {
        return;
    }

    $self->{clacks}->doNetwork();
    while((my $message = $self->{clacks}->getNext())) {
        if($message->{type} eq 'disconnect') {
            # Nothing to do
        }
    }
    $self->{clacks}->set('Debuglog::DNS::new', $logline);
    $self->{clacks}->doNetwork();

    return;
}

sub countRequest {
    my ($self) = @_;

    if(!defined($self->{clacks})) {
        return;
    }

    $self->{clacks}->increment('WebStats::dns_request_count');
    $self->{clacks}->doNetwork();
    return;
}
    

sub process_request {
    my ($self, $realsocket) = @_;

    if(!defined($self->{dbh})) {
        $self->child_init_hook;
    }

    my $prop = $self->{'server'};
    my $peerhost = $prop->{peeraddr};

    if($peerhost =~ /^\:\:ffff\:(\d+\.\d+\.\d+\.\d+)/) {
        $peerhost = $1;
    }

    if($prop->{udp_true}) {
        return $self->handleUDP($peerhost);
    } else {
        $self->debuglog("TCP connection from $peerhost");
        return $self->handleTCP($peerhost, $realsocket);
    }
}

sub handleUDP {
    my ($self, $peerhost) = @_;

    my $prop = $self->{'server'};

    my $indata = $prop->{udp_data};
    my $inpacket = Net::DNS::Packet->new(\$indata, 0);
    my ($question) = $inpacket->question;

    # Count request
    $self->countRequest();

    # mark the answer as authoritive (by setting the 'aa' flag
    my $extra = { aa => $self->{config}->{authoritive} };

    my $reply = $inpacket->reply();
    my $header = $reply->header;

    my $opcode  = $inpacket->header->opcode;
	my $qdcount = $inpacket->header->qdcount;

    my ($validreply, $rcode, $ans, $auth, $add, $remotelookup);

    if(!$qdcount) {
        $header->rcode("NOERROR");
    } elsif($qdcount > 1) {
        # Multiple questions(?) currently unsupported
        $header->rcode("FORMERR");
    } else {
        my $qname = lc $question->qname;
        my $qtype = uc $question->qtype;
        my $qclass = $question->qclass;

        #$self->debuglog("UDP request for $qname / $qtype");

        if($opcode eq 'QUERY') {
            ($validreply, $rcode, $ans, $auth, $add, $remotelookup) = $self->compile_reply($qname, $qclass, $qtype, $peerhost, 'UDP');
            if(!defined($validreply) || !$validreply) {
                # Client blocked or something else went wrong. Close the connection without answer
                return;
            }
        } elsif($opcode eq 'NOTIFY') {
            # Not implemented
            $rcode = 'NOTIMP';
        } else {
            # Unsupported opcode
            $rcode = 'FORMERR';
        }
        $header->rcode($rcode);
        $reply->{answer} = [@{$ans}] if $ans;
        $reply->{authority} = [@{$auth}] if $auth;
        $reply->{additional} = [@{$add}] if $add;

    }

    # "Recursion available"
    $header->ra($self->{config}->{remotelookup});

    # Only "authoritive" if it's from our own database
    $header->aa(1) if($self->{config}->{authoritive} && !$remotelookup);

    my $max_len = $inpacket->edns->size;
    if(!defined($max_len)) {
        $max_len = 512;
        $self->debuglog("Undefined max UDP length, setting to $max_len just in case");
    }
    my $outdata = $reply->data();
    if(length($outdata) > $max_len) {
        $self->debuglog("Truncating UDP response to allowed limit $max_len from " . length($outdata));
        $outdata = $reply->data($max_len);
    }

    #$self->debuglog("Max len: $max_len, packet len: ", length($outdata));

    $prop->{client}->send($outdata);

    return;
}

sub handleTCP {
    my ($self, $peerhost, $realsocket) = @_;


    binmode($realsocket);
    $realsocket->blocking(0);

    while(1) {
        my $idletimeout = time + $self->{config}->{tcpidletimeout};
        my $lenprefix = '';
        while(length($lenprefix) < 2) {
            if(time > $idletimeout) {
                $self->debuglog("TCP Idle timeout during length header read.");
                return;
            }

            my $buffer;
            my $status = sysread($realsocket, $buffer, 2 - length($lenprefix));
            if(!$realsocket->connected || !$realsocket->opened || $realsocket->error || ($ERRNO ne '' && !$ERRNO{EWOULDBLOCK})) {
                $self->debuglog("TCP connection closed by client during header read.");
                return;
            }

            if(!defined($buffer) || !length($buffer)) {
                sleep(0.01);
                next;
            }
            $lenprefix .= $buffer;
        }

        my $packetlength = unpack('n', $lenprefix);
        $self->debuglog("Incoming packet length: $packetlength");
        if($packetlength < 2 || $packetlength > 30_000) {
            $self->debuglog("Packet size out of bounds 2 < size > 30000");
            return;
        }

        my $indata = '';
        while(length($indata) < $packetlength) {
            if(time > $idletimeout) {
                $self->debuglog("TCP Idle timeout during packet read.");
                return;
            }

            my $buffer;
            my $status = sysread($realsocket, $buffer, $packetlength - length($indata));
            if(!$realsocket->connected || !$realsocket->opened || $realsocket->error || ($ERRNO ne '' && !$ERRNO{EWOULDBLOCK})) {
                $self->debuglog("TCP connection closed by client during packet read.");
                return;
            }
            if(!defined($buffer) || !length($buffer)) {
                sleep(0.01);
                next;
            }
            $indata .= $buffer;
        }


        my $inpacket = Net::DNS::Packet->new(\$indata, 0);
        my ($question) = $inpacket->question;

        # Count request
        $self->countRequest();

        # mark the answer as authoritive (by setting the 'aa' flag
        my $extra = { aa => $self->{config}->{authoritive} };

        my $reply = $inpacket->reply();
        my $header = $reply->header;

        my $opcode  = $inpacket->header->opcode;
        my $qdcount = $inpacket->header->qdcount;

        my ($validreply, $rcode, $ans, $auth, $add, $remotelookup);

        if(!$qdcount) {
            $header->rcode("NOERROR");
        } elsif($qdcount > 1) {
            # Multiple questions(?) currently unsupported
            $header->rcode("FORMERR");
        } else {
            my $qname = lc $question->qname;
            my $qtype = uc $question->qtype;
            my $qclass = $question->qclass;

            if($opcode eq 'QUERY') {
                ($validreply, $rcode, $ans, $auth, $add, $remotelookup) = $self->compile_reply($qname, $qclass, $qtype, $peerhost, 'TCP');
                if(!defined($validreply) || !$validreply) {
                    # Client blocked or something else went wrong. Close the connection without answer
                    return;
                }
            } elsif($opcode eq 'NOTIFY') {
                # Not implemented
                $rcode = 'NOTIMP';
            } else {
                # Unsupported opcode
                $rcode = 'FORMERR';
            }
            $header->rcode($rcode);


            $reply->{answer} = [@{$ans}] if $ans;
            $reply->{authority} = [@{$auth}] if $auth;
            $reply->{additional} = [@{$add}] if $add;

        }

        # "Recursion available"
        $header->ra($self->{config}->{remotelookup});

        # Only "authoritive" if it's from our own database
        $header->aa(1) if($self->{config}->{authoritive} && !$remotelookup);

        my $outdata = $reply->data();
        my $outlenheader = pack('n', length($outdata));

        if(!webPrint($realsocket, $outlenheader, $outdata)) {
            if($self->{isVerbose}) {
                print STDERR "webPrint failed, closing connection!\n";
            }
            return;
        }

        # Loop/keep-alive
    }
    return;
}

sub compile_reply { ## no critic (Subroutines::ProhibitExcessComplexity)
    my ($self, $qname, $qclass, $qtype, $peerhost, $proto) = @_;
    my ($rcode, @ans, @auth, @add);
    my $extrainfo = '';

    my $dbh = $self->{dbh};

    my $remotelookup = 0;
    if($peerhost ne $RECURSIVELOOKUP) {
        $self->debuglog("Requested: $qtype OF $qname by $peerhost");
    }

    # IP floodcheck (DNS DDOS to IP target), don't check for recursive lookups and whenever the client is localhost
    if($peerhost ne $RECURSIVELOOKUP && !$self->isownip($peerhost)) {
        # localhost doesn't have limitations
        if(!$self->{ipfloodinssth}->execute($peerhost)) {
            $self->debuglog("Can't log $qname from $peerhost");
            #$dbh->rollback;
            return;
        } else {
            $dbh->commit;
        }

        if(!$self->{ipblockchecksth}->execute($peerhost)) {
            $self->debuglog("Can't execute ip block checks");
            $dbh->rollback;
        } else {
            my ($isblocked) = $self->{ipblockchecksth}->fetchrow_array;
            $self->{ipblockchecksth}->finish;
            $dbh->commit;
            if(defined($isblocked) && $isblocked) {
                $self->debuglog("Blocking request from $peerhost (IP)BLOCK");
                return;
            }
        }
    }

    # Hostname floodcheck (DNS DDOS to DNS Server), don't check for recursive lookups and whenever the client is localhost
    if($peerhost ne $RECURSIVELOOKUP && !$self->isownip($peerhost)) {
        if(!$self->{hostfloodinssth}->execute($qname)) {
            $self->debuglog("Can't log $qname from $peerhost");
            $dbh->rollback;
            #return;
        } else {
            $dbh->commit;
        }

        if(!$self->{hostblockchecksth}->execute($qname)) {
            $self->debuglog("Can't execute hostname block checks");
            $dbh->rollback;
        } else {
            my ($isblocked) = $self->{hostblockchecksth}->fetchrow_array;
            $self->{hostblockchecksth}->finish;
            $dbh->commit;
            if(defined($isblocked) && $isblocked > 0) {
                $self->debuglog("Blocking request from $peerhost (HOSTBLOCK)");
                return;
            }
        }
    }

    # Hostname MUST have a dot
    if($qname !~ /\./) {
        $rcode = 'INVALID';
        goto dnsreply;
    }


    my @implemented = qw[ANY A TXT MX CNAME NS SOA SPF SRV AAAA CAA AXFR PTR LOC SSHFP];

    if(!(contains($qtype, \@implemented))) {
        $rcode = 'NOTIMP';
        goto dnsreply;
    }

    if($qtype eq 'AXFR') {
        if($proto ne 'TCP') {
            # Zone transfer only allowed on TCP
            $rcode = 'REFUSED';
            goto dnsreply;
        }

        # Check if out peer is in the "allowed" list
        $self->{axfrmaster}->execute($qname) or croak($dbh->errstr);
        my $allowed = 0;
        while((my $line = $self->{axfrmaster}->fetchrow_hashref)) {
            next unless($line->{is_axfr_master});

            $line->{axfr_slave} =~ s/\ //g;
            next if($line->{axfr_slave} eq '');
            my @slaveips = split/\,/, $line->{axfr_slave};
            if(contains($peerhost, \@slaveips)) {
                $self->debuglog("AXFR Peer Allowed!");
                $allowed = 1;
                last;
            }
        }
        $self->{axfrmaster}->finish;
        if(!$allowed) {
            $self->debuglog("AXFR Peer REFUSED!");
            $rcode = 'REFUSED';
            goto dnsreply;
        }
    }

    if($qtype eq 'PTR') {
        my $isv6 = 0;
        my $reverseip = '';
        if($qname =~ /^(.*)\.in\-addr\.arpa$/) {
            $reverseip = $1;
        } elsif($qname =~ /^(.*)\.ip6\.arpa$/) {
            $reverseip = $1;
            $isv6 = 1;
        } else {
            # Not a valid IP->Hostname query
            $rcode = 'NXDOMAIN';
            goto dnsreply;
        }

        my @parts = reverse split/\./, $reverseip;
        my $realip;
        if(!$isv6) {
            $realip = join('.', @parts);
            $realip =~ s/\-.*//g;
        } else {
            my $temp = join('', @parts);
            @parts = ();
            push @parts, substr($temp, 0, 4, "") while(length($temp));
            $realip = join(':', @parts);
        }

        if(!$self->{ptrsth}->execute($realip)) {
            $dbh->rollback;
            $rcode = 'SERVFAIL';
            goto dnsreply;
        }
        my $ptrdata = $self->{ptrsth}->fetchrow_hashref;
        $self->{ptrsth}->finish;
        if(!defined($ptrdata)) {
            $rcode = 'NXDOMAIN';
            goto dnsreply;
        }

        my $rr = Net::DNS::RR->new("$qname " . $ptrdata->{ttl_time} . " $qclass PTR " . $ptrdata->{hostname});
        push @ans, $rr;
        $rcode = 'NOERROR';
        goto dnsreply;
    }


    $rcode = 'NXDOMAIN';
    my @lines;
    if($qtype eq 'ANY') {
        $self->{domainselsth}->execute($qname) or croak($dbh->errstr);
        while((my $line = $self->{domainselsth}->fetchrow_hashref)) {
            push @lines, $line;
        }
        $self->{domainselsth}->finish;
    } elsif($qtype eq 'AXFR') {
        $self->{axfrselsth}->execute($qname) or croak($dbh->errstr);
        while((my $line = $self->{axfrselsth}->fetchrow_hashref)) {
            push @lines, $line;
        }
        $self->{axfrselsth}->finish;

        # For some strange reason, we need to push the first record (SOA) again as the last record. This seems
        # to somehow signify the end of the AXFR zone transfer....?!?!?!?
        push @lines, $lines[0];

        open(my $ofh, '>', '/home/cavac/temp/axfr.txt') or croak($ERRNO);
        print $ofh Dumper(\@lines);
        close $ofh;
    } elsif($qtype eq 'SOA') {
        # Need to find the SOA entry for the DOMAIN not the host
        $self->{soaselsth}->execute($qname) or croak($dbh->errstr);
        while((my $line = $self->{soaselsth}->fetchrow_hashref)) {
            push @lines, $line;
        }
        $self->{soaselsth}->finish;
    } elsif($qtype eq 'SPF') {
        # SPF record type is not a standard anymore, RFC recommends to use the
        # TXT record type... which we do. But some old servers still request the
        # SPF record, so we look up the TXT record and fake an SPF record
        $self->{spfselsth}->execute($qname) or croak($dbh->errstr);
        while((my $line = $self->{spfselsth}->fetchrow_hashref)) {
            $line->{record_type} = 'SPF';
            push @lines, $line;
        }
        $self->{spfselsth}->finish;
    } elsif($qtype eq 'CAA') {
        # Certificate Authority Authorization
        $self->{caaselsth}->execute($qname) or croak($dbh->errstr);
        while((my $line = $self->{caaselsth}->fetchrow_hashref)) {
            push @lines, $line;
        }
        $self->{caaselsth}->finish;
    } else {
        my @types = ($qtype);
        if($qtype eq 'A' || $qtype eq 'AAAA') {
            push @types, 'CNAME';
        }
        foreach my $type (@types) {
            $self->{nameselsth}->execute($qname, $type) or croak($dbh->errstr);
            while((my $line = $self->{nameselsth}->fetchrow_hashref)) {
                push @lines, $line;
            }
            $self->{nameselsth}->finish;
        }
    }

    foreach my $line (@lines) {
        $rcode = 'NOERROR';
        my $destination;
        my $computer;
        #my $rname = $line->{host_fqdn};

        if(defined($line->{computer_name})) {
            $self->{computersth}->execute($line->{computer_name}) or croak($dbh->errstr);
            $computer = $self->{computersth}->fetchrow_hashref;
            $self->{computersth}->finish;
        }

        if($line->{record_type} eq 'SOA') {
            my $domname = $line->{domain_fqdn};
            $self->{soaserialsth}->execute($domname) or croak($dbh->errstr);
            my ($soaserial) = $self->{soaserialsth}->fetchrow_array;
            $self->{soaserialsth}->finish;
            $self->{soadatasth}->execute($domname) or croak($dbh->errstr);
            my $domaintimes = $self->{soadatasth}->fetchrow_hashref;
            $self->{soadatasth}->finish;
            my $ldestination = join(' ',
                                   $domaintimes->{primary_nameserver},
                                   $domaintimes->{soa_admin},
                                   $soaserial,
                                   $domaintimes->{refresh_time},
                                   $domaintimes->{retry_time},
                                   $domaintimes->{expire_time},
                                   $domaintimes->{ttl_time},

            );
            my $rr = Net::DNS::RR->new($line->{host_fqdn} . ' ' . $line->{ttl_time} . " $qclass SOA " . $ldestination);
            push @ans, $rr;

        } elsif($line->{record_type} eq 'A') {
            my $usetxtfallback = 1;
            if(defined($computer) && defined($self->{config}->{columnprefix})) {
                foreach my $cprefix (@{$self->{config}->{columnprefix}}) {
                    my $colname = $cprefix . '_ipv4';
                    $destination = $computer->{$colname} || '';
                    next if($destination eq '');
                    $destination = fixDestination($line->{domain_fqdn}, $destination);
                    my $rr = Net::DNS::RR->new($line->{host_fqdn} . ' ' . $line->{ttl_time} . " $qclass A " . $destination);
                    push @ans, $rr;
                    $usetxtfallback = 0;
                }
            }

            if($usetxtfallback && $line->{textrecord} ne '') {
                $destination = fixDestination($line->{domain_fqdn}, $line->{textrecord});
                my $rr = Net::DNS::RR->new($line->{host_fqdn} . ' ' . $line->{ttl_time} . " $qclass A " . $destination);
                push @ans, $rr;
            }
        } elsif($line->{record_type} eq 'AAAA') {
            my $usetxtfallback = 1;
            if(defined($computer) && defined($self->{config}->{columnprefix})) {
                foreach my $cprefix (@{$self->{config}->{columnprefix}}) {
                    my $colname = $cprefix . '_ipv6';
                    $destination = $computer->{$colname} || '';
                    next if($destination eq '');
                    $destination = fixDestination($line->{domain_fqdn}, $destination);
                    my $rr = Net::DNS::RR->new($line->{host_fqdn} . ' ' . $line->{ttl_time} . " $qclass AAAA " . $destination);
                    push @ans, $rr;
                    $usetxtfallback = 0;
                }
            }
            if($usetxtfallback && $line->{textrecord} ne '') {
                $destination = fixDestination($line->{domain_fqdn}, $line->{textrecord});
                my $rr = Net::DNS::RR->new($line->{host_fqdn} . ' ' . $line->{ttl_time} . " $qclass AAAA " . $destination);
                push @ans, $rr;
            }
        } elsif($line->{record_type} eq 'SRV') {
            if($line->{textrecord} eq '') {
                $self->debuglog("Error resolving record $qtype for $qname at entry_id ", $line->{entry_id});
                next;
            }

            my ($desthost, $destport);
            if($line->{textrecord} =~ /^(.*)\:(\d+)/) {
                ($desthost, $destport) = ($1, $2);
            } else {
                $self->debuglog("Error parsing record $qtype for $qname at entry_id ", $line->{entry_id});
                next;
            }

            $destination = $line->{mxpriority} . ' 1 ' . $destport . ' ' . $desthost;

            my $rr = Net::DNS::RR->new($line->{host_fqdn} . ' ' . $line->{ttl_time} . " $qclass SRV " . $destination);
            push @ans, $rr;
        } elsif($line->{record_type} eq 'SPF') {
            if($line->{textrecord} eq '') {
                $self->debuglog("Error resolving record $qtype for $qname at entry_id ", $line->{entry_id});
                next;
            }

            $destination = '"' . $line->{textrecord} . '"';

            my $rr = Net::DNS::RR->new($line->{host_fqdn} . ' ' . $line->{ttl_time} . " $qclass SPF " . $destination);
            push @ans, $rr;
        } elsif($line->{record_type} eq 'CAA') {
            if($line->{textrecord} eq '') {
                $self->debuglog("Error resolving record $qtype for $qname at entry_id ", $line->{entry_id});
                next;
            }
            my ($caaflags, $caatype, $caatext) = split/\ /, $line->{textrecord}, 3;

            my $rr = Net::DNS::RR->new($line->{host_fqdn} . ' ' . $line->{ttl_time} . " $qclass CAA $caaflags $caatype $caatext");
            push @ans, $rr;
        } elsif($line->{record_type} eq 'TXT') {
            if($line->{textrecord} eq '') {
                $self->debuglog("Error resolving record $qtype for $qname at entry_id ", $line->{entry_id});
                next;
            }

            $destination = '"' . $line->{textrecord} . '"';

            my %replacements = (
                PEERHOST    => $peerhost,
                SERVERTIME  => getISODate(),
            );

            foreach my $rkey (keys %replacements) {
                my $rval = $replacements{$rkey};
                $destination =~ s/$rkey/$rval/g;
            }

            my $rr = Net::DNS::RR->new($line->{host_fqdn} . ' ' . $line->{ttl_time} . " $qclass TXT " . $destination);
            push @ans, $rr;
        } elsif($line->{record_type} eq 'CNAME') {
            if(defined($line->{computer_name})) {
                $destination = $line->{computer_name};
            } elsif($line->{textrecord} ne '') {
                $destination = $line->{textrecord};
            } else {
                $self->debuglog("Error resolving record $qtype for $qname at entry_id ", $line->{entry_id});
                next;
            }

            $destination = fixDestination($line->{domain_fqdn}, $destination);
            my $rr = Net::DNS::RR->new($line->{host_fqdn} . ' ' . $line->{ttl_time} . " $qclass CNAME " . $destination);
            push @ans, $rr;

            # Now we have to recursively lookup the "glue" records, e.g. A and AAAA records for the names we just
            # found and put them into the ["additional"] actually the ANSWER section
            #return ($rcode, \@ans, \@auth, \@add, { aa => $config->{authoritive} });
            foreach my $gluetype (qw[A AAAA]) {
                next if($gluetype eq 'A' && $qtype eq 'AAAA');
                next if($gluetype eq 'AAAA' && $qtype eq 'A');
                my ($validreply, $glue_rcode, $glue_ans, undef, undef, undef, undef) = $self->compile_reply($destination, $qclass, $gluetype, $RECURSIVELOOKUP, $proto);
                if(!defined($validreply) || !$validreply) {
                    # Client blocked or something else went wrong. Close the connection without answer
                    return;
                }
                if(@{$glue_ans} && $self->{isVerbose}) {
                    $self->debuglog("  Found $gluetype glue record for $destination");
                }
                if($qtype ne 'AXFR') {
                    push @ans, @{$glue_ans};
                } else {
                    push @add, @{$glue_ans};
                }
            }
        } elsif($line->{record_type} eq 'LOC') {
            $destination = $line->{textrecord};
            my $rr = Net::DNS::RR->new($line->{host_fqdn} . ' ' . $line->{ttl_time} . " $qclass LOC " . $destination);
            push @ans, $rr;
        } elsif($line->{record_type} eq 'SSHFP') {
            $destination = $line->{textrecord};
            my $rr = Net::DNS::RR->new($line->{host_fqdn} . ' ' . $line->{ttl_time} . " $qclass SSHFP " . $destination);
            push @ans, $rr;
        } elsif($line->{record_type} eq 'MX') {
            if(defined($line->{computer_name})) {
                $destination = $line->{computer_name};
            } elsif($line->{textrecord} ne '') {
                $destination = $line->{textrecord};
            } else {
                $self->debuglog("Error resolving record $qtype for $qname at entry_id ", $line->{entry_id});
                next;
            }

            $destination = fixDestination($line->{domain_fqdn}, $destination);
            my $rr = Net::DNS::RR->new($line->{host_fqdn} . ' ' . $line->{ttl_time} . " $qclass MX " . $line->{mxpriority} . ' ' . $destination);
            push @ans, $rr;

            # Now we have to recursively lookup the "glue" records, e.g. A and AAAA records for the names we just
            # found and put them into the ["additional"] actually the ANSWER section
            #return ($rcode, \@ans, \@auth, \@add, { aa => $config->{authoritive} });
            foreach my $gluetype (qw[A AAAA]) {
                next if($gluetype eq 'A' && $qtype eq 'AAAA');
                next if($gluetype eq 'AAAA' && $qtype eq 'A');
                my ($validreply, $glue_rcode, $glue_ans, undef, undef, undef, undef) = $self->compile_reply($destination, $qclass, $gluetype, $RECURSIVELOOKUP, $proto);
                if(!defined($validreply) || !$validreply) {
                    # Client blocked or something else went wrong. Close the connection without answer
                    return;
                }
                if(@{$glue_ans} && $self->{isVerbose}) {
                    $self->debuglog("  Found $gluetype glue record for $destination");
                }
                if($qtype ne 'AXFR') {
                    push @ans, @{$glue_ans};
                } else {
                    push @add, @{$glue_ans};
                }
            }
        } elsif($line->{record_type} eq 'NS') {
            if(defined($line->{computer_name})) {
                $destination = $line->{computer_name};
            } elsif($line->{textrecord} ne '') {
                $destination = $line->{textrecord};
            } else {
                $self->debuglog("Error resolving record $qtype for $qname at entry_id ", $line->{entry_id});
                next;
            }

            $destination = fixDestination($line->{domain_fqdn}, $destination);
            my $rr = Net::DNS::RR->new($line->{host_fqdn} . ' ' . $line->{ttl_time} . " $qclass NS " . $destination);
            push @ans, $rr;

            # Now we have to recursively lookup the "glue" records, e.g. A and AAAA records for the names we just
            # found and put them into the ["additional"] actually the ANSWER section
            #return ($rcode, \@ans, \@auth, \@add, { aa => $config->{authoritive} });
            foreach my $gluetype (qw[A AAAA]) {
                next if($gluetype eq 'A' && $qtype eq 'AAAA');
                next if($gluetype eq 'AAAA' && $qtype eq 'A');
                my ($validreply, $glue_rcode, $glue_ans, undef, undef, undef, undef) = $self->compile_reply($destination, $qclass, $gluetype, $RECURSIVELOOKUP, $proto);
                if(!defined($validreply) || !$validreply) {
                    # Client blocked or something else went wrong. Close the connection without answer
                    return;
                }
                if(@{$glue_ans} && $self->{isVerbose}) {
                    $self->debuglog("  Found $gluetype glue record for $destination");
                }
                if($qtype ne 'AXFR') {
                    push @ans, @{$glue_ans};
                } else {
                    push @ans, @{$glue_ans};
                }
            }
        }
    }
    $dbh->rollback;

    dnsreply:

    # We may not have found the entry we where looking for, but the host itself
    # might still exist. In this case, we *MUST* return NOERROR instead of NXDOMAIN!
    if($rcode eq 'NXDOMAIN') {
        my $hostexists = 0;
        if(!$self->{domainexistssth}->execute($qname, $qname)) {
            $dbh->rollback;
        } else {
            ($hostexists) = $self->{domainexistssth}->fetchrow_array;
            $self->{domainexistssth}->finish;
            $dbh->commit;
        }
        if($hostexists) {
            $rcode = 'NOERROR';
        }
    }

    if($rcode eq 'NXDOMAIN' && $self->{config}->{remotelookup}) {
        if($self->{isVerbose}) {
            $self->debuglog("Checking for remote lookup...");
        }
        # Check if this is one of our own domains after all
        my $lookupname = '' . $qname;
        my $owndomain = 0;
        while($lookupname =~ /\./ && !$owndomain) {
            if($self->{isVerbose}) {
                $self->debuglog(" testing $lookupname");
            }
            if(!$self->{checkdomainsth}->execute($lookupname)) {
                $self->debuglog("   ", $dbh->errstr);
                $dbh->rollback;
                return;
            }
            if((my $line = $self->{checkdomainsth}->fetchrow_hashref)) {
                $owndomain = 1;
            }
            $self->{checkdomainsth}->finish;

            $lookupname =~ s/^.*?\.//;
        }
        $dbh->commit;


        if(!$owndomain) {

            # Handle ForceNX string matches
            foreach my $matcher (@{$self->{forcenxstringmatch}}) {
                if($qname eq $matcher) {
                    $self->debuglog("Blocked by string match ForceNX rule");
                    $extrainfo = "ForceNX stringmatch";
                    $rcode = "FORCENX";
                    last;
                }
            }

            # Handle ForceNX (forbidden) regex matched domains
            if($rcode ne 'FORCENX') {
                my $offs = -1;
                foreach my $matcher (@{$self->{forcenx}}) {
                    $offs++;
                    if($qname =~ $matcher) {
                        my $rawmatcher = $self->{forcenxraw}->[$offs];
                        $self->debuglog("Blocked by ForceNX rule $rawmatcher");
                        $extrainfo = $rawmatcher;
                        $rcode = 'FORCENX';
                        last;
                    }
                }
            }

            if($rcode ne 'FORCENX') {
                $remotelookup = 1;
                my ($reply, $error) = $self->resolve_extern($qname, $qtype);

                my @fasterrors = qw[NOERROR SERVFAIL NOTIMP REFUSED NOTZONE];
                if(!defined($reply) && defined($error)) {
                    # Host exists but has no data for this qtype
                    $extrainfo = 'RCODE_' . $error;
                    $rcode = $error;
                } elsif(defined($reply) && defined($reply->header)) {

                    $rcode = $reply->header->rcode;
                    @auth = $reply->authority;

                    # Filter ANSWER section
                    my $filtercount = 0;
                    my %filtered;
                    foreach my $record ($reply->answer) {
                        next if($record->type eq 'OPT'); # Don't need this pseudo-type
                        if(!(contains($record->type, \@implemented))) {
                            $filtercount++;
                            $filtered{$record->type} = 1;
                            next;
                        }
                        push @ans, $record;
                    }
                    
                    # Filter ADDITIONAL section
                    foreach my $record ($reply->additional) {
                        next if($record->type eq 'OPT'); # Don't need this pseudo-type
                        if(!(contains($record->type, \@implemented))) {
                            $filtercount++;
                            $filtered{$record->type} = 1;
                            next;
                        }
                        push @add, $record;
                    }
                    if($filtercount) {
                        $extrainfo = "MODIFIED_FILTERED_" . join('_', sort keys %filtered);
                    }

                    $rcode = 'NOERROR';
                } elsif($qtype ne 'ANY' && $qtype ne 'SOA') {
                    # If we need a specific record that is not ANY (e.g. record type might not exist, but host does),
                    # run a dummy query for type ANY. If we find *anything*, we return NOERROR.
                    #my $soareply = $resolver->search($qname, 'ANY');
                    my ($soareply, $soaerror) = $self->resolve_extern($qname, 'ANY');
                    if(defined($soareply) && defined($soareply->header)) {
                        $rcode = 'NOERROR';
                        $extrainfo = 'QTYPE_EMPTY';
                    } else {
                        $extrainfo = "NOREPLY";
                    }

                } else {
                    $extrainfo = 'NOREPLY';
                }
            }
        }
    }


    if($peerhost ne $RECURSIVELOOKUP) {
        if($self->{loginssth}->execute($qname, $qtype, $peerhost, $rcode, $proto, $remotelookup, $extrainfo)) {
            $dbh->commit;
        } else {
            $self->debuglog($dbh->{errstr});
            $dbh->rollback;
        }
    }

    # Correct returncode after special handling
    if($rcode eq 'FORCENX') {
        $rcode = 'NXDOMAIN';
        # $rcode = 'NOERROR';
        # $rcode = 'REFUSED';
    }

    if($rcode eq 'INVALID') {
        $rcode = 'NXDOMAIN';
    }

    return (1, $rcode, \@ans, \@auth, \@add, $remotelookup);
}


sub resolve_extern {
    my ($self, $qname, $qtype) = @_;

    my $dbh = $self->{dbh};

    my $reply;
    my $error;

if(1) {
    if(!$self->{cacheselsth}->execute($qname, $qtype)) {
        $self->debuglog("Cache sel error:", $dbh->errstr);
        $dbh->rollback;
    } else {
        while((my $line = $self->{cacheselsth}->fetchrow_hashref)) {
            if(defined($line->{packetdata}) && $line->{packetdata} ne '') {
                my $packetdata = decode_base64($line->{packetdata});
                $reply = Net::DNS::Packet->new(\$packetdata);
                $self->debuglog("Loaded cached data for $qname / $qtype");
            } elsif(defined($line->{lookuperror}) && $line->{lookuperror} ne '') {
                $error = $line->{lookuperror};
                $self->debuglog("Loaded cached error data for $qname / $qtype");
            }
            last;
        }
        $self->{cacheselsth}->finish;
        $dbh->commit;
    }
}

    if(!defined($reply) && !defined($error)) {
        my $resolver;
        if($self->{config}->{usegoogle}) {
            $resolver = Net::DNS::Resolver->new(nameservers => ['8.8.8.8', '8.8.4.4']);
        } else {
            $resolver = Net::DNS::Resolver::Recurse->new(config_file => $self->{config}->{resolvconf},  recurse => 1, debug => 0, search => '');
        }
        $reply = $resolver->search($qname, $qtype);

        my @fasterrors = qw[NOERROR SERVFAIL NOTIMP REFUSED NOTZONE];


        if(defined($reply)) {
            # Need to retrieve additional info for CNAME and MX

            my $recursecount = 8;
            while($recursecount) {
                my @rrs = $reply->answer;
                #$self->debuglog("MMMMMMMMMMMMMMMMMMMMMMMMMMM $recursecount");
                $recursecount--;

                # Check if *we* need to recursively look up CNAME and MX records
                my %incomplete;
                #    get all MX and CNAME records
                foreach my $rr (@rrs) {
                    next unless ($rr->type eq 'MX' || $rr->type eq 'CNAME');
                    my $subname = $rr->rdstring;
                    $subname =~ s/\.$//;
                    if($rr->type eq 'MX') {
                        $subname =~ s/^\d+\ //;
                    }
                    next if($subname eq '');
                    $incomplete{$subname} = 1;
                }
                #    now delete all entries from the incomplete list for which we know at least ONE address
                foreach my $rr (@rrs) {
                    next unless ($rr->type eq 'A' || $rr->type eq 'AAAA' || $rr->type eq 'CNAME');
                    my $owner = $rr->owner;
                    #$self->debuglog("************** GOT ADDRESS FOR $owner");
                    if(defined($incomplete{$owner})) {
                        delete $incomplete{$owner};
                    }
                }

                # All done;
                last if(!%incomplete);

                foreach my $subname (keys %incomplete) {
                    #$self->debuglog("MISSING A OR AAAA $subname");
                    foreach my $type (qw[A AAAA]) {
                        next if($type eq 'A' and $qtype eq 'AAAA');
                        next if($type eq 'AAAA' and $qtype eq 'A');

                        #$self->debuglog("-----------    REQUEST $type FOR $subname");
                        my $subreply = $resolver->search($subname, $type);
                        if(defined($subreply)) {
                            my @subrrs = $subreply->answer;
                            foreach my $subrr (@subrrs) {
                                next unless($subrr->type eq 'A' || $subrr->type eq 'AAAA' || $subrr->type eq 'CNAME');
                                #$self->debuglog("        SUBREPLY GOT " . $subrr->type . " " . $subrr->rdstring);
                                $reply->push(answer => $subrr);
                            }
                        }
                    }
                }
            }

        }

        if(defined($reply)) {
            my @rrs;
            push @rrs, $reply->authority;
            push @rrs, $reply->additional;
            push @rrs, $reply->answer;
            my $ttl = -1;
            foreach my $rr (@rrs) {
                next if($rr->type eq 'OPT');
                my $rrttl = $rr->ttl;
                next if(!defined($rrttl) || $rrttl eq '');
                $rrttl = 0 + $rrttl;
                next if(!$rrttl);
                #$self->debuglog("  RR TTL: $rrttl");
                if($ttl == -1 || $rrttl < $ttl) {
                    $ttl = $rrttl;
                }
            }
            if($ttl == -1) {
                $ttl = $self->{config}->{extern_cachetime};
            } else {
                $ttl = "$ttl seconds";
            }
            $self->debuglog("  Cache TTL: $ttl");

            #$self->debuglog("  ************** Packet  TTL: $ttl");
            my $packetdata = encode_base64($reply->data, '');
            if(!$self->{cacheinssth}->execute($qname, $qtype, $packetdata, '', $ttl)) {
                $self->debuglog("Cache ins error:", $dbh->errstr);
                $dbh->rollback;
            } else {
                $self->debuglog("Cached data for $qname / $qtype");
                $dbh->commit;
            }
        } elsif(!defined($reply) && defined($resolver->errorstring) && contains($resolver->errorstring, \@fasterrors)) {
            # Host exists but has no data for this qtype
            $error = $resolver->errorstring;
            if(!$self->{cacheinssth}->execute($qname, $qtype, '', $error, $self->{config}->{extern_cachetime})) {
                $self->debuglog("Cache ins error:", $dbh->errstr);
                $dbh->rollback;
            } else {
                $self->debuglog("Cached error data for $qname / $qtype");
                $dbh->commit;
            }
        } elsif(!defined($reply) && !defined($resolver->errorstring)) {
            # We just didn't find anything, this is a workaround for Net::DNS::Resolver in recurse mode
            $error = 'NOERROR';
            if(!$self->{cacheinssth}->execute($qname, $qtype, '', $error, $self->{config}->{extern_cachetime})) {
                $self->debuglog("Cache ins error:", $dbh->errstr);
                $dbh->rollback;
            } else {
                $self->debuglog("Cached not found data for $qname / $qtype");
                $dbh->commit;
            }
            
        }

    }

    return ($reply, $error);
}

sub fixDestination {
    my ($domain, $host) = @_;

    my $destination;
    if($host =~ /\./ || $host =~ /\:/) {
        $destination = $host;
    } else {
        $destination = $host . '.' . $domain;
    }

    return $destination;
}


1;

