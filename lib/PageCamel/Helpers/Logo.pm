package PageCamel::Helpers::Logo;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp;
our $VERSION = 2.4;
use autodie qw( close );
use Array::Contains;
use utf8;
#---AUTOPRAGMAEND---


use base qw(Exporter);
our @EXPORT= qw(PageCamelLogo); ## no critic (Modules::ProhibitAutomaticExportation)


my @lines = (
    '',
    '*************************************************************************',
    '',
    '                                                          //             ',
    '  ____                   ____                     _     _oo\             ',
    ' |  _ \ __ _  __ _  ___ / ___|__ _ _ __ ___   ___| |   (__/ \  _  _      ',
    ' | |_) / _` |/ _` |/ _ \ |   / _` | ´_ ` _ \ / _ \ |      \  \/ \/ \     ',
    ' |  __/ (_| | (_| |  __/ |__| (_| | | | | | |  __/ |      (         )\   ',
    ' |_|   \__,_|\__, |\___|\____\__,_|_| |_| |_|\___|_|       \_______/  \  ',
    '             |___/                                          [[] [[]      ',
    '                                                            [[] [[]     ',
    '',
    ' Application: APPNAME',
    ' Version: VERSION',
    '',
    ' This application is part of the PAGECAMEL Framework, developed',
    ' under the Artistic license',
    '*************************************************************************',
    '',
);

sub PageCamelLogo {
    my ($appname, $version) = @_;

    my @xlines = @lines; # Do NOT work on original data set
    foreach my $line (@xlines) {
        $line =~ s/APPNAME/$appname/g;
        $line =~ s/VERSION/$version/g;
        print $line, "\n";
    }
    print "\n";
    #sleep(1); # Workaround: Serialize possible error output in Kommodo
    return 1;
}

1;
__END__

=head1 NAME

PageCamel::Helpers::Logo - print the PageCamel logo

=head1 SYNOPSIS

  use PageCamel::Helpers::Logo;

=head1 DESCRIPTION

Prints the standardized PageCamel logo, including application name and version.

=head2 PageCamelLogo

Print the logo.

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
