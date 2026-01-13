package PageCamel::Web::Reporting;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 5.0;
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::Padding qw(doSpacePad);

use IO::Handle;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    if(!defined($self->{memcache})) {
        croak("No memcache defined for module " . $self->{modname});
    }
    STDERR->autoflush(1);
    $self->{lastlinelen} = 0;

    return $self;
}

sub register($self) {
    $self->register_debuglog('debuglog');

    return;
}

sub crossregister($self) {
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $type = ref $memh;

    if($type !~ /ClacksCache$/ && $type !~ /ClacksCachePg$/) {
        croak("memcache type is $type but needs to be of type ClacksCache or ClacksCachePg in module " . $self->{modname});
    }

    return;
}

sub dblog($self, $error_type, $description) {
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $sth = $dbh->prepare("INSERT INTO errors (error_type, description)" .
                            "VALUES (?, ?)")
                or croak($dbh->errstr);
    $sth->execute($error_type, $description) or croak($dbh->errstr);
    $sth->finish;
    $dbh->commit;

    return;
}

sub auditlog($self, $modulename, $logtext, $username, @extrainfo) {
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $worker = $self->{PSAPPNAME};

    my $sth = $dbh->prepare("INSERT INTO auditlog (worker_name, module_name, logtext, username, extrainfo) " .
                            "VALUES (?, ?, ?, ?, ?)")
                or croak($dbh->errstr);
    $sth->execute($worker, $modulename, $logtext, $username, \@extrainfo) or croak($dbh->errstr);
    $sth->finish;
    $dbh->commit;

    return;
}

sub debuglog($self, @parts) {
    my $line = '';
    foreach my $part (@parts) {
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
        print STDERR "\n", encode_utf8($line);
        $self->{lastlinelen} = length($line);
    }

    return;
}

sub debuglog_overwrite($self, @parts) {
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
        print STDERR "\r", encode_utf8($line);
    }

    return;
}

1;
__END__

=head1 NAME

PageCamel::Web::Reporting -

=head1 SYNOPSIS

  use PageCamel::Web::Reporting;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



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
