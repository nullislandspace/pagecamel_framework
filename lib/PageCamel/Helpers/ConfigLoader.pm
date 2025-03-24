package PageCamel::Helpers::ConfigLoader;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.6;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---


use base qw(Exporter);
our @EXPORT= qw(LoadConfig); ## no critic (Modules::ProhibitAutomaticExportation)
use XML::Simple;
use PageCamel::Helpers::FileSlurp qw(slurpBinFile);

sub LoadConfig {
    my($fname, %options) = @_;

    my @paths;
    if(defined($ENV{'PC_CONFIG_PATHS'})) {
        push @paths, split/\:/, $ENV{'PC_CONFIG_PATHS'};
        #print "Found config paths:\n", Dumper(\@paths), " \n";
    } else {
        #print("PC_CONFIG_PATHS undefined, falling back to legacy mode\n");
        @paths = ('', 'configs/');
    }

    my $filedata;
    my $fullfname;
    foreach my $path (@paths) {
        if($path ne '' && $path !~ /\/$/) {
            $path .= '/';
        }
        $fullfname = $path . $fname;
        next unless (-f $fullfname);
        #print "   Loading config file $fullfname\n";

        $filedata = slurpBinFile($fullfname);

        foreach my $varname (keys %ENV) {
            next unless $varname =~ /^PC\_/;

            my $newval = $ENV{$varname};

            #print "$varname = $newval\n";
            $filedata =~ s/$varname/$newval/g;
        }

        last;
    }

    if(!defined($filedata) || $filedata eq "") {
        croak("Can't load config file $fname: Not found or empty!");
    }

    print "------- Parsing config file $fullfname ------\n";

    my $config = XMLin($filedata, %options);

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
            #if(!defined($module->{modname})) {
            #    print STDERR "\nModule is missing modname:\n", Dumper($module), "\n";
            #}
            if(!defined($module->{modname}) || $module->{modname} ne "include") {
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

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
