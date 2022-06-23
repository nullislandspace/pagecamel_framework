package PageCamel::Web::StaticCache;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.1;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::FileSlurp qw(slurpBinFile);
use IO::Compress::Gzip qw(gzip $GzipError);
use Digest::SHA1  qw(sha1_hex);
use PageCamel::Helpers::DateStrings;
use CSS::Minifier::XS;
use File::Type;

my $cachemodulecount = 0;
my @knownstaticmodules;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    my @tmp;
    if(!defined($self->{EXTRAINC})) {
        $self->{EXTRAINC} = \@tmp;
    }

    if(!defined($self->{sizelimit})) {
        $self->{sizelimit} = 1024 * 100; # Default 100 kilobyte per file
    }

    if(!defined($self->{public})) {
        $self->{public} = 0;
    }
    
    $cachemodulecount++;
    push @knownstaticmodules, $self->{modname};
    if($cachemodulecount > 1) {
        print STDERR "***** StaticCache configured more then once (", join(',', @knownstaticmodules), ")!\n";
        print STDERR "***** This is usually inefficient and can lead to duplicate files in memory, are you sure you want to do that?\n";
        print STDERR "***** Instead of multiple StaticCache instances, you can use PluginConfig to add more views!\n";
    }

    return $self;
}

sub addPath {
    my ($self, $basePath) = @_;

    push @{$self->{EXTRAINC}}, $basePath;

    return 1;
}

sub addView {
    my ($self, $dirpath, $urlpath) = @_;
    # add additional views to scan in all incs
    
    my %view = (
        path => $dirpath,
        webpath => $urlpath,
    );
    
    foreach my $v (@{$self->{view}}) {
        if($v->{path} eq $dirpath) {
            croak("Can't addView for $dirpath / $urlpath because dirpath $dirpath is already configured!");
        }
        
        if($v->{webpath} eq $urlpath) {
            croak("Can't addView for $dirpath / $urlpath because webpath $urlpath is already configured!");
        }
    }
    
    push @{$self->{view}}, \%view;
    
    # Also need to register the webpaths during register() call, because we can get additional paths during
    # the crossregister() loop
    $self->register_webpath($urlpath, "get", 'GET');
    if($self->{public}) {
        $self->register_public_url($urlpath);
    }
    
    return;
    
}

sub reload {
    my ($self, $ofh) = @_;

    if(!defined($ofh)) {
        $ofh = \*STDOUT;
    }

    # Empty cache
    my %files;
    $self->{cache} = \%files;

    $self->{reloadTime} = getFileDate();

    my $fcount = 0;

    my @DIRS = reverse @INC;
    if(defined($self->{EXTRAINC})) {
        push @DIRS, @{$self->{EXTRAINC}};
    }

    foreach my $view (@{$self->{view}}) {
        foreach my $bdir (@DIRS) {
            next if($bdir eq ".");
            my $fulldir = $bdir . '/' . $view->{path};
            print $ofh "   ** checking $fulldir \n";
            if(-d $fulldir) {
                #print $ofh "   **** loading extra static files\n";
                $fcount += $self->load_dir($fulldir, $view->{webpath}, $ofh);
            }
        }
    }
    
    $fcount += 0; # Dummy for debug breakpoint

    return;

}

sub load_dir {
    my ($self, $basedir, $basewebpath, $ofh) = @_;

    my $fcount = 0;
    my $ft = File::Type->new();

    print $ofh "StaticCache loading directory $basedir into $basewebpath...\n";

    opendir(my $dfh, $basedir) or croak($ERRNO);
    while((my $fname = readdir($dfh))) {
        next if($fname =~ /^\./);
        my $nfname = $basedir . "/" . $fname;
        if(-d $nfname) {
            # Got ourself a directory, go recursive
            $fcount += $self->load_dir($nfname, $basewebpath . $fname . "/", $ofh);
            next;
        }

        my $data = slurpBinFile($nfname);

        # Fill with default mime type (not always correct!)
        my $mtype = $ft->checktype_contents($data);

        # Now update MIME type from file extensions
        my ($kname, $type);
        if($fname =~ /(.*)\.([a-zA-Z0-9]+)$/) {
            ($kname, $type) = ($1, $2);
            if($type =~ /htm/i) {
                $mtype = "text/html";
            } elsif($type =~ /txt/i) {
                $mtype = "text/plain";
            } elsif($type =~ /^css$/i) {
                $mtype = "text/css";
            } elsif($type =~ /^wasm$/i) {
                $mtype = "application/wasm";
            } elsif($type =~ /js/i) {
                $mtype = "application/javascript";
            } elsif($type =~ /ico/i) {
                $mtype = "image/vnd.microsoft.icon";
            } elsif($type =~ /bmp/i) {
                $mtype = "image/bmp";
            } elsif($type =~ /png/i) {
                $mtype = "image/png";
            } elsif($type =~ /(jpg|jpeg|jpe)/i) {
                $mtype = "image/jpeg";
            }
        } else {
            # File without extension
            $kname = $fname;
        }

        if(!defined($mtype) || $mtype eq '') {
            # Whoops. Just use the most generic mime type available
            $mtype = 'application/octet-stream';
        }

        if(0) {
        #if(!$self->{isDebugging}) {
            # Only minify when not debugging for faster startup
            if($mtype eq "text/css") {
                my $miniok = 0;
                eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                    print $ofh ("   MINIFY $nfname\n");
                    my $tmp = CSS::Minifier::XS::minify($data);
                    print $ofh ("   MINIFY $nfname OK\n");
                    $data = $tmp;
                    $miniok = 1;
                };

                if(!$miniok) {
                    print $ofh "MINIFY ERROR: ", $EVAL_ERROR, "\n";
                }
            }
        }

        my $lastmodified = getLastModifiedWebdate($nfname);
        my $tmp = parseWebdate($lastmodified);
        $lastmodified = getWebdate($tmp);
        my %entry = (name   => $kname,
                    fullname=> $nfname,
                    type    => $mtype,
                    size    => length($data),
                    etag    => sha1_hex($self->{reloadTime} . sha1_hex($data)), # Force browser reload after pagecamel reload with timestamp
                    "Last-Modified" => $lastmodified,
                    disable_compression => 0,
                    );

        # !!! only store the data itself in RAM if the file is small enough !!!
        if($self->{isDebugging}) {
            #print $ofh "   !Debugging mode, will only cache metadata: $nfname\n";
        } elsif(!$self->{sizelimit}) {
            print $ofh "   !Size limit = 0, will only cache metadata: $nfname\n";
        } elsif($entry{size} > $self->{sizelimit}) {
            print $ofh "   !File too big (", $entry{size}, " > ", $self->{sizelimit}, "bytes), will only cache metadata: $nfname\n";
        } else {
            $entry{data} = $data;

            if($nfname !~ /\.(?:exe|msi|swf)/gio) {
                #print STDERR "Compressing $nfname\n";
                my $gzipped;
                if(gzip(\$data => \$gzipped)) {
                    if(length($gzipped) < length($data)) {
                        $entry{gzipdata} = $gzipped;
                    }
                }
            } else {
                $entry{disable_compression} = 1;
            }
        }

        $self->{cache}->{$basewebpath . $fname} = \%entry; # Store under full name
        $fcount++;
    }
    closedir($dfh);

    print $ofh "StaticCache loading directory $basedir into $basewebpath... done\n";
    return $fcount;
}


