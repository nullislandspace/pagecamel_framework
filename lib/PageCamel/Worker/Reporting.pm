package PageCamel::Worker::Reporting;
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

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;
use Net::Clacks::Client;
use PageCamel::Helpers::Padding qw(doSpacePad);

use IO::Handle;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{nextping} = 0;

    if(!$self->{isDebugging}) {
        $self->{stdout} = 0;
    }
    STDOUT->autoflush(1);
    $self->{lastlinelen} = 0;

    return $self;
}

sub reload {
    my ($self) = shift;

    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $oldlog = $memh->get($self->{APPNAME});
    my $restart = 0;
    if(defined($oldlog)) {
        $self->{debuglog} = $oldlog;
        $restart = 1;
    }

    if($restart) {
        $self->debuglog("****** RESTART DETECTED ********");
        #$self->auditlog($self->{modname}, 'RESTART DETECTED');
    } else {
        $self->debuglog("****** SERVICE STARTED ********");
        #$self->auditlog($self->{modname}, 'SERVICE STARTED');
    }

    return;
}

sub dblog {
    my ($self, $error_type, $description) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $sth = $dbh->prepare("INSERT INTO errors (error_type, description)" .
                            "VALUES (?, ?)")
                or croak($dbh->errstr);
    $sth->execute($error_type, $description) or croak($dbh->errstr);
    $sth->finish;
    $dbh->commit;

    return;
}

sub auditlog {
    my ($self, $modulename, $logtext) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $worker = $self->{PSAPPNAME};

    my $sth = $dbh->prepare("INSERT INTO auditlog (worker_name, module_name, logtext)" .
                            "VALUES (?, ?, ?)")
                or croak($dbh->errstr);
    $sth->execute($worker, $modulename, $logtext) or croak($dbh->errstr);
    $sth->finish;
    $dbh->commit;

    return;
}

sub debuglog {
    my ($self, @parts) = @_;

    my $line = '';
    foreach my $part (@parts) {
        #if(!defined($part)) {
        #    croak("debuglog called with undefined part");
        #}
        next unless(defined($part));
        chomp $part;
        $line .= $part;
    }

    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    $line = getISODate() . " " . $line;

    my $name = 'Debuglog::' . $self->{APPNAME} . '::new';
    $name =~ s/\ /\_/g;

    $memh->clacks_set($name, $line);

    if($self->{std_out}) {
        print "\n$line";
        $self->{lastlinelen} = length($line);

    }

    return;
}

sub debuglog_overwrite {
    my ($self, @parts) = @_;

    my $line = '';
    foreach my $part (@parts) {
        chomp $part;
        $line .= $part;
    }

    my $memh = $self->{server}->{modules}->{$self->{memcache}};

    $line = getISODate() . " " . $line;

    my $name = 'Debuglog::' . $self->{APPNAME} . '::overwrite';
    $name =~ s/\ /\_/g;
    $memh->clacks_set($name, $line);

    if($self->{std_out}) {
        if(length($line) < $self->{lastlinelen}) {
            my $newlinelen = length($line);
            $line = doSpacePad($line, $self->{lastlinelen});
            $self->{lastlinelen} = $newlinelen;
        } else {
            $self->{lastlinelen} = length($line);
        }
        print "\r$line";
    }

    return;
}

1;
__END__

=head1 NAME

PageCamel::Worker::Reporting -

=head1 SYNOPSIS

  use PageCamel::Worker::Reporting;



=head1 DESCRIPTION



=head2 new



=head2 reload


=head2 dblog



=head2 auditlog



=head2 debuglog



=head2 debuglog_overwrite



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
