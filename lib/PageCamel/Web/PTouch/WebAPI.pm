package PageCamel::Web::PTouch::WebAPI;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.2;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;
use XML::RPC;
use PageCamel::Helpers::DataBlobs;
use MIME::Base64;

my %apifunctions = (
    getnext     => \&api_getnext,
    completed   => \&api_completed,
);

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub reload($self) {

    # Nothing to do.. in here, we only use the template and database module
    return;
}

sub register($self) {
    $self->register_webpath($self->{webpath}, "get", 'POST');

    return;
}

sub crossregister($self) {

    $self->register_public_url($self->{webpath});

    return;
}

sub get($self, $ua) {

    my $dbh = $self->{server}->{modules}->{$self->{db}};

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
            "__do_not_log_to_accesslog" => 1,
            data    => $data,
            type    => 'text/xml',
    );
}


sub api_getnext {
    my($self, $ua, %options) =@_;

    my $host = $ua->{remote_addr} || '0.0.0.0';

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $selsth = $dbh->prepare_cached("SELECT * FROM ptouch_queue
                                        WHERE is_active = false
                                        AND printer_name = ?
                                        ORDER BY queuetime
                                        LIMIT 1
                                        FOR UPDATE NOWAIT")
            or croak($dbh->errstr);

    my $upsth = $dbh->prepare_cached("UPDATE ptouch_queue
                                        SET is_active = true
                                        WHERE job_id = ?")
            or croak($dbh->errstr);


    if(!$selsth->execute($options{printer_name})) {
        $dbh->rollback;
        return {status => 0};
    }

    my $job = $selsth->fetchrow_hashref;
    $selsth->finish;

    if(!defined($job)) {
        $dbh->rollback;
        return {status => 0};
    }

    if(!$upsth->execute($job->{job_id})) {
        $dbh->rollback;
        return {status => 0};
    }

    $dbh->commit;

    my $foo = {
               job_id  => $job->{job_id},
               label_type  => $job->{label_type},
               label_data  => $job->{labeldata},
               status   => 1,
               };

    return $foo;
}

sub api_completed {
    my($self, $ua, %options) =@_;

    my $host = $ua->{remote_addr} || '0.0.0.0';

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $delsth = $dbh->prepare_cached("DELETE FROm ptouch_queue
                                        WHERE job_id = ?")
            or croak($dbh->errstr);


    if(!$delsth->execute($options{job_id})) {
        $dbh->rollback;
        return {status => 0};
    }

    $dbh->commit;

    return {status => 1};
}


1;
__END__

=head1 NAME

PageCamel::Web::PTouch::WebAPI -

=head1 SYNOPSIS

  use PageCamel::Web::PTouch::WebAPI;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 crossregister



=head2 get



=head2 api_getnext



=head2 api_completed



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
