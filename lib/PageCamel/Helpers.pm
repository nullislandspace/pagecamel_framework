package PageCamel::Helpers;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 2.1;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use base qw(Exporter);

#=!=START-AUTO-INCLUDES
use PageCamel::Helpers::AutoDialogs;
use PageCamel::Helpers::CSVFilter;
use PageCamel::Helpers::ClacksCache;
use PageCamel::Helpers::CommandHelper;
use PageCamel::Helpers::ConfigData;
use PageCamel::Helpers::ConfigLoader;
use PageCamel::Helpers::DBSerialize;
use PageCamel::Helpers::DataBlobs;
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::ENVResetHelper;
use PageCamel::Helpers::FTPSync;
use PageCamel::Helpers::FileSlurp;
use PageCamel::Helpers::Logging::Graphs;
use PageCamel::Helpers::Logo;
use PageCamel::Helpers::Mod43Checksum;
use PageCamel::Helpers::NeatLittleHelpers;
use PageCamel::Helpers::Padding;
use PageCamel::Helpers::Passwords;
use PageCamel::Helpers::PostgresDB;
use PageCamel::Helpers::Strings;
use PageCamel::Helpers::SystemSettings;
use PageCamel::Helpers::Translator;
use PageCamel::Helpers::URI;
use PageCamel::Helpers::UserAgent;
use PageCamel::Helpers::VoiceClient;
use PageCamel::Helpers::WSockFrame;
use PageCamel::Helpers::WebCommandQueue;
use PageCamel::Helpers::WebPrint;
#=!=END-AUTO-INCLUDES

1;
__END__

=head1 NAME

PageCamel::Helpers - pseudo base class

=head1 SYNOPSIS

  use PageCamel::Helpers;

=head1 DESCRIPTION

This pseudo module isn't used in running programs. It's main purpose is to provide
a version string for Makefile.pm, and to make some other tasks easier to
remember (like 'cpan install PageCamel::Helpers').


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
