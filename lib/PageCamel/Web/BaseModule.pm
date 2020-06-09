package PageCamel::Web::BaseModule;
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
use Sys::Hostname;
use PageCamel::Helpers::DateStrings;
use Net::Clacks::Client;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $hname = hostname;

    my $self = bless \%config, $class;

    if(defined($self->{hosts}->{$hname})) {
        print "   Host-specific configuration for '$hname'\n";
        foreach my $keyname (keys %{$self->{hosts}->{$hname}}) {
            $self->{$keyname} = $self->{hosts}->{$hname}->{$keyname};
        }
    }

    if(!defined($self->{showads})) {
        $self->{showads} = 0;
    }

    return $self;
}

sub reload {
    # reload now optional in modules
    return;
}

sub register {
    # register is purely optional
    return;
}

sub crossregister {
    # crossregister is purely optional
    return;
}

sub handle_child_start {
    # Handle PageCamel::Net::Server::PreFork's child_init_hook() in preforking mode
    # This is optional but really usefull in stuff like database connections

    # THIS FUNCTION DOES *NOT* GET CALLED IN SINGLE THREAD MODE

    return;
}

sub handle_child_stop {
    my ($self) = @_;

    return;
}

sub create_cookie {
    my ($self, $ua, %fields) = @_;

    # Check for required fields
    foreach my $fname (qw[name value]) {
        if(!defined($fields{$fname})) {
            croak("Cookie field $fname not defined!");
        }
        if($fields{$fname} eq '') {
            croak("Cookie field $fname must nor be an empty string");
        }
    }

    if(!defined($fields{location})) {
        $fields{location} = $ua->{url};
    }

    if(!defined($fields{expires}) || $fields{expires} eq '') {
        $fields{expires} = getWebdate();
    } else {
        # Reparse field to make sure we have the proper format
        $fields{expires} = getWebdate(parseWebdate($fields{expires}));
    }

    my $cookie = $fields{name} . '=' . $fields{value} .
        '; path=' . $fields{location} .
        '; expires=' . $fields{expires};

    if(defined($fields{httponly}) && $fields{httponly}) {
        $cookie .= '; HttpOnly';
    }

    if(defined($fields{secure}) && $fields{secure}) {
        $cookie .= '; Secure';
    }

    if(defined($fields{samesite})) {
        my $samemode = 'Strict';
        if(lc $fields{samesite} eq 'lax') {
            $samemode = 'Lax';
        }
        $cookie .= '; SameSite=' . $samemode;
    }


    $cookie =~ s/\;$//g;

    return $cookie;

}

sub finalcheck {
    # finalcheck is purely optional
    return;
}

sub endconfig {
    # Called after everything is configured and the webserver is ready to serve data.
    # This method is most likely only usefull in forking servers to dump any data
    # that needs to be re-initialized after forking, for example database handles
    # and memcached connections which are also in use before forking)
}


sub extend_header {
    my ($self, $headers, $headername, $value) = @_;

    if(!defined($headers->{$headername})) {
        $headers->{$headername} = $value;
        return;
    }

    if($headers->{$headername} !~ $value) {
        $headers->{$headername} .= ",$value";
    }
    return;
}

# Convenience functions for registering various callbacks
sub register_webpath {
    my ($self, $path, $funcname, @methods) = @_;

    confess("No Webpath specified") unless defined($path);
    confess("No function name specified") unless defined($funcname);

    $self->{server}->add_webpath($path, $self, $funcname, @methods);
    return;
}

sub register_overridewebpath {
    my ($self, $path, $funcname, @methods) = @_;

    confess("No Webpath specified") unless defined($path);
    confess("No function name specified") unless defined($funcname);

    $self->{server}->add_overridewebpath($path, $self, $funcname, @methods);
    return;
}

sub register_custom_method {
    my ($self, $method, $funcname) = @_;

    confess("No Method specified") unless defined($method);
    confess("No function name specified") unless defined($funcname);

    $self->{server}->add_custom_method($method, $self, $funcname);
    return;
}

sub register_protocolupgrade {
    my ($self, $path, $funcname, @protocols) = @_;

    confess("No Webpath specified") unless defined($path);
    confess("No function name specified") unless defined($funcname);
    confess("No protocols specified") unless(@protocols);

    $self->{server}->add_protocolupgrade($path, $self, $funcname, @protocols);
    return;
}

sub register_basic_auth {
    my ($self, $url, $realm) = @_;

    $self->{server}->add_basic_auth($url, $realm);
    return;
}

sub get_basic_auths {
    my ($self) = @_;

    return $self->{server}->get_basic_auths();
}

