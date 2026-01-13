package PageCamel::Helpers::WebPrint;
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

use File::Binary;
use Time::HiRes qw(sleep time);
use Errno qw(:POSIX);
use IO::Select;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = bless \%config, $class;

    return $self;
}

sub write($self, $ofh, @parts) {
    my $brokenpipe = 0;
    local $SIG{PIPE} = sub { $brokenpipe = 1;};

    local $INPUT_RECORD_SEPARATOR = undef;
    binmode($ofh, ':bytes');

    my $full;
    foreach my $npart (@parts) {
        if(!defined($npart)) {
            #$self->debuglog("Empty npart in Webprint!");
            next;
        }
        if(is_utf8($npart)) {
            $full .= encode_utf8($npart);
        } else {
            $full .= $npart;
        }
    }

    my $shownlimitmessage = 0;

    my $timeoutthres = 20; # Need to be able to send at least one byte per 20 seconds

    # Output bandwidth-limited stuff, in as big chunks as possible
    if(!defined($full) || $full eq '') {
        return 1;
    }
    my $written = 0;
    my $endtime = time + $timeoutthres;
    $ERRNO = 0;
    my $select = IO::Select->new($ofh);

    while(length($full)) {
        # Calculate remaining timeout
        my $remaining = $endtime - time;
        if($remaining <= 0) {
            $self->debuglog("***** webPrint TIMEOUT ****** $ERRNO");
            return 0;
        }

        eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
            $written = syswrite($ofh, $full);
        };
        if($EVAL_ERROR) {
            $self->debuglog("Write error: $EVAL_ERROR");
            return 0;
        }

        if(defined($written) && $written > 0) {
            # Successfully wrote data, reset timeout and advance buffer
            $endtime = time + $timeoutthres;
            $full = substr($full, $written);
            next;
        }

        # Handle write errors
        if($ERRNO{EWOULDBLOCK} || $ERRNO{EAGAIN}) { ## no critic (Variables::ProhibitPunctuationVars)
            # Socket buffer full - wait for writability using select() instead of busy-wait
            if(!$shownlimitmessage) {
                #$self->debuglog("Rate limiting output");
                $shownlimitmessage = 1;
            }
            $select->can_write($remaining);  # Wait for socket to be writable
        } elsif(0 && $brokenpipe) {
            $self->debuglog("webPrint write failure: SIGPIPE");
            return 0;
        } elsif($ofh->error || $ERRNO ne '') {
            if($ERRNO !~ /Broken\ pipe/) {
                $self->debuglog("webPrint write failure: $ERRNO / ", $ofh->opened, " / ", $ofh->error);
            }
            return 0;
        }
    }
    return 1;
}

sub debuglog($self, @parts) {
    if(!defined($self->{reph})) {
        print STDERR "FALLBACK: ", getISODate(), " ", join('', @parts), "\n";
        return;
    }

    my $modname = $self->{reph};
    my $funcname = 'debuglog';
    if(defined($self->{rephfunc})) {
        $funcname = $self->{rephfunc};
    }
    $modname->$funcname(@parts);

    return;
}

1;
__END__

=head1 NAME

PageCamel::Helpers::WebPrint - helper to write to a tcp socket.

=head1 SYNOPSIS

  use PageCamel::Helpers::WebPrint;

=head1 DESCRIPTION

Writing to a TCP socket of a bit trickier than it's supposed to be. This helper tries data to a TCP socket, in multiple chunks if required. Handles some timeout conditions as well.

=head2 webPrint

Write data to a TCP socket.

=head1 IMPORTANT NOTE

This module is part of the PageCamel framework. Currently, only limited support
and documentation exists outside my DarkPAN repositories. This source is
currently only provided for your reference and usage in other projects (just
copy&paste what you need, see license terms below).

To see PageCamel in action and for news about the project,
visit my blog at L<https://cavac.at>.

=head1 AUTHOR

Rene Schickbauer, E<lt>cavac@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
