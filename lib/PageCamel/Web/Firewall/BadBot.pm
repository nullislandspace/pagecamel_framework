package PageCamel::Web::Firewall::BadBot;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);

use PageCamel::Helpers::UserAgent qw[simplifyUA];

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub register($self) {
    $self->register_prefilter("prefilter");
    return;
}

sub prefilter($self, $ua) {

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $host = $ua->{remote_addr};
    my $userAgent = $ua->{headers}->{'User-Agent'} || '--unknown--';
    my ($simpleUserAgent, $badBot) = simplifyUA($userAgent);

    if($badBot) {
        my $insth = $dbh->prepare_cached("INSERT INTO accesslog_blocklist (ip_address, is_automatic, is_badbot, description)
                                         VALUES (?, true, true, ?)")
                or croak($dbh->errstr);
        if($insth->execute($host, "Bad Bot $simpleUserAgent")) {
            $dbh->commit;
        } else {
            $dbh->rollback;
        }


        return (status  => 403,
                type    => 'text/plain',
                data    => "Your user agent has been identified as a 'bad bot', as '$simpleUserAgent'. Go away, please!",
        );
    }

    return;
}

1;
__END__

=head1 NAME

PageCamel::Web::Firewall::BadBot -

=head1 SYNOPSIS

  use PageCamel::Web::Firewall::BadBot;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 prefilter



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
