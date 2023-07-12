package PageCamel::Web::StaticCache;
#---AUTOPRAGMASTART---
use v5.36;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.2;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::FileSlurp qw(slurpBinFile);
use XML::Simple;
use IO::Compress::Gzip qw(gzip $GzipError);
use Digest::SHA1  qw(sha1_hex);
use PageCamel::Helpers::DateStrings;
use CSS::Minifier::XS;
use File::Type;
use POSIX;

my $cachemodulecount = 0;
my @knownstaticmodules;

sub new($proto, %config) {
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

sub addPath($self, $basePath) {

    push @{$self->{EXTRAINC}}, $basePath;

    return 1;
}

sub addView($self, $dirpath, $urlpath) {
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

sub reload($self, $ofh = undef) {

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

sub load_dir($self, $basedir, $basewebpath, $ofh, $dynamic=0) {
    my $fcount = 0;
    my $ft = File::Type->new();

    print $ofh "StaticCache loading directory $basedir into $basewebpath...\n";

    my @ignore;

    if(-f $basedir . '/pagecamel.xml') {
        # Special directives for static loading
        my $signore;
        ($signore, $dynamic) = $self->process_special_directives($basedir, $ofh);
        push @ignore, @{$signore};
        push @ignore, 'pagecamel.xml';
    }

    opendir(my $dfh, $basedir) or croak("$ERRNO");
    while((my $fname = readdir($dfh))) {
        next if($fname =~ /^\./); # Ignore hidden files and dirs

        next if(!$self->{isDebugging} && $fname =~ /\.ts$/); # Only deliver typescript files when debugging
        next if(!$self->{isDebugging} && $fname =~ /\.js\.map$/); # Only deliver TS map files when debugging
        next if($fname eq 'gettranslatekeys.pl');

        if(contains($fname, \@ignore)) {
            print $ofh "      Ignoring $fname in $basedir\n";
            next; # Ignore files specified in special directives
        }

        my $nfname = $basedir . "/" . $fname;
        if(-d $nfname) {
            # Got ourself a directory, go recursive
            $fcount += $self->load_dir($nfname, $basewebpath . $fname . "/", $ofh, $dynamic);
            next;
        }

        if($fname eq 'gettranslatekeys.dat') {
            open(my $ifh, '<', $nfname) or croak("$!");
            while((my $line = <$ifh>)) {
                chomp $line;
                if(length($line)) {
                    $self->{server}->{modules}->{templates}->addTranslateKey($line);
                }
            }
            close $ifh;
            next;
        }

        my $data = slurpBinFile($nfname);

        # Fill with default mime type (not always correct!)
        my $mtype = $ft->checktype_contents($data);

        # Now update MIME type from file extensions
        my ($kname, $type);
        if($fname =~ /\.js\.map$/) {
            $mtype = "application/json";
        } elsif($fname =~ /(.*)\.([a-zA-Z0-9]+)$/) {
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
            } elsif($type eq 'ts') {
                $mtype = "application/typescript";
            }
        } else {
            # File without extension
            $kname = $fname;
        }

        if(!defined($mtype) || $mtype eq '') {
            # Whoops. Just use the most generic mime type available
            $mtype = 'application/octet-stream';
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
                    dynamic => $dynamic,
                    );

        # !!! only store the data itself in RAM if the file is small enough !!!
        if($self->{isDebugging}) {
            #print $ofh "   !Debugging mode, will only cache metadata: $nfname\n";
        } elsif($dynamic) {
            #print $ofh "   !Dynamic file, will only cache metadata: $nfname\n";
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

sub process_special_directives($self, $basedir, $ofh) {
    my @ignore;

    my $directivefname = $basedir . '/pagecamel.xml';

    if(!-f $directivefname) {
        croak("Internal error: File $directivefname not found");
    }

    my $directives;
    my $loadok = 0;
    eval {
        $directives = XMLin($directivefname,
                            ForceArray => [ 'item' ],
                        );
        $loadok = 1;
    };

    if(!$loadok || !defined($directives)) {
        croak("Invalid directives file $directivefname: " . $EVAL_ERROR);
    }

    my $dynamic = 0;
    if($self->{isDebugging} && defined($directives->{dynamic}) && $directives->{dynamic}) {
        $dynamic = 1;
    }

    if(defined($directives->{ignore}->{item})) {
        push @ignore, @{$directives->{ignore}->{item}};
    }

    my $commandpath = "livecommands";
    if($self->{isDebugging}) {
        $commandpath = "debugcommands";
    }

    if(defined($directives->{$commandpath}->{item})) {
        my $currentwd = getcwd();
        chdir $basedir;
        my $newwd = getcwd();
        print $ofh   "  Changing working directory from $currentwd to $newwd to execute commands\n";

        foreach my $cmd (@{$directives->{$commandpath}->{item}}) {
            my $ok = $self->execute_external_command($cmd, $ofh);
            if(!$ok) {
                croak("Failed to execute external command");
            }
        }

        chdir $currentwd;

        if(getcwd() ne $currentwd) {
            croak("Changing WD back to $currentwd has failed!");
        }
    }


    return \@ignore, $dynamic;

}

sub execute_external_command($self, $cmd, $ofh) {

    print $ofh "       Executing command $cmd\n";

    my ($child_pid, $child_rc);

    unless ($child_pid = open(OUTPUT, '-|')) {
      open(STDERR, ">&STDOUT");
      {
          exec('/bin/true | ' . $cmd . ' || echo "PAGECAMEL_EXECUTE_ERROR"');
      }
      croak("ERROR: Could not execute program: $ERRNO");
    }
    print "Waiting for child $child_pid\n";
    waitpid($child_pid, 0);
    $child_rc = $CHILD_ERROR >> 8;

    my $ok = 1;
    while(my $line = <OUTPUT>) {
        chomp $line;
        if($line =~ /PAGECAMEL_EXECUTE_ERROR/) {
            $ok = 0;
            next;
        }
        print $ofh ":           $line\n";
    }
    eval {
        close(OUTPUT);
    };

    if(!$ok) {
        print "ERROR EXECUTING CHILD!\n";
    }

    return $ok;

}

sub register($self) {

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

sub get($self, $ua) {

    my $name = $ua->{url};

    print STDERR "##########   $name\n";

    return (status  =>  404) unless defined($self->{cache}->{$name});

    my $cachecontrol = $self->{cache_control}; 
    my $expires = $self->{expires}; 

    if($self->{cache}->{$name}->{dynamic}) {
        print STDERR "------ $name is a dynamic file, checking for newer version\n";
        $cachecontrol = "no-cache, no-store, must-revalidate";
        $expires = 'now';

        my $newlastmodified = getLastModifiedWebdate($self->{cache}->{$name}->{fullname});
        my $tmp = parseWebdate($newlastmodified);
        $newlastmodified = getWebdate($tmp);

        if($self->{cache}->{$name}->{"Last-Modified"} ne $newlastmodified) {
            print STDERR "------ $name is a dynamic file and has a newer version available, reloading metadata\n";
            my $data = slurpBinFile($self->{cache}->{$name}->{fullname});
            $self->{cache}->{$name}->{size} = length($data);
            $self->{cache}->{$name}->{"Last-Modified"} = $newlastmodified;
            $self->{cache}->{$name}->{etag} = sha1_hex($newlastmodified) . sha1_hex($data);
        }
    }


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
            expires         => $expires,
            cache_control   =>  $cachecontrol,
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

sub sitemap($self, $sitemap) {

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
