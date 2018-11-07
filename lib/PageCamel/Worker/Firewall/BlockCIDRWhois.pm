package PageCamel::Worker::Firewall::BlockCIDRWhois;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);

use Net::Whois::Raw;
use Net::Whois::Parser;
use JSON::XS;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{nextrun} = 0;

    return $self;
}


sub register {
    my $self = shift;
    $self->register_worker("work");
    return;
}


sub work {
    my ($self) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $workCount = 0;
    my $now = time;
    if($now > $self->{nextrun}) {
        $self->{nextrun} = time + 10;
    } else {
        return $workCount;
    }

    my $delwhoissth = $dbh->prepare_cached("DELETE FROM firewall_whois_cache
                                            WHERE logtime < (now() - interval '" . $self->{whoiscache} . "')")
            or croak($dbh->errstr);

    my $selwhoissth = $dbh->prepare_cached("SELECT * FROM firewall_whois_cache
                                            WHERE ? <<= network_cidr
                                            LIMIT 1")
            or croak($dbh->errstr);

    my $inswhoissth = $dbh->prepare_cached("INSERT INTO firewall_whois_cache
                                            (network_cidr, whois_raw)
                                            VALUES (?,?)")
            or croak($dbh->errstr);


    my $delblocksth = $dbh->prepare_cached("DELETE FROM firewall_block_cidr
                                            WHERE is_autoblocked = true
                                            AND seen_last < (now() - interval '" . $self->{blocktime} . "')")
            or croak($dbh->errstr);

    my $delcansth = $dbh->prepare_cached("DELETE FROM firewall_candidates
                                           WHERE is_processed = true
                                           AND logtime < (now() - interval '" . $self->{logtime} . "')")
            or croak($dbh->errstr);

    my $selsth = $dbh->prepare_cached("SELECT * FROM firewall_candidates
                                        WHERE is_processed = false
                                        ORDER BY logtime
                                        LIMIT 1")
            or croak($dbh->errstr);

    my $upnosth = $dbh->prepare_cached("UPDATE firewall_candidates
                                        SET is_processed = true
                                        WHERE candidate_id = ?")
            or croak($dbh->errstr);

    my $upyessth = $dbh->prepare_cached("UPDATE firewall_candidates
                                        SET is_processed = true,
                                        block_cidr = ?
                                        WHERE ip_address <<= ?
                                        AND is_processed = false")
            or croak($dbh->errstr);

    my $cidrmatchsth = $dbh->prepare_cached("SELECT * FROM firewall_block_cidr
                                            WHERE ? <<= blocked_network
                                            LIMIT 1")
            or croak($dbh->errstr);

    my $insth = $dbh->prepare_cached("INSERT INTO firewall_block_cidr
                                        (blocked_network, network_owner_whois,
                                         is_autoblocked, seen_first, seen_last)
                                        VALUES (?, ?, true, now(), now())")
            or croak($dbh->errstr);

    # Clean up stale blocks and candidates
    $delblocksth->execute() or croak($dbh->errstr);
    $delcansth->execute() or croak($dbh->errstr);
    $delwhoissth->execute() or croak($dbh->errstr);
    $dbh->commit;

    while(1) {
        # See if we have another candidate in the list
        $selsth->execute or croak($dbh->errstr);
        my $candidate = $selsth->fetchrow_hashref;
        $selsth->finish;
        if(!defined($candidate)) {
            $dbh->rollback;
            last;
        }
        $workCount++;

        # Ok, we got a new entry, let's check if we already
        # have a block for that (need to do this due to multi-forking and stuff)
        $cidrmatchsth->execute($candidate->{ip_address}) or croak($dbh->errstr);
        my $match = $cidrmatchsth->fetchrow_hashref;
        $cidrmatchsth->finish;
        if(defined($match)) {
            # Matched existing rule, mark ALL matching candidates as processed and start over
            $upyessth->execute($match->{blocked_network}, $match->{blocked_network}) or croak($dbh->errstr);
            $dbh->commit;
            next;
        }

        # Let's get the WHOIS entry for that IP
        # First, see if we already know about that network block
        $selwhoissth->execute($candidate->{ip_address}) or croak($dbh->errstr);
        my $cachedata = $selwhoissth->fetchrow_hashref;
        $selwhoissth->finish;

        my $whoisraw;
        my $cached = 0;
        if(defined($cachedata)) {
            $whoisraw = $cachedata->{whois_raw};
            $cached = 1;
        } else {
            $whoisraw = whois($candidate->{ip_address})
        }

        if(!defined($whoisraw)) {
            # Whoops, no WHOIS entry found, don't know if we can block it. Let's default
            # to avoiding false positives
            $upnosth->execute($candidate->{candidate_id}) or croak($dbh->errstr);
            $dbh->commit;
            next;
        }

        #my $whois = parse_whois($candidate->{ip_address});
        my $whois = parse_whois(raw => $whoisraw);
        if(!defined($whois)) {
            # Whoops, can't parse whois data
            $upnosth->execute($candidate->{candidate_id}) or croak($dbh->errstr);
            $dbh->commit;
            next;
        }

        my $destcidr = $candidate->{ip_address}; # default to "default subnet definitions" if we don't find a CIDR entry in WHOIS
        if(defined($whois->{cidr})) {
            $destcidr = $whois->{cidr};
        } elsif(defined($whois->{inet6num})) {
            $destcidr = $whois->{inet6num};
        }

        if(!$cached) {
            # Add raw whois data to cache
            if(ref $destcidr ne 'ARRAY') {
                $inswhoissth->execute($destcidr, $whoisraw) or croak($dbh->errstr);
            } else {
                foreach my $realdest (@{$destcidr}) {
                    $inswhoissth->execute($realdest, $whoisraw) or croak($dbh->errstr);
                }
            }
            $dbh->commit;
        }

        # now let's search the whois record. Easiest way is to make it a JSON string and them just regex over it
        my $json = encode_json $whois;

        if($json =~ /$candidate->{whois_must_match}/i) {
            # Bingo, got a match. Block this sucker
            $insth->execute($destcidr, $candidate->{whois_must_match}) or croak($dbh->errstr);
            $upyessth->execute($destcidr, $destcidr) or croak($dbh->errstr); # Mark ALL as candidates in this range as matched, even if the
                                                                             # whois_must_match doesn't fit, since we already have a block for this
                                                                             # CIDR in place
            $dbh->commit;
            next;
        }

        # Does not match our expectations
        $upnosth->execute($candidate->{candidate_id}) or croak($dbh->errstr);
        $dbh->commit;
        next;
    }

    $dbh->rollback;

    return $workCount;
}


1;
__END__

=head1 NAME

PageCamel::Worker::Firewall::BlockCIDRWhois - Block certain IP ranges based on their WHOIS entries

=head1 SYNOPSIS

  use PageCamel::Worker::Firewall::BlockCIDRWhois;

=head1 DESCRIPTION

Block IP ranges of certain owners. Many cloud services have good WHOIS entries, including
a line that specifies the complete IP range (CIDR block) for a specific IP adress.

=head2 new

Create a new instance

=head2 register

Register work callback

=head2 work

Create and clear firewall entries for IP ranges

=head1 IMPORTANT NOTE

This module is part of the PageCamel framework. Currently, only limited support
and documentation exists outside my DarkPAN repositories. This source is
currently only provided for your reference and usage in other projects (just
copy&paste what you need, see license terms below).

To see PageCamel in action and for news about the project,
visit my blog at L<https://cavac.at>.

=head1 AUTHOR

Rene Schickbauer, E<lt>pagecamel@cavac.atE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2016 by Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
