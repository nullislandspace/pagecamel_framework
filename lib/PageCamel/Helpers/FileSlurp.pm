package PageCamel::Helpers::FileSlurp;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use base qw(Exporter);
our @EXPORT_OK = qw(slurpTextFile slurpBinFile writeBinFile slurpBinFilehandle slurpBinFilePart);
use File::Binary;


sub slurpTextFile {
    my $fname = shift;

    # Read in file in binary mode, slurping it into a single scalar.
    # We have to make sure we use binmode *and* turn on the line termination variable completly
    # to work around the multiple idiosynchrasies of Perl on Windows
    open(my $fh, "<", $fname) or croak($ERRNO);
    local $INPUT_RECORD_SEPARATOR = undef;
    binmode($fh);
    my $data = <$fh>;
    close($fh);

    # Convert line endings to a single format. This certainly is not perfect,
    # but it works in my case. So i don't f...ing care.
    $data =~ s/\015\012/\012/go;
    $data =~ s/\012\015/\012/go;
    $data =~ s/\015/\012/go;

    # Split the lines, which also removes the linebreaks
    my @datalines = split/\012/, $data;

    return @datalines;
}

sub slurpBinFile {
    my $fname = shift;

    # Read in file in binary mode, slurping it into a single scalar.
    # We have to make sure we use binmode *and* turn on the line termination variable completly
    # to work around the multiple idiosynchrasies of Perl on Windows
    open(my $fh, "<", $fname) or croak($ERRNO);
    local $INPUT_RECORD_SEPARATOR = undef;
    binmode($fh);
    my $data = <$fh>;
    close($fh);

    return $data;
}

sub slurpBinFilePart {
    my ($fname, $start, $len) = @_;

    # Read in file in binary mode, slurping it into a single scalar.
    # We have to make sure we use binmode *and* turn on the line termination variable completly
    # to work around the multiple idiosynchrasies of Perl on Windows
    my $fb = File::Binary->new($fname);
    $fb->seek($start);
    my $data = $fb->get_bytes($len);
    $fb->close();

    return $data;
}

sub slurpBinFilehandle {
    my $fh = shift;

    # Read in file in binary mode, slurping it into a single scalar.
    # We have to make sure we use binmode *and* turn on the line termination variable completly
    # to work around the multiple idiosynchrasies of Perl on Windows
    local $INPUT_RECORD_SEPARATOR = undef;
    binmode($fh);
    my $data = <$fh>;
    close($fh);

    return $data;
}

sub writeBinFile {
    my ($fname, $data) = @_;

    # Read in file in binary mode, slurping it into a single scalar.
    # We have to make sure we use binmode *and* turn on the line termination variable completly
    # to work around the multiple idiosynchrasies of Perl on Windows
    open(my $fh, ">", $fname) or croak($ERRNO);
    local $INPUT_RECORD_SEPARATOR = undef;
    binmode($fh);
    print $fh $data;
    close($fh);

    return 1;
}

1;
__END__

=head1 NAME

PageCamel::Helpers::FileSlurp -

=head1 SYNOPSIS

  use PageCamel::Helpers::FileSlurp;

=head1 DESCRIPTION

Helper to handle (mostly) binary files.

=head2 slurpTextFile

Slurp in a text file.

=head2 slurpBinFile

Slurp in a binary file.

=head2 slurpBinFilePart

Slurp in part of a binary file (given offset and length)

=head2 slurpBinFilehandle

Slurp in a binary file from a given filehandle.

=head2 writeBinFile

Write out a binary file.

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

Copyright (C) 2008-2016 by Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
