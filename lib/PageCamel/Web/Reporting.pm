package PageCamel::Web::Reporting;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.0;
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

    if(!defined($self->{memcache})) {
        croak("No memcache defined for module " . $self->{modname});
    }

    return $self;
}

sub crossregister {
    my ($self) = @_;

    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $type = ref $memh;

    if($type !~ /ClacksCache$/ && $type !~ /ClacksCachePg$/) {
        croak("memcache type is $type but needs to be of type ClacksCache or ClacksCachePg in module " . $self->{modname});
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
    my ($self, $modulename, $logtext, $username, @extrainfo) = @_;

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

sub debuglog {
    my ($self, @parts) = @_;

    my $line = '';
    foreach my $part (@parts) {
        chomp $part;
        $line .= $part;
    }

    $line = getISODate() . " " . $line;
    my $name = 'Debuglog::' . $self->{APPNAME} . '::new';
    $name =~ s/\ /\_/g;

    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    $memh->clacks_set($name, $line);

    if($self->{std_out}) {
        print STDERR "$line\n";
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

    $line = getISODate() . " " . $line;
    my $name = 'Debuglog::' . $self->{APPNAME} . '::overwrite';
    $name =~ s/\ /\_/g;

    $self->{clacks}->set($name, $line);

    if($self->{std_out}) {
        print STDERR "$line\n";
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

Copyright (C) 2008-2019 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
