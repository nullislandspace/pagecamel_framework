package PageCamel::Web::ForceFavicon;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.8;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DangerSign;
use PageCamel::Helpers::FileSlurp qw(slurpBinFile);
use XML::Simple;
use JSON::XS;

sub new($proto, %config) {
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    if(!defined($self->{staticcache})) {
        print STDERR DangerSignUTF8();
        cluck('PageCamel::Web::ForceFavicon configured without reference to the StaticCache module, assuming default name!');
        $self->{staticcache} = 'staticcache';
    }

    return $self;
}


sub register($self) {
    $self->register_prefilter("prefilter");

    return;
}

# preparing our data needs to run AFTER StaticCache has loaded all files
sub finalcheck($self) {
    my $cacheh = $self->{server}->{modules}->{$self->{staticcache}};

    my $fname = $cacheh->getFilename($self->{favicon});
    if(!defined($fname)) {
        croak("File not found for URI " . $self->{favicon});
    }

    my $dirname = '';
    if($fname =~ /^(.*)\//) {
        $dirname = $1 . '/';
    }

    my $uridir = '' . $self->{favicon};
    $uridir =~ s/favicon\.ico$//;

    #print "favicon: $fname has basedir $dirname\n";

    my %map;

    my $xmlfname = $dirname . 'browserconfig.xml';
    if(-f $xmlfname) {
        #print "   Loading $xmlfname\n";
        my $xml = XMLin($xmlfname, ForceArray => [ 'tile']);

        if(defined($xml->{msapplication}->{tile})) {
            foreach my $tile (@{$xml->{msapplication}->{tile}}) {
                foreach my $key (keys %{$tile}) {
                    if(ref $tile->{$key} eq 'HASH' && defined($tile->{$key}->{src})) {
                        my $orig = '' . $tile->{$key}->{src};
                        my $modified = '' . $orig;
                        $modified =~ s/.*\///;
                        $modified = $uridir . $modified;
                        $map{$orig} = $modified;

                        # Also put in root path
                        $orig =~ s/.*\///g;
                        $map{'/' . $orig} = $modified;
                        
                        # ... and the default pagecamel path
                        $orig = '/pics/favicons/' . $orig;
                        $map{$orig} = $modified;

                    } 
                }
            }
        }
    }

    my $jsonfname = $dirname . 'site.webmanifest';
    if(-f $jsonfname) {
        #print "   Loading $jsonfname\n";
        my $jsondata = slurpBinFile($jsonfname);
        my $json = decode_json($jsondata);
        if(defined($json->{icons}) && ref $json->{icons} eq 'ARRAY') {
            foreach my $icon (@{$json->{icons}}) {
                #print Dumper($icon);
                if(defined($icon->{src})) {
                    my $orig = '' . $icon->{src};
                    my $modified = '' . $orig;
                    $modified =~ s/.*\///;
                    $modified = $uridir . $modified;
                    $map{$orig} = $modified;

                    # Also put in root path
                    $orig =~ s/.*\///g;
                    $map{'/' . $orig} = $modified;

                    # ... and the default pagecamel path
                    $orig = '/pics/favicons/' . $orig;
                    $map{$orig} = $modified;
                }
            }
        }

    }

    $map{'/favicon.ico'} = $self->{favicon};
    $map{'/pics/favicons/favicon.ico'} = $self->{favicon};

    $self->{map} = \%map;

    return;

}

sub prefilter($self, $ua) {
    if(!defined($ua->{url}) || $ua->{url} eq '') {
        return;
    }

    my $webpath = $ua->{url};

    if(defined($self->{map}->{$webpath})) {
        #print STDERR "***** MAPPING $webpath to ", $self->{map}->{$webpath}, "\n";
        $ua->{url} = $self->{map}->{$webpath};
        return;
    }

    return;
}
1;
__END__

=head1 NAME

PageCamel::Web::ForceFavicon -

=head1 SYNOPSIS

  use PageCamel::Web::PageCamelStats;



=head1 DESCRIPTION



=head2 new



=head2 crossregister



=head2 register



=head2 prefilter



=head2 postfilter



=head2 get_defaultwebdata



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