sub register_public_url {
    my ($self, $url) = @_;

    $self->{server}->add_public_url($url);
    return;
}

sub get_public_urls {
    my ($self) = @_;

    return $self->{server}->get_public_urls();
}

# Allow Cross Origin Resource Sharing on specific URLs
sub register_cors {
    my ($self, $path, $origin, @methods) = @_;

    confess("No Webpath specified") unless defined($path);
    confess("No origin specified") unless defined($origin);
    confess("No methods specified") unless(@methods);

    $self->{server}->add_cors($path, $self, $origin, @methods);
    return;
}

BEGIN {
    # Auto-magically generate a number of similar functions without actually
    # writing them down one-by-one. This makes consistent changes much easier, but
    # you need perl wizardry level +10 to understand how it works...
    #
    # Added wizardry points are gained by this module beeing a parent class to
    # all other web modules, so this auto-generated functions are subclassed into
    # every child.
    my @stdFuncs = qw(prefilter postauthfilter postfilter defaultwebdata late_defaultwebdata task loginitem
                        logoutitem sessionrefresh preconnect prerender cleanup authcheck logstart
                        logend logdatadelivery logwebsocket logrequestfinished logstacktrace remotelog sitemap firewall fastredirect);

    # -- Deep magic begins here...
    for my $a (@stdFuncs){
        #print STDERR "Function " . __PACKAGE__ . "::register_$a will call add_$a\n";
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
        *{__PACKAGE__ . "::register_$a"} =
            sub {
                my $funcname = "add_$a";
                confess("No function name specified") unless defined($funcname);
                $_[0]->{server}->$funcname($_[0], $_[1]);
            };
    }
    # ... and ends here
}

#sub register_prefilter {
#    my ($self, $funcname) = @_;
#
#    confess("No function name specified") unless defined($funcname);
#    $self->{server}->add_prefilter($self, $funcname);
#}


sub newClacksFromConfig {
    my ($self, $clconf) = @_;

    my $socket = $clconf->get('socket');
    my $clacks;
    if(defined($socket) && $socket ne '') {
        $clacks = Net::Clacks::Client->newSocket($socket, $clconf->get('user'), $clconf->get('password'), $self->{PSAPPNAME} . ':' . $self->{modname});
    } else {
        $clacks = Net::Clacks::Client->new($clconf->get('host'), $clconf->get('port'), $clconf->get('user'), $clconf->get('password'), $self->{PSAPPNAME} . ':' . $self->{modname});
    }

    return $clacks;
}

1;
__END__

=head1 NAME

PageCamel::Web::BaseModule - the basis of all web modules

=head1 SYNOPSIS

  use PageCamel::Web::BaseModule;

=head1 DESCRIPTION

This module doesn't get called in itself, but is the basis for all PageCamel web modules ("use base").

=head2 new

Create a new instance.

=head2 reload

Reload modules external content.

=head2 register

Register modules callbacks from Web.pm

=head2 crossregister

Register callbacks to modules loaded by Web.pm.

=head2 handle_child_start

Handle PageCamel::Net::Server::PreFork's child_init_hook() in preforking mode.
This is optional but really usefull in stuff like database connections

THIS FUNCTION DOES *NOT* GET CALLED IN SINGLE THREAD MODE


=head2 handle_child_stop

Handle PageCamel::Net::Server::PreFork's child_finish_hook() in preforking mode
This is optional but really usefull in stuff like database connections

Note: DESTROY() does not seem to be called reliably in preforking mode, so
handle_stopchild defaults to calling $self->DESTROY()

THIS FUNCTION DOES *NOT* GET CALLED IN SINGLE THREAD MODE

By calling DESTROY by default, this should nicely "simulate" single
thread handling. WARNING, in some cases, DESTROY might get called twice, so
proper coding (e.g. checking for already freed handles and such) is mandatory.


=head2 create_cookie

Create a cookie string.

=head2 DESTROY

Currently does nothinh.

=head2 finalcheck

This gets called just before the webserver switched from STARTUP to RUNNING

=head2 endconfig

This gets called just before the webserver switched from STARTUP to RUNNING

=head2 extend_header

Extend a (possibly) existing header with more values.

=head2 register_webpath

Register a webpath.

=head2 register_overridewebpath

Register an override webpath.

=head2 register_custom_method

Register a custom method.

=head2 register_protocolupgrade

Register a protocolupgrade (e.g. websocket handling)

=head2 register_public_url

Register a public URL.

=head2 get_public_urls

List all public URLs.

=head2 register_cors

Register CORS (cross-origin resource sharing)

=head2 register_prefilter

Register a prefilter callback.

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
