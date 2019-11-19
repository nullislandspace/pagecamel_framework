package PageCamel::Web::Errors;
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

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;




sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my $whereclause = " WHERE ack_done = false ";
    if(defined($self->{views})) {
        my @parts;
        foreach my $part (@{$self->{views}->{view}}) {
            push @parts, "'" . $part . "'";
        }
        $whereclause .= " AND error_type IN (" . join(',', @parts)  . ")";
    }
    $self->{whereclause} = $whereclause;

    return $self;
}

sub reload {
    my ($self) = shift;
    # Nothing to do.. in here, we only use the template and database module
    return;
}

sub register {
    my $self = shift;
    $self->register_webpath($self->{webpath}, "get");

    if(defined($self->{templatevar})) {
        $self->register_defaultwebdata("get_defaultwebdata");
    }
    return;
}

sub get {
    my ($self, $ua) = @_;


    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $th = $self->{server}->{modules}->{templates};

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        PostLink        =>  $self->{webpath}
    );

    my $mode = $ua->{postparams}->{'mode'} || 'view';
    if($mode ne "view") {
        my $command = "";
        my @errorids;
        if(defined($ua->{postparams}->{'error_id'})) {
            if(ref $ua->{postparams}->{'error_id'} eq 'ARRAY') {
               @errorids = @{$ua->{postparams}->{'error_id'}};
            } else {
                @errorids = ($ua->{postparams}->{'error_id'});
            }
        }

        my $acksth = $dbh->prepare_cached("UPDATE errors
                                          SET ack_done = true,
                                          ack_time = now(),
                                          ack_user = ?
                                          WHERE error_id = ? ")
                or croak($dbh->errstr);

        foreach my $errorid (@errorids) {
            my $ackstate = $ua->{postparams}->{$errorid . '_ack'} || '';
            next if($ackstate ne "1" && $ackstate ne "on");

            if($acksth->execute($webdata{userData}->{user}, $errorid)) {
                $acksth->finish;
                $dbh->commit;
            } else {
                $dbh->rollback();
            }
        }
    }

    # Reload webdata after update
    %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        PostLink        =>  $self->{webpath}
    );

    my $errsth = $dbh->prepare_cached("SELECT error_id, reporttime, error_type, description " .
                               "FROM errors " .
                               $self->{whereclause} .
                               "ORDER BY reporttime"
                                )
                    or croak($dbh->errstr);
    my @errors;
    $errsth->execute or croak($dbh->errstr);
    while((my $errline = $errsth->fetchrow_hashref)) {
        $errline->{error_image} = "rbserror_" . lc($errline->{error_type}) . ".bmp";
        push @errors, $errline;
    }
    $errsth->finish;
    $webdata{errors} = \@errors;

    $dbh->rollback;

    my $template = $self->{server}->{modules}->{templates}->get("errors", 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template);
}

sub get_defaultwebdata {
    my ($self, $webdata) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $stmt = "SELECT count(*) FROM errors " .
                $self->{whereclause};

    my $sth = $dbh->prepare_cached($stmt) or croak($dbh->errstr);
    $sth->execute or croak($dbh->errstr);
    my $cnt = 0;
    while((my @line = $sth->fetchrow_array)) {
        $cnt = $line[0];
    }
    $sth->finish;
    $dbh->rollback;

    $webdata->{$self->{templatevar}} = $cnt;
    return;
}

1;
__END__

=head1 NAME

PageCamel::Web::Errors -

=head1 SYNOPSIS

  use PageCamel::Web::Errors;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 get



=head2 get_defaultwebdata



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
