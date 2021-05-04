package PageCamel::Web::Firewall::Hostname;
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
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);

use URI;

# Detect "use server as proxy" attacks and block the client
#
# Also, if the client uses a hostname that is ours but isn't our default hostname, reroute
# the client to the correct one ("moved permanently")

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    if($self->{isDebugging}) {
        # Use 'localhost:8080' for debugging
        my %debugitem = (host => 'localhost:8080');
        push @{$self->{myhostnames}->{item}}, \%debugitem;
    }


    return $self;
}

sub register {
    my $self = shift;
    $self->register_prefilter("prefilter");
    $self->register_defaultwebdata("get_defaultwebdata");
    return;
}

sub prefilter {
    my ($self, $ua) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    if(defined($self->{defaultwebdata})) {
        delete $self->{defaultwebdata};
    }

    my $webpath = $ua->{original_path_info}; # Need the unmangled path
    my $requesthostname = $ua->{headers}->{Host};
    #print STDERR "Requested HOSTNAME: $requesthostname ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n";
    my $uriparser = URI->new($webpath);
    my $ip = $ua->{remote_addr};

    # Try to parse the hostname and relative PATH from URI.
    # This will fail if we already have a relative URL, which is perfectly
    # fine, since we want that anyway.
    # If we DO get hostname and relative path out of this, we update the values
    # in $ua
    my $urihostname;
    my $newwebpath;
    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
        $urihostname = $uriparser->host_port();
        $newwebpath = $uriparser->path();
    };

    if(defined($urihostname) && defined($newwebpath)) {
        # If on standard ports 80 or 443, remove those port numbers
        $urihostname =~ s/\:80$//;
        $urihostname =~ s/\:443$//;

        $ua->{headers}->{Host} = $urihostname;
        $ua->{url} = $newwebpath;
    }

    if(defined($urihostname) && $urihostname ne $requesthostname) {
        # Hostname in URI does not match Host header
        return (status => 400,
                type => 'text/plain',
                data => 'Hostnames given by client in request line and Host header do not match!',
                );
    }

    my $okname = 0;
    foreach my $item (@{$self->{myhostnames}->{item}}) {
        next unless($requesthostname eq $item->{host});
        $okname = 1;
        if(defined($item->{pathprefix})) {
            if($ua->{url} !~ /^\//) {
                $ua->{url} = '/' . $ua->{url};
            }

            my $doignore = 0;
            if(defined($item->{ignorepaths})) {
                foreach my $path (@{$item->{ignorepaths}->{item}}) {
                    my $suburl = substr($ua->{url}, 0, length($path));
                    if($suburl eq $path) {
                        #print STDERR "Ignoring PATH ", $ua->{url}, " for rerouting\n";
                        $doignore = 1;
                    }
                }
            }

            {
                my $path = $item->{pathprefix};
                my $suburl = substr($ua->{url}, 0, length($path));
                if($suburl eq $path) {
                    # Already pointing to the right sub path
                    $doignore = 1;
                }
            }


            if(!$doignore) {
                $ua->{url} = $item->{pathprefix} . $ua->{url};
                if(1 || $self->{isDebugging}) {
                    print STDERR "******************************************    internally rerouting to ", $ua->{url}, "\n";
                }
            }
            if(defined($item->{defaultwebdata})) {
                $self->{defaultwebdata} = $item->{defaultwebdata};
            }
        }

        if(defined($item->{reroute})) {
            my $newurl = 'https://' . $item->{reroute} . $ua->{url};
            return (status => 301,
                    location => $newurl,
                    type => 'text/html',
                    data => '<html><body>Moved permanently to <a href="' . $newurl . '">here</a></body></html>'
            );
        }

        last;
    }

    if(!$okname) {
        return (status => 404,
                type   => 'text/plain',
                data   => 'You requested information from ' . $requesthostname . ' which is unknown to this server. Maybe check your DNS settings?',
                );
    }

    return;
}

sub get_defaultwebdata {
    my ($self, $webdata) = @_;

    return unless defined($self->{defaultwebdata});
    foreach my $key (keys %{$self->{defaultwebdata}}) {
        my $val = $self->{defaultwebdata}->{$key};
        print STDERR "   ADDING DEFAULTWEBDATA: ", $key, " => ", $val, "\n";
        $webdata->{$key} = $val;
    }
    delete $self->{defaultwebdata};

    return;
}

1;
__END__

=head1 NAME

PageCamel::Web::Firewall::Hostname -

=head1 SYNOPSIS

  use PageCamel::Web::Firewall::Hostname;



=head1 DESCRIPTION



=head2 new



=head2 register



=head2 prefilter



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
