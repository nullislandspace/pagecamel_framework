package PageCamel::Helpers::ENVResetHelper;
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


use base qw(Exporter);
our @EXPORT= qw(ENVReset); ## no critic (Modules::ProhibitAutomaticExportation)


sub ENVReset {
    #if(!defined($ENV{HOME})) {
    #    print STDERR "HOME environment variable not set!\n";
    #    return;
    #}
    #
    #my $fname = $ENV{HOME} . '/.perl_env';
    my $fname = '/home/cavac/.perl_env';

    if(!(-f $fname)) {
        print STDERR "$fname does not exist!\n";
        return;
    }

    open(my $ifh, '<', $fname) or croak($ERRNO);
    while((my $line = <$ifh>)) {
        chomp $line;
        if($line =~ /^([A-Za-z0-9_]+)=(.*)/) {
            my ($key, $val) = ($1, $2);
            #print STDERR "Setting $key = $val\n";
            $ENV{$key} = $val;
        } else {
            print STDERR "Unparsable line $line\n";
        }
    }
    close $ifh;
    return;

}

1;
__END__

=head1 NAME

PageCamel::Helpers::ENVResetHelper - Load environment variables from a file.

=head1 SYNOPSIS

  use PageCamel::Helpers::ENVResetHelper;

=head1 DESCRIPTION

This is mostly used in debugging to simulate a specific environment, by resetting %ENV to specific values loaded from a file.

=head2 ENVReset

Load "/home/cavac/.perl_env" and parse it into %ENV

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
