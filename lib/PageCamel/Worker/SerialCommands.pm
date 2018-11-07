package PageCamel::Worker::SerialCommands;
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

# Do some updates and advanced parsing for accesslog. Run at once an hour. The
# Exception here is: If workCount > 0 then it will ru in the next loop too

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DBSerialize;
use MIME::Base64;
use Net::Clacks::Client;
use Data::Dumper;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = Net::Clacks::Client->new($clconf->get('host'), $clconf->get('port'), $clconf->get('user'), $clconf->get('password'), $self->{PSAPPNAME} . ':' . $self->{modname});

    return $self;
}


sub register {
    my $self = shift;
    $self->register_worker("work");
    return;
}

sub crossregister {
    my ($self) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    $dbh->{disconnectIsFatal} = 1; # Don't automatically reconnect but exit instead!
    $dbh->commit;

    # Listen to session refresh notifications
    $self->{clacks}->listen('Login::Sessionrefresh');
    $self->{clacks}->doNetwork();
    $self->{nextping} = 0;

    return;

}


sub work {
    my ($self) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $workCount = 0;

    my $selsth = $dbh->prepare_cached("SELECT sid, extract(epoch from (valid_until - now())) AS valid_seconds
                                        FROM sessions")
            or croak($dbh->errstr);

    my $upsth = $dbh->prepare_cached("UPDATE sessions
                                   SET valid_until = (now() + interval '10 minutes')
                                   WHERE sid = ?")
            or croak($dbh->errstr);

    my $badel = $dbh->prepare_cached("DELETE FROM users_basicauthcache WHERE valid_until < now()")
            or croak($dbh->errstr);

    if($badel->execute) {
        $dbh->commit;
    } else {
        $dbh->rollback;
    }

    my $now = time;
    if($now > $self->{nextping}) {
        $self->{clacks}->ping();
        $self->{nextping} = $now + 30;
    }

    $self->{clacks}->doNetwork();

    my $firstrefresh = 1;
    my %sessions;
    while((my $message = $self->{clacks}->getNext())) {
        if($message->{type} eq 'disconnect') {
            $self->{clacks}->listen('Login::Sessionrefresh');
            $self->{clacks}->ping();
            $self->{clacks}->doNetwork();
            $self->{nextping} = $now + 30;
            next;
        }

        next unless(defined($message->{name}));

        if($message->{name} eq 'Login::Sessionrefresh' && $message->{type} eq 'set') {
            if($firstrefresh) {
                $firstrefresh = 0;
                $selsth->execute or croak($dbh->errstr);
                while((my $line = $selsth->fetchrow_hashref)) {
                    $sessions{$line->{sid}} = $line->{valid_seconds};
                }
                $selsth->finish;
                # Just unlock the table again as fast as possible
                $dbh->rollback;
            }

            if(!defined($sessions{$message->{data}})) {
                $reph->debuglog("Unknown session id " . $message->{data});
                next;
            }

            if($sessions{$message->{data}} > (5 * 60)) { # Only refresh is session is to expire in the next 5 minutes
                #$reph->debuglog("Session still fresh, id ". $message->{data});
                next;
            }

            if($upsth->execute($message->{data})) {
                $dbh->commit;
                $sessions{$message->{data}} = 10_000;
                $reph->debuglog("Session refreshed: " . $message->{data});
            } else {
                $dbh->rollback;
                $reph->debuglog("Session refresh FAILED: " . $message->{data});
            }

            $dbh->commit;
        }

    }


    return $workCount;
}

1;
__END__

=head1 NAME

PageCamel::Worker::SerialCommands -

=head1 SYNOPSIS

  use PageCamel::Worker::SerialCommands;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 crossregister



=head2 work



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
