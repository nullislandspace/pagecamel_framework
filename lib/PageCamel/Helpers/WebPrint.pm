package PageCamel::Helpers::WebPrint;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.6;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(Exporter);
our @EXPORT = qw(webPrint); ## no critic (Modules::ProhibitAutomaticExportation)
use File::Binary;
use Time::HiRes qw(sleep);
use Errno qw(:POSIX);

sub webPrint {
    my ($ofh, @parts) = @_;
    
    my $brokenpipe = 0;
    local $SIG{PIPE} = sub { $brokenpipe = 1;};

    local $INPUT_RECORD_SEPARATOR = undef;
    binmode($ofh, ':bytes');

    my $full;
    foreach my $npart (@parts) {
        if(!defined($npart)) {
            #print STDERR "Empty npart in Webprint!\n";
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
    my $timeout = time + $timeoutthres;
    $ERRNO = 0;
    my $needprintdone = 0;
    while(1) {
        eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
            $written = syswrite($ofh, $full);
        };
        if($EVAL_ERROR) {
            print STDERR "Write error: $EVAL_ERROR\n";
            return 0;
        }
        if(!defined($written)) {
            $written = 0;
        }
        last if($written == length($full));
        #print STDERR "Sent $written bytes (", length($full) - $written, "remaining)\n";
        if($!{EWOULDBLOCK} || $!{EAGAIN}) { ## no critic (Variables::ProhibitPunctuationVars)
            if(!$shownlimitmessage) {
                print STDERR "Rate limiting output\n";
                $shownlimitmessage = 1;
            }
            $timeout = time + $timeoutthres;
            if(!$written) {
                sleep(0.01);
            }
        } elsif(0 && $brokenpipe) {
            print STDERR "webPrint write failure: SIGPIPE\n";
            return 0;
        } elsif($ofh->error || $ERRNO ne '') {
            print STDERR "webPrint write failure: $ERRNO / ", $ofh->opened, " / ", $ofh->error, "\n";
            return 0;
        }
        if($written) {
            $timeout = time + $timeoutthres;
            $full = substr($full, $written);
            $written = 0;
            next;
        }
        
        if($timeout < time) {
            print STDERR "***** webPrint TIMEOUT ****** $ERRNO\n";
            return 0;
        }
        
        sleep(0.01);
        $needprintdone = 1;
    }
    if($needprintdone) {
        #print STDERR "Webprint Done\n";
    }
    return 1;


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
