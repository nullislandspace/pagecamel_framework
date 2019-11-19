package PageCamel::Worker::Twitter::BlogTweet;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 2.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);

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

    my $selsth = $dbh->prepare_cached("SELECT * FROM blog
                                        WHERE is_released = true
                                        AND is_twittered = false
                                        AND releasedate <= now()
                                        AND twitter_message != ''
                                        ORDER BY releasedate
                                        LIMIT 1")
        or croak($dbh->errstr);

    $selsth->execute or croak($dbh->errstr);

    my $blogentry = $selsth->fetchrow_hashref;
    $selsth->finish;
    if(!defined($blogentry) || !defined($blogentry->{article_id})) {
        $dbh->rollback;
        return 0;
    }

    my $insth = $dbh->prepare_cached("INSERT INTO twitter_outbox
                                     (message, account_name)
                                     VALUES (?, ?)
                                     RETURNING tweet_id")
            or croak($dbh->errstr);

    my $upsth = $dbh->prepare_cached("UPDATE blog
                                     SET is_twittered = true
                                     WHERE article_id = ?")
            or croak($dbh->errstr);

    if(!$insth->execute($blogentry->{twitter_message}, $self->{twitter_account})) {
        $reph->debuglog("Failed to spool Tweet!");
        $dbh->rollback;
        return 0;
    }

    my $tweetid = $insth->fetch()->[0];
    $insth->finish;

    if(!$upsth->execute($blogentry->{article_id})) {
        $reph->debuglog("Failed update article (is_twittered)!");
        $dbh->rollback;
        return 0;
    }

    $dbh->commit;
    $reph->debuglog("Tweeted released blog (outbox id $tweetid)");

    return 1;
}

1;
__END__

=head1 NAME

PageCamel::Worker::Twitter::BlogTweet - Automatically tweet newly released blog articles

=head1 SYNOPSIS

  use PageCamel::Worker::Twitter::BlogTweet;

=head1 DESCRIPTION

This module automatically creates Tweets for newly released blog articles (created in twitter_outbox)

=head2 new

Create a new instance

=head2 reload

Currently does nothing

=head2 register

Register work callback

=head2 work

Create tweets

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

Copyright (C) 2008-2019 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
