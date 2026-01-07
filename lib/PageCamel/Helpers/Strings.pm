package PageCamel::Helpers::Strings;
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


use base qw(Exporter);
use PageCamel::Helpers::Padding qw(doSpacePad);
our @EXPORT_OK = qw(tabsToTable normalizeString elemNameQuote stripString humanFilesize windowsStringsQuote splitStringWithQuotes webSafeString encodeVNCString cutStrings lineWrap);


sub tabsToTable($txt, @lengths) {
    my @parts = split/\t/, $txt;
    my $newtext = "";
    foreach my $part (@parts) {
        my $len = shift @lengths || 5;
        $newtext .= doSpacePad($part, $len);
    }
    return $newtext;
}

# strip string of leading and trailing whitespace
sub stripString($val) {
    if(!defined($val)) {
        $val = '';
    }

    $val =~ s/^\s+//o;
    $val =~ s/\s+$//o;
    $val =~ s/\s+/\ /go;

    return $val;
}

# Removes all unneeded whitespace and non-word characters
sub normalizeString($val) {
    if(!defined($val)) {
        $val = '';
    }

    $val =~ s/\t/ /go;
    $val =~ s/^\s+//o;
    $val =~ s/\s+$//o;
    $val =~ s/\s+/\ /go;
    $val =~ s/[^\w\s]//go;

    return $val;
}

