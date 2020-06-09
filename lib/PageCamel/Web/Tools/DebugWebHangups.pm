package PageCamel::Web::Tools::DebugWebHangups;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);

use MIME::Base64;
use Time::HiRes qw[sleep];

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    return $self;
}

sub register {
    my $self = shift;

    $self->register_logstart("logstart");
    $self->register_logend("logend");
    $self->register_logrequestfinished("logrequestfinished");
    $self->register_logwebsocket("logwebsocket");
    $self->register_logdatadelivery("logdatadelivery");
    $self->register_logstacktrace("logstacktrace");

    return;
}

sub crossregister {
    my ($self) = @_;

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    my $clacks = $self->newClacksFromConfig($clconf);
    for(my $id = 0; $id <= 65_535; $id++) {
        my $key = "PageCamel::WebHangups::$id";
        $clacks->remove($key);
    }
    $clacks->doNetwork();

    return;
}

sub handle_child_start {
    my ($self) = @_;

    my $clconf = $self->{server}->{modules}->{$self->{clacksconfig}};
    $self->{clacks} = $self->newClacksFromConfig($clconf);
    $self->{clackskey} = 'PageCamel::WebHangups::' . $PID;
    $self->{clacks}->disablePing();
    $self->{clacks}->store($self->{clackskey}, 'IDLE');
    $self->{clacks}->doNetwork();

    return;
}

sub handle_child_stop {
    my ($self) = @_;

    $self->{clacks}->remove($self->{clackskey});
    $self->{clacks}->doNetwork();

    return;
}


sub logstart {
    my ($self, $ua) = @_;

    my $webpath = $ua->{url} || '--unknown--';

    my $method = $ua->{method} || '--unknown--';
    my $protocol = 'http';
    if($self->{usessl}) {
        $protocol = 'https';
    }

    my $debuginfo = join(' ## ', $webpath, $method, $protocol);
    $self->{clacks}->store($self->{clackskey}, 'LOGSTART ' . $debuginfo);
    $self->{clacks}->doNetwork();
    $self->{debuginfo} = $debuginfo;

    return;
}

sub logend {
    my ($self, $ua) = @_;

    $self->{clacks}->store($self->{clackskey}, 'LOGEND ' . $self->{debuginfo});
    $self->{clacks}->doNetwork();

    return;
}


sub logdatadelivery {
    my ($self, $ua) = @_;

    $self->{clacks}->store($self->{clackskey}, 'LOGDATADELIVERY ' . $self->{debuginfo});
    $self->{clacks}->doNetwork();

    return;
}

sub logwebsocket {
    my ($self, $ua) = @_;

    $self->{clacks}->store($self->{clackskey}, 'LOGWEBSOCKET ' . $self->{debuginfo});
    $self->{clacks}->doNetwork();

    return;
}

sub logrequestfinished {
    my ($self, $ua, $header, $result) = @_;

    $self->{clacks}->store($self->{clackskey}, 'IDLE');
    $self->{clacks}->doNetwork();
    delete $self->{debuginfo};

    return;
}

sub logstacktrace {
    my ($self, $message) = @_;

    my $key = 'DEBUG::STACKTRACE::' . $PID;
    print STDERR "############################# KEY $key\n";
    print STDERR "############################# MESSAGE $message\n";
    $message = encode_base64($message, '');

    $self->{clacks}->set($key, $message);
    for(1..5) {
        $self->{clacks}->doNetwork();
        sleep(0.1);
    }

    return;
}


# logdatadelivery logwebsocket logrequestfinished

1;
__END__

=head1 NAME

PageCamel::Web::Accesslog - log all webcalls

=head1 SYNOPSIS

  use PageCamel::Web::Accesslog;

=head1 DESCRIPTION

Logs all webcalls in the "accesslog" table

=head2 new

Create a new instance.

=head2 register

Register the logstart and logend callbacks

=head2 logstart

"Remember" initial request informations.

=head2 logend

Write log entry.

=head2 get_defaultwebdata

Default "__do_not_log_to_accesslog" to false (= log always)

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