sub register {
    my $self = shift;

    # Also need to register the webpaths during addview() call, because we can get additional paths during
    # the crossregister loop
    foreach my $view (@{$self->{view}}) {
        $self->register_webpath($view->{webpath}, "get", 'GET');
        if($self->{public}) {
            $self->register_public_url($view->{webpath});
        }
    }

    if(defined($self->{sitemap}) && $self->{sitemap}) {
        $self->register_sitemap('sitemap');
    }
    return;
}

sub get {
    my ($self, $ua) = @_;

    my $name = $ua->{url};

    print STDERR "##########   $name\n";

    return (status  =>  404) unless defined($self->{cache}->{$name});

    my $lastetag = $ua->{headers}->{'If-None-Match'} || '';

    if(defined($self->{cache}->{$name}->{etag}) &&
            $lastetag ne "" &&
            $self->{cache}->{$name}->{etag} eq $lastetag) {
        # Resource matches the cached one in the browser, so just notify
        # we didn't modify it
        return(status   => 304);
    }

    my $lastmodified = $ua->{headers}->{'If-Modified-Since'} || '';

    if(defined($self->{cache}->{$name}->{'Last-Modified'}) &&
            $lastmodified ne "") {
        # Compare the dates
        my $lmclient = parseWebdate($lastmodified);
        my $lmserver = parseWebdate($self->{cache}->{$name}->{'Last-Modified'});
        if($lmclient >= $lmserver) {
            return(status   => 304);
        }
    }


    my %retpage = (status          =>  200,
            type            => $self->{cache}->{$name}->{type},
            data            => $self->{cache}->{$name}->{data},
            expires         => $self->{expires},
            cache_control   =>  $self->{cache_control},
            );

    if(defined($self->{cache}->{$name}->{data})) {
        # Deliver directly from cache RAM
        my $supportedcompress = $ua->{headers}->{'Accept-Encoding'} || '';
        if($supportedcompress =~ /gzip/io && defined($self->{cache}->{$name}->{gzipdata})) {
            $retpage{data} = $self->{cache}->{$name}->{gzipdata};
            $retpage{"Content-Encoding"} = "gzip";
            $self->extend_header(\%retpage, "Vary", "Accept-Encoding");
        } elsif($self->{cache}->{$name}->{disable_compression}) {
            $retpage{disable_compression} = $self->{cache}->{$name}->{disable_compression};
        }
    } else {
        # Bigger file. No RAM caching. Just load, send and forget
        $retpage{disable_compression} = 0;
        $retpage{data} = slurpBinFile($self->{cache}->{$name}->{fullname});
    }

    if(defined($self->{cache}->{$name}->{etag})) {
        $retpage{ETag} = $self->{cache}->{$name}->{etag};
    }

    if(defined($self->{cache}->{$name}->{"Last-Modified"})) {
        $retpage{"Last-Modified"} = $self->{cache}->{$name}->{"Last-Modified"};
    }

    return %retpage;
}

sub sitemap {
    my ($self, $sitemap) = @_;

    push @{$sitemap}, keys %{$self->{cache}};

    return;
}

1;
__END__

=head1 NAME

PageCamel::Web::StaticCache -

=head1 SYNOPSIS

  use PageCamel::Web::StaticCache;



=head1 DESCRIPTION



=head2 new



=head2 addPath



=head2 reload



=head2 load_dir



=head2 register



=head2 crossregister



=head2 get



=head2 sitemap



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
