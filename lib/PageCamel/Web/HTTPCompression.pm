package PageCamel::Web::HTTPCompression;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.7;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use Module::Load::Conditional qw[check_install];
my $brotliavailable;
BEGIN {

    my $modname = 'IO::Compress::Brotli';
    if(check_install(module => $modname)) {
        $brotliavailable = 1;
        my $file = $modname;
        $file =~ s[::][/]g;
        $file .= '.pm';
        require $file;
        $modname->import();
    } else {
        $brotliavailable = 0;
    }
};

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;
use IO::Compress::Gzip qw(gzip $GzipError);

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    if(defined($ENV{PC_DISABLE_HTTPCOMPRESSION}) && $ENV{PC_DISABLE_HTTPCOMPRESSION}) {
        $self->{enableCompression} = 0;
    } else {
        $self->{enableCompression} = 1;
    }


    if(!defined($self->{gzip})) {
        $self->{gzip} = 0;
    }

    if(!defined($self->{brotli})) {
        $self->{brotli} = 0;
    }

    if(!$brotliavailable) {
        $self->{brotli} = 0;
    }

    return $self;
}

sub reload($self) {
    # Nothing to do.. in here, we only use the template and database module
    return;
}

sub register($self) {
    if(!$self->{enableCompression}) {
        return;
    }

    # only register if we actually have at least ONE compression type enabled
    if($self->{gzip} || $self->{brotli}) {
        $self->register_postfilter("postfilter");
    }
    return;
}

sub postfilter($self, $ua, $header, $result) {

    # Ignore replies without content
    return if(!(defined($result->{data})));

    # Ignore content that already has a Content-Encoding
    return if(defined($result->{"Content-Encoding"}) || (defined($result->{"disable_compression"}) && $result->{"disable_compression"}));

    # Ignore clients that don't support compression
    return if(!defined($ua->{headers}->{'Accept-Encoding'}) || $ua->{headers}->{'Accept-Encoding'} eq '');

    my $supportedcompress = $ua->{headers}->{'Accept-Encoding-Array'};

    my $iscompressed = 0;

    if($self->{brotli} && contains('br', $supportedcompress)) {
        my $tmp;
        my $compressok = 0;

        eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
            my $tmpdata;
            if(is_utf8($result->{data})) {
                $tmpdata = encode_utf8($result->{data});
            } else {
                $tmpdata = $result->{data};
            }
            $tmp = bro($tmpdata, 5); # Use relatively quick (but inefficient) compression factor for just-in-time compression
            $compressok = 1;
        };

        if(!$compressok) {
            #print STDERR "HTTP BROTLI COMPRESSION FAILURE: $EVAL_ERROR!\n";
        } else {
            if(length($tmp) < length($result->{data})) {
                #print STDERR "*****  BROTLI ORIG: ", length($result->{data}), "  NEW: ", length($tmp), "  at ", $ua->{url} . "\n";
                $result->{data} = $tmp;
                $result->{"Content-Encoding"} = "br";
                $self->extend_header($result, "Vary", "Accept-Encoding");
                $iscompressed = 1;
            }
        }
    }
    if(!$iscompressed && $self->{gzip} && contains('gzip', $supportedcompress)) {
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
            $compressstatus = gzip(\$tmpdata => \$tmp, '-Level' => 3); # Use very fast (but inefficient) compression for dynamic stuff
            $compressok = 1;
        };

        if(!$compressstatus || !$compressok) {
            print STDERR "HTTP GZIP COMPRESSION FAILURE: $EVAL_ERROR!\n";
        } else {
            if(length($tmp) < length($result->{data})) {
                #print STDERR "*****  GZIP ORIG: ", length($result->{data}), "  NEW: ", length($tmp), "  at ", $ua->{url} . "\n";
                $result->{data} = $tmp;
                $result->{"Content-Encoding"} = "gzip";
                $self->extend_header($result, "Vary", "Accept-Encoding");
                $iscompressed = 1;
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
