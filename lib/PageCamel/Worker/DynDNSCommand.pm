# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license
package PageCamel::Worker::DynDNSCommand;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
use Data::Dumper;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Worker::BaseModule);
use PageCamel::Helpers::DateStrings;
use WWW::Mechanize::GZip;
use PageCamel::Helpers::DBSerialize qw/dbderef/;

use Readonly;

Readonly my $LASTIPMEMKEY => "DynDNSCommand::lastIP";

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;
    
    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my %commands;

    foreach my $cmd (qw[DYNDNS_UPDATE]) {
        my $cmdfunc = "do_" . lc($cmd);
        $commands{$cmd} = $cmdfunc;
    }
    $self->{extcommands} = \%commands;

    return $self;
}

sub reload {
    my ($self) = shift;
    # Nothing to do.. in here, we are pretty much self contained
    return;
}

sub register {
    my $self = shift;

    # Register ourselfs in the RBSCommands module with additional commands
    my $comh = $self->{server}->{modules}->{$self->{commands}};
    
    foreach my $cmd (sort keys %{$self->{extcommands}}) {
        $comh->register_extcommand($cmd, $self);
    }
    return;
}

sub execute {
    my ($self, $command, $arguments) = @_;
    
    if(defined($self->{extcommands}->{$command})) {
        my $cmdfunc = $self->{extcommands}->{$command};
        return $self->$cmdfunc($arguments);
    }
    return;
}

sub do_dyndns_update {
    my ($self, $arguments) = @_;
    my $host = $arguments->[0];
    my $done = 1;

    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $memh = $self->{server}->{modules}->{$self->{memcache}};
    my $reph = $self->{server}->{modules}->{$self->{reporting}};

    my $logtype = "OTHER"; # make logging visible only to admin user

    my $lastIP = $memh->get($LASTIPMEMKEY);
    if(!defined($lastIP)) {
        $lastIP = "";
    } else {
        $lastIP = dbderef($lastIP);
    }
    
    if($lastIP eq $host) {
        $reph->debuglog("DynDNS: IP not changed");
        return (1, $logtype);
    }
    
    $memh->set($LASTIPMEMKEY, $host);

    $reph->debuglog("DynDNS: Updating IPv6 tunnel...");
    my $mech = WWW::Mechanize::GZip->new();
    #$mech->credentials($device->{device_username}, $device->{device_password});
    
    #my $url = 'https://cavac:76b78acd@ipv4.tunnelbroker.net/ipv4_end.php?tid=276082&ip=' . $host;
    my $url = 'https://cavac:lmXwoMY4al+odLX3@ipv4.tunnelbroker.net/nic/update?hostname=276082&myip=' . $host;
    my $success = 0;
    my $result;
    if(!(eval {
        $result = $mech->get($url);
        $success = 1;
        1;
    })) {
        $success = 0;
    }
    if($success && defined($result) && $result->is_success) {
        my $content = $result->content;
        print STDERR "** $content **\n";
        $reph->debuglog("DynDNS: $content");

        return (1, $logtype);
    } else {
        $reph->debuglog("DynDNS: Failed");
    }

    return (0, $logtype);
}


1;
__END__

=head1 NAME

PageCamel::Worker::BackupCommand - database backup command module

=head1 SYNOPSIS

This module does PostgreSQL database backups.

=head1 DESCRIPTION

This module is a plugin module for the "Commands" module and handles
PostgreSQL backups.

=head1 Configuration

    <module>
        <modname>backupcommand</modname>
        <pm>BackupCommand</pm>
        <options>
            <db>maindb</db>
            <memcache>memcache</memcache>
            <commands>commands</commands>
            <reporting>reporting</reporting>
            <pgdump>/usr/bin/pg_dump</pgdump>
            <basedir>/path/to/backups</basedir>
            <host>localhost</host>
            <port>5432</port>
            <username>postgres</username>
            <database>RBS_DB</database>
            <sudouser>someusername</sudouser>
        </options>
    </module>



=head2 execute

Callback to run a command.

=head2 do_backup

Internal function, call the external pg_dump command to execute a full database backup.

=head1 Dependencies

This module depends on the following modules beeing configured (the 'as "somename"'
means the key name in this modules configuration):

PageCamel::Worker::PostgresDB as "db"
PageCamel::Worker::Memcache as "memcache"
PageCamel::Worker::Commands as "commands"
PageCamel::Worker::Reporting as "reporting"

=head1 SEE ALSO

PageCamel::Worker

=head1 AUTHOR

Rene Schickbauer, E<lt>pagecamel@cavac.atE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
