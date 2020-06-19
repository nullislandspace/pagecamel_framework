package PageCamel::Worker::Twitter::TweetOutbox;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.2;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
use Data::Dumper;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);

use Net::Twitter;
use Scalar::Util qw[blessed];

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub reload {
    my ($self) = shift;
    # Nothing to do.. in here, we are pretty much self contained
    return;
}

sub register {
    my $self = shift;
    $self->register_worker("work");
    return;
}


sub work {
    my ($self) = @_;

    my $reph = $self->{server}->{modules}->{$self->{reporting}};
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $selsth = $dbh->prepare_cached("SELECT * FROM twitter_outbox o
                                        INNER JOIN twitter_accounts a
                                        ON (o.account_name = a.account_name)
                                        WHERE is_sent = false
                                        AND has_error = false
                                        AND starttime <= now()
                                        ORDER BY starttime, tweet_id
                                        LIMIT 1")
        or croak($dbh->errstr);

    $selsth->execute or croak($dbh->errstr);

    my $tweet = $selsth->fetchrow_hashref;
    $selsth->finish;
    if(!defined($tweet) || !defined($tweet->{tweet_id})) {
        $dbh->rollback;
        return 0;
    }

    my $parent;
    if(defined($tweet->{inreplyto_tweet_id} && $tweet->{inreplyto_tweet_id} ne '')) {
        my $parentsth = $dbh->prepare_cached('SELECT * FROM twitter_outbox
                                             WHERE tweet_id = ?
                                             AND has_error = false
                                             ')
                or croak($dbh->errstr);
        $parentsth->execute($tweet->{inreplyto_tweet_id}) or croak($dbh->errstr);
        $parent = $parentsth->fetchrow_hashref;
        $parentsth->finish;
        if(!defined($parent) || !defined($parent->{twitter_real_id}) || $parent->{twitter_real_id} eq '') {
            $reph->debuglog("Can't get real parent tweet id!");
            $dbh->rollback;
            return 0;
        }
    }

    my $nt = Net::Twitter->new(
        traits          => ['API::RESTv1_1', 'OAuth'],
        consumer_key    => $tweet->{consumer_key},
        consumer_secret => $tweet->{consumer_secret},
        access_token    => $tweet->{access_token},
        access_token_secret => $tweet->{access_secret},
    );

    my $upsth = $dbh->prepare_cached("UPDATE twitter_outbox
                                     SET is_sent = true,
                                     twitter_real_id = ?
                                     WHERE tweet_id = ?")
            or croak($dbh->errstr);

    my $errorsth = $dbh->prepare_cached("UPDATE twitter_outbox
                                        SET has_error = true,
                                        errortext = ?
                                        WHERE tweet_id = ?")
            or croak($dbh->errstr);

    my $status;
    my $ok = 0;
    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
        if($tweet->{message_type} eq 'tweet') { # Standard tweet
            $status = $nt->update({status => $tweet->{message}});
        } elsif($tweet->{message_type} eq 'retweet') {
            $status = $nt->retweet({status => $tweet->{message}, id => $parent->{twitter_real_id}});
        } elsif($tweet->{message_type} eq 'reply') {
            $status = $nt->update({status => $tweet->{message}, in_reply_to_status_id => $parent->{twitter_real_id}});
        } elsif($tweet->{message_type} eq 'like') {
            $status = $nt->create_favorite($parent->{twitter_real_id});
        } else {
            #$reph->debuglog("Unimplemented Tweet message type " . $tweet->{message_type});
            croak("Unimplemented Tweet message type " . $tweet->{message_type});
        }
        $ok = 1;
    };

    if(!$ok) {
        if ( blessed $EVAL_ERROR && $EVAL_ERROR->isa('Net::Twitter::Error') ) {
            $errorsth->execute($EVAL_ERROR->error, $tweet->{tweet_id})
                    or croak($dbh->errstr);
            $dbh->commit;
            return 0;
        } else {
            # something bad happened!
            croak($EVAL_ERROR);
        }
    }

    my $realid = 0;
    if(defined($status) && defined($status->{id})) {
        $realid = $status->{id};
    }

    if(!$realid) {
        $reph->debuglog("Something went wrong with Twitter!");
        $errorsth->execute("Couldn't get real twitter ID!", $tweet->{tweet_id})
                    or croak($dbh->errstr);
        $dbh->commit;
        return 0;
    }

    if(!$upsth->execute($realid, $tweet->{tweet_id})) {
        $reph->debuglog("Failed update twitter_outbox!");
        $dbh->rollback;
        return 0;
    }

    $dbh->commit;
    $reph->debuglog("Sent message to twitter (" . $tweet->{tweet_id} . "), Twitter ID $realid");

    return 1;
}
1;
__END__

=head1 NAME

PageCamel::Worker::Twitter::TweetOutbox - send Tweets from twitter_outbox to Twitter

=head1 SYNOPSIS

  use PageCamel::Worker::Twitter::TweetOutbox;



=head1 DESCRIPTION

This module creates tweets based on information in twitter_outbox

=head2 new

Create a new instance

=head2 reload

Currently does nothing

=head2 register

Register work callback

=head2 work

Create the tweets

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

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
