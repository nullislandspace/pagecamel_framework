package PageCamel::Web::Livestream::ManageStream;
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

    return $self;
}

sub reload {
    my ($self) = shift;
    # Nothing to do.. in here, we only use the template and database module
    return;
}

sub register {
    my ($self) = @_;
    $self->register_webpath($self->{webpath}, "get", "GET", "POST");

    return;
}

sub get {
    my ($self, $ua) = @_;

    my $th = $self->{server}->{modules}->{templates};
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $streammode = $self->getStreamMode();

    my $mode = $ua->{postparams}->{'mode'} || 'view';

if(1) {
    if($mode eq 'start') {
        my $cmd = $self->{startscript};
        `$cmd`;
        sleep(3);
        $streammode = $self->getStreamMode();
    } elsif($mode eq 'stop') {
        for(1..3) {
            `killall ffmpeg`;
            sleep(1);
        }
        `killall -9 ffmpeg`;
        sleep(1);
        $streammode = $self->getStreamMode();
    } elsif($mode eq 'archive') {
        return(status => 500) if(!defined($self->{livedir}) || $self->{livedir} eq '');
        return(status => 500) if(!defined($self->{archivedir}) || $self->{archivedir} eq '');

        my $title = $ua->{postparams}->{'title'} || 'Untitled Stream';
        my $inssth = $dbh->prepare("INSERT INTO livestreams (title) VALUES (?) RETURNING livestream_id")
                or croak($dbh->errstr);

        if(!$inssth->execute($title)) {
            $dbh->rollback;
            print STDERR $dbh->errstr, "\n";
            return(status => 500);
        }
        my $line = $inssth->fetchrow_hashref;
        $inssth->finish;
        $dbh->commit;

        my $livestreamid  = $line->{livestream_id};
        my $targetdir = $self->{archivedir} . '/' . $livestreamid;
        mkdir $targetdir;

        my $cmd = 'cp ' . $self->{livedir} . '/* ' . $targetdir;
        `$cmd`;
        $cmd = 'touch ' . $self->{livedir} . '/_is_archived';
        `$cmd`;
        $streammode = $self->getStreamMode();
    } elsif($mode eq 'cleanup') {
        sleep(1);
        my $cmd = 'rm ' . $self->{livedir} . '/*';
        `$cmd`;
        $streammode = $self->getStreamMode();
    }
}


    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $self->{pagetitle},
        PostLink => $self->{webpath},
        StreamMode => $streammode,
    );


    my $template = $self->{server}->{modules}->{templates}->get('livestream/managestream', 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => 'text/html',
            data    => $template,
            );
}

sub getStreamMode {
    my ($self) = @_;

    my $streammode = 1;
    if(-f $self->{livedir} . '/_is_archived') {
        $streammode = 4;
    } elsif(-f $self->{livedir} . '/index.m3u8') {
        $streammode = 3;
    }

    my @processes = `ps aux | grep -v grep | grep ffmpeg`;
    foreach my $process (@processes) {
        if($process =~ /ffmpeg/) {
            $streammode = 2;
        }
    }


    return $streammode;
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

Copyright (C) 2008-2019 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