sub webSafeString($val) {
    if(!defined($val)) {
        $val = '';
    }

    $val =~ s/\t/ /go;
    $val =~ s/^\ +//o;
    $val =~ s/\ +$//o;
    $val =~ s/\ +/\ /go;
    $val =~ s/\r//go;
    $val =~ s/[^\w\s\!\?\.\:\,\;\-\_\#\$\€\°\|\@]/ /go;
    $val =~ s/\n/<br\/>/gso;

    return $val;
}

sub splitStringWithQuotes($val) {
    if(!defined($val)) {
        $val = '';
    }

    # Double backslash in search fields
    $val =~ s/\\/\\\\/g;

    $val =~ s/\t/ /go;
    $val =~ s/\'/"/go;
    $val =~ s/^\s+//o;
    $val =~ s/\s+$//o;
    $val =~ s/\s+/\ /go;

    my $inquotes = 0;
    my @strings;

    my $buffer = '';

    my @parts = split//, $val;
    while(scalar @parts) {
        my $part = shift @parts;
        if(!$inquotes) {
            if($part eq '"') {
                if(length($buffer)) {
                    push @strings, '' . $buffer;
                    $buffer = '';
                }
                $inquotes = 1;
                next;
            }

            if($part eq ' ') {
                if(length($buffer)) {
                    push @strings, '' . $buffer;
                    $buffer = '';
                }
                next;
            }

            $buffer .= $part;
        } else {
            if($part eq '"') {
                if(length($buffer)) {
                    push @strings, '' . $buffer;
                    $buffer = '';
                }
                $inquotes = 0;
            } else {
                $buffer .= $part;
            }
        }
    }

    if(length($buffer)) {
        push @strings, '' . $buffer;
    }

    return @strings;
}

sub elemNameQuote($val) {
    if(!defined($val)) {
        $val = '';
    }

    #$val = normalizeString($val);
    $val =~ s/\s/_/g;
    $val =~ s/[^\w\s]/_/g;

    return $val;
}

sub windowsStringsQuote($val) {
    if(!defined($val)) {
        $val = '';
    }

    $val =~ s/\ä/ae/go;
    $val =~ s/\ö/oe/go;
    $val =~ s/\ü/ue/go;
    $val =~ s/Ä/Ae/go;
    $val =~ s/Ö/Oe/go;
    $val =~ s/Ü/Ue/go;
    $val =~ s/ß/ss/go;
    $val =~ s/[^abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890\ ]//go;
    $val = normalizeString($val);

    return $val;
}

sub humanFilesize($size) {
    my $exp = 0;
    state $units = [qw(B KB MB GB TB PB)];
    for (@{$units}) {
        last if $size < 1024;
        $size /= 1024;
        $exp++;
    }
    return wantarray ? ($size, $units->[$exp]) : sprintf("%.2f %s", $size, $units->[$exp]);
}

# Encode a string for VNC session recording
sub encodeVNCString($val) {
    if(!defined($val)) {
        $val = '';
    }

    my $out = "";
    my @chars = split//, $val;

    foreach my $char (@chars) {
        my $num = ord($char);
        if($num == 10) {
            $out .= '\n';
        } elsif($num < 32 || $num > 122 || $num == 39 || $num == 34 || $num == 92 || $num == 96) {
            $out .= '\x' . unpack('H*', $char);
        } else {
            $out .= $char;
        }
    }

    return $out;
}

# 'cut -c' compatible implementation
sub cutStrings($definition, $seperator, @lines) {
    my @outlines;

    my @cuts;
    my @parts = split/\,/, $definition;
    foreach my $part (@parts) {
        my ($start, $finish, $len);

        if($part =~ /\-/) {
            ($start, $finish) = split/\-/, $part;
            $len = $finish - $start + 1;
        } else {
            $start = $part;
            $len = 1;
        }
        $start--;

        my %cut = (
            start => $start,
            len => $len,
        );
        push @cuts, \%cut;
    }

    foreach my $line (@lines) {
        chomp $line;
        my @outparts;
        foreach my $cut (@cuts) {
            push @outparts, substr $line, $cut->{start}, $cut->{len};
        }
        push @outlines, join($seperator, @outparts);
    }

    return @outlines;
}

# Line-wrap a string
sub lineWrap($val, $linelength) {
    if(!defined($val)) {
        $val = '';
    }

    my @lines;
    my $line = '';

    my @words = split/\s+/, $val;

    while(@words) {
        my $word = shift @words;

        # Need to shift word to the next line?
        if((length($line) + length($word) + 1) > $linelength) {
            if($line ne '') {
                push @lines, $line;
                $line = '';
            }
        }

        # Add space?
        if($line ne '') {
            $line .= ' ';
        }

        # If the word itself is too long for a single line, "unpack" it into line-length chunks, else just
        # add it to the current line
        if(length($word) > $linelength) {
            my @parts = unpack("(A" . $linelength . ")*", $word);
            push @lines, @parts;
        } else {
            $line .= $word;
        }
    }

    # Push the last (non-empty) line
    if($line ne '') {
        push @lines, $line;
    }

    return @lines;
}


1;
__END__

=head1 NAME

PageCamel::Helpers::Strings - various helpers for dealing with strings

=head1 SYNOPSIS

  use PageCamel::Helpers::Strings;

=head1 DESCRIPTION

This module houses a number of helper function to deal with strings.

=head2 tabsToTable

Changed a tab-separated string into space padded columns (used to print nice ASCII art tables)

=head2 stripString

Removes unneeded whitespace from a string.

=head2 normalizeString

Removes unneeded whitespace and non-word characters from a string.

=head2 webSafeString

Quote strings in a way to make them somewhat safer to use in web pages.

=head2 splitStringWithQuotes

Split strings on whitespace, but consider anything inbetween quotation marks a single string

=head2 elemNameQuote

Quote element names to make them websafe.

=head2 windowsStringsQuote

Special string quoting for some windows command line tools. Make sure we are only using a very limited character set.

=head2 humanFilesize

Turn a number into a more human readable filesize

=head2 encodeVNCString

Used in noVNC session recording.  Quote binary strings in a way to make them usable in a javascript file.

=head2 cutStrings

'cut -c' compatible implementation. Warning: Same as 'cut' is 1-indexed instead of 0-indexed

=head2 lineWrap

Wrap a string into multiple lines with a maximum length

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
