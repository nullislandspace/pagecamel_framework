package PageCamel::Web::BaseModule;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---
use Sys::Hostname;
use PageCamel::Helpers::DateStrings;
use Net::Clacks::Client;

sub new($proto, %config) {
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

sub handle_child_stop($self) {
    return;
}

sub create_cookie($self, $ua, %fields) {
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

sub finalcheck($self) {
    # finalcheck is purely optional
    return;
}

sub endconfig($self) {
    # Called after everything is configured and the webserver is ready to serve data.
    # This method is most likely only usefull in forking servers to dump any data
    # that needs to be re-initialized after forking, for example database handles
    # and memcached connections which are also in use before forking)
}


sub extend_header($self, $headers, $headername, $value) {
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
sub register_webpath($self, $path, $funcname, @methods) {
    confess("No Webpath specified") unless defined($path);
    confess("No function name specified") unless defined($funcname);

    $self->{server}->add_webpath($path, $self, $funcname, @methods);
    return;
}

sub register_overridewebpath($self, $path, $funcname, @methods) {
    confess("No Webpath specified") unless defined($path);
    confess("No function name specified") unless defined($funcname);

    $self->{server}->add_overridewebpath($path, $self, $funcname, @methods);
    return;
}

sub register_uploadstreamwebpath($self, $path, $funcnamestream, $funcnamefinish) {
    confess("No Webpath specified") unless defined($path);
    confess("No stream function name specified") unless defined($funcnamestream);
    confess("No finish function name specified") unless defined($funcnamefinish);

    $self->{server}->add_uploadstream_webpath($path, $self, $funcnamestream, $funcnamefinish);
    return;
}

sub register_custom_method($self, $method, $funcname) {
    confess("No Method specified") unless defined($method);
    confess("No function name specified") unless defined($funcname);

    $self->{server}->add_custom_method($method, $self, $funcname);
    return;
}

sub register_protocolupgrade($self, $path, $funcname, @protocols) {
    confess("No Webpath specified") unless defined($path);
    confess("No function name specified") unless defined($funcname);
    confess("No protocols specified") unless(@protocols);

    $self->{server}->add_protocolupgrade($path, $self, $funcname, @protocols);
    return;
}

# Convenience functions for registering various callbacks
sub register_continueheader($self, $path, $funcname) {
    confess("No Webpath specified") unless defined($path);
    confess("No function name specified") unless defined($funcname);

    $self->{server}->add_continueheader($path, $self, $funcname);
    return;
}

sub register_basic_auth($self, $url, $realm) {
    $self->{server}->add_basic_auth($url, $realm);
    return;
}

sub get_basic_auths($self) {
    return $self->{server}->get_basic_auths();
}

sub register_public_url($self, $url) {
    $self->{server}->add_public_url($url);
    return;
}

sub get_public_urls($self) {
    return $self->{server}->get_public_urls();
}

# Allow Cross Origin Resource Sharing on specific URLs
sub register_cors($self, $path, $origin, @methods) {
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
                        logoutitem sessionrefresh preconnect prerender lateprerender cleanup authcheck logstart
                        logend logdatadelivery logwebsocket logrequestfinished logstacktrace remotelog sitemap firewall fastredirect debuglog);

    # -- Deep magic begins here...
    for my $f (@stdFuncs){
        #print STDERR "Function " . __PACKAGE__ . "::register_$f will call add_$f\n";
        no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)
        *{__PACKAGE__ . "::register_$f"} =
            sub ($arg1, $arg2) {
                my $funcname = "add_$f";
                confess("No function name specified") unless defined($funcname);
                $arg1->{server}->$funcname($arg1, $arg2);
            };
    }
    # ... and ends here
}

#sub register_prefilter($self, $funcname) {
#
#    confess("No function name specified") unless defined($funcname);
#    $self->{server}->add_prefilter($self, $funcname);
#}


sub newClacksFromConfig($self, $clconf) {
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

=head2 create_cookie

Create a cookie string.

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
