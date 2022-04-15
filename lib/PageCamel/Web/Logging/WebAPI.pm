package PageCamel::Web::Logging::WebAPI;
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
use XML::RPC;

my %apifunctions = (
    gettempsens     => \&api_gettempsens,
);

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub reload {
    my ($self) = shift;

    # Nothing to do.. in here, we only use the template and database module
    return;
}

sub register {
    my $self = shift;
    $self->register_webpath($self->{webpath}, "get", 'POST');

    return;
}

sub crossregister {
    my $self = shift;

    $self->register_public_url($self->{webpath});

    return;
}

# Get supervisor cards
sub get {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    my $host = $ua->{remote_addr} || '0.0.0.0';
    my $xmlrpc = XML::RPC->new();
    my $xml = $ua->{postdata};


    return (status  => 400) unless(defined($xml)); # BAAAAAD Request! Sit! Stay!!

    my $data;
    my $haserrors = 0;
    if(!eval {
        $data = $xmlrpc->receive($xml, sub {
                my ($methodname, @params) = @_;

                if(!defined($apifunctions{$methodname})) {
                    $haserrors = 1;
                    return;
                }

                return $apifunctions{$methodname}($self, $ua, @params);
        });
    }) {
        $haserrors = 1;
    }
    return (status  => 403) if($haserrors);
    return (status  =>  403) unless defined($data); # Forbidden because something in the request wasn't ok

    return (status  => 200,
            data    => $data,
            type    => 'text/xml',
            "__do_not_log_to_accesslog" => 1,
    );
}


sub api_gettempsens {
    my($self, $ua, %options) =@_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $selsth = $dbh->prepare_cached("SELECT logtime, hostname, temperature, humidity
                                      FROM logging_log_tempsensor
                                        WHERE hostname = ?
                                        ORDER BY logtime DESC
                                        LIMIT 1")
            or croak($dbh->errstr);

    if(!$selsth->execute($options{hostname})) {
        $dbh->rollback;
        return {};
    }
    my $foo = {
               };
    if((my $line = $selsth->fetchrow_hashref)) {
        $foo = $line;
    }

    $selsth->finish;
    $dbh->rollback;
    return $foo;
}


1;
__END__

=head1 NAME

PageCamel::Web::Logging::WebAPI -

=head1 SYNOPSIS

  use PageCamel::Web::Logging::WebAPI;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 crossregister



=head2 get



=head2 api_gettempsens



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
