package PageCamel::Web::HTTPCompression;
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
use IO::Compress::Gzip qw(gzip $GzipError);

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    if(!defined($self->{gzip})) {
        $self->{gzip} = 0;
    }

    return $self;
}

sub reload {
    my ($self) = shift;
    # Nothing to do.. in here, we only use the template and database module
    return;
}

sub register {
    my $self = shift;

    # only register if we actually have at least ONE compression type enabled
    if($self->{gzip}) {
        $self->register_postfilter("postfilter");
    }
    return;
}

sub postfilter {
    my ($self, $ua, $header, $result) = @_;

    # Ignore replies without content
    return if(!(defined($result->{data})));

    # Ignore content that already has a Content-Encoding
    return if(defined($result->{"Content-Encoding"}) || (defined($result->{"disable_compression"}) && $result->{"disable_compression"}));

    # We use an old internal bot that annouces http compression but doesn't actually
    # support it
    my $userAgent = $ua->{headers}->{'User-Agent'} || "Unknown";
    return if($userAgent =~ /CCOld\ Bot/o);

    my $supportedcompress = $ua->{headers}->{'Accept-Encoding'} || '';

    if($self->{gzip} && $supportedcompress =~ /gzip/io) {
        my $tmp;
        my $compressok = 0;
        my $compressstatus;

        eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
            my $tmpdata;
            if(is_utf8($result->{data})) {
                $tmpdata = encode_utf8($result->{data});
            } else {
                $tmpdata = $result->{data};
            }
            $compressstatus = gzip(\$tmpdata => \$tmp);
            $compressok = 1;
        };

        if(!$compressstatus || !$compressok) {
            print STDERR "HTTP COMPRESSION FAILURE: $EVAL_ERROR!\n";
        } else {
            if(length($tmp) < length($result->{data})) {
                #print STDERR "*****   ORIG: ", length($result->{data}), "  NEW: ", length($tmp), "  at ", $ua->{url} . "\n";
                $result->{data} = $tmp;
                $result->{"Content-Encoding"} = "gzip";
                $self->extend_header($result, "Vary", "Accept-Encoding");
            }
        }
    }

    return;
}

1;
__END__

=head1 NAME

PageCamel::Web::HTTPCompression -

=head1 SYNOPSIS

  use PageCamel::Web::HTTPCompression;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 postfilter



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
