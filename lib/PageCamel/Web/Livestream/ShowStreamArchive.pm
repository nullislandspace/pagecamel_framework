package PageCamel::Web::Livestream::ShowStreamArchive;
#---AUTOPRAGMASTART---
use 5.032;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.0;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
use feature 'signatures';
no warnings qw(experimental::signatures);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    if(!defined($self->{show_unreleased})) {
        $self->{show_unreleased} = 0;
    }

    return $self;
}

sub register {
    my ($self) = @_;
    $self->register_webpath($self->{webpath}, "get");

    return;
}

sub get {
    my ($self, $ua) = @_;

    my $th = $self->{server}->{modules}->{templates};
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $streamid = $ua->{url};
    $streamid =~ s/^.*\///g;

    my $selsth = $dbh->prepare_cached("SELECT *, CASE WHEN publish_time < now() THEN true ELSE false END AS publish_date_ok
                                        FROM livestreams WHERE livestream_id = ?")
        or croak($dbh->errstr);

    if(!$selsth->execute($streamid)) {
        $dbh->rollback;
        return(status => 500);
    }
    my $line = $selsth->fetchrow_hashref();
    $selsth->finish;
    $dbh->commit;

    if(!defined($line) || !defined($line->{livestream_id})) {
        return (status => 404);
    }

    if(!$self->{show_unreleased} && (!$line->{is_published} || !$line->{publish_date_ok})) {
        return (status => 404);
    }

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $line->{title},
        Description   =>  $line->{description},
        PublishDate   =>  $line->{publish_time},
        M3U8File => $self->{filepath} . '/' . $streamid . '/' . $self->{m3u8file},
        showads => $self->{showads},
    );

    my @extrascripts = ('/static/hls.js');
    $webdata{HeadExtraScripts} = \@extrascripts;

    my $template = $self->{server}->{modules}->{templates}->get('livestream/showstreamarchive', 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => 'text/html',
            data    => $template,
            expires         => $self->{expires},
            cache_control   =>  $self->{cache_control},
            );
}

1;
__END__


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
