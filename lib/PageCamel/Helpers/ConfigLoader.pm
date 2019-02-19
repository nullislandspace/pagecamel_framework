package PageCamel::Helpers::ConfigLoader;
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
our @EXPORT= qw(LoadConfig); ## no critic (Modules::ProhibitAutomaticExportation)
use XML::Simple;


sub LoadConfig {
    my($fname, %options) = @_;

    if(!defined($fname) || $fname eq "") {
        croak("Can't load config file: No filename given!");
    }

    print "------- Parsing config file $fname ------\n";

    croak("$fname not found") unless(-f $fname);
    my $config = XMLin($fname, %options);

    my $newconfig;

    # Copy everything EXCEPT the modules list
    foreach my $key (keys %{$config}) {
        next if($key eq "module");
        $newconfig->{$key} = $config->{$key};
    }

    if(defined($config->{module})) {
        my @modules = @{$config->{module}};
        my @newmodules;
        foreach my $module (@modules) {
            if($module->{modname} ne "include") {
                push @newmodules, $module;
            } else {
                # Lets do some recursion
                my $extraconf = LoadConfig($module->{file}, %options);

                ## Add all "normal" keys to the config hash, replacing existing ones
                foreach my $ekey (keys %{$extraconf}) {
                    next if($ekey eq "module");
                    $newconfig->{$ekey} = $extraconf->{$ekey};
                }

                # now, add the modules to the current list (add in sequence)
                if(defined($extraconf->{module})) {
                    my @emodules = @{$extraconf->{module}};

                    # No need to iterate over it, should be clean already
                    push @newmodules, @emodules;
                }
            }
        }
        $newconfig->{module} = \@newmodules;
    }
    return $newconfig;
}

1;
__END__

=head1 NAME

PageCamel::Helpers::ConfigLoader - Load PageCamel XML config files

=head1 SYNOPSIS

  use PageCamel::Helpers::ConfigLoader;

=head1 DESCRIPTION

This loads PageCamel specific config files.

=head2 LoadConfig

Recursively load config files by handling the "include" module

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
