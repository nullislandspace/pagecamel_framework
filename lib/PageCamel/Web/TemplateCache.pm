package PageCamel::Web::TemplateCache;
#---AUTOPRAGMASTART---
use 5.020;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English qw(-no_match_vars);
use Carp;
our $VERSION = 1;
use Fatal qw( close );
use Array::Contains;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use Template;
use HTML::Entities;
use IO::Compress::Gzip qw(gzip $GzipError);
use Digest::SHA1  qw(sha1_hex);
use PageCamel::Helpers::DateStrings;
use Time::HiRes qw(sleep);
use PageCamel::Helpers::Padding qw(trim);

use PageCamel::Helpers::FileSlurp qw(slurpBinFile);
use PageCamel::Helpers::Strings qw(stripString);
use PageCamel::Helpers::AutoDialogs;
use JavaScript::Minifier qw(minify);

my $templatemodulecount = 0;
my @knowntemplatemodules;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    $self->{processor} = Template->new({
        PLUGINS => {
            tr => 'PageCamel::Web::TT::Translate',
        },
    });
    if(!defined($self->{processor})) {
        croak("Failed to load template engine");
    }

    my @tmp;
    if(!defined($self->{EXTRAINC})) {
        $self->{EXTRAINC} = \@tmp;
    }
    
    if(!defined($self->{uninline})) {
        croak("UNINLINE mode mandatory");
    }
    my %uninlinefiles;
    $self->{uninlinefiles} = \%uninlinefiles;

    $templatemodulecount++;
    push @knowntemplatemodules, $self->{modname};
    if($templatemodulecount > 1) {
        print STDERR "***** TemplateCache configured more then once (", join(',', @knowntemplatemodules), ")!\n";
        print STDERR "***** This is usually inefficient and can lead to duplicate files in memory, are you sure you want to do that?\n";
        print STDERR "***** Instead of multiple TemplateCache instances, you can use PluginConfig to add more views!\n";
    }

    return $self;
}

sub addPath {
    my ($self, $basePath) = @_;

    push @{$self->{EXTRAINC}}, $basePath;

    return 1;
}

sub addView {
    my ($self, $path, $base) = @_;
    
    foreach my $v (@{$self->{view}}) {
        if($v->{base} eq $base) {
            croak("Can't addView for $base / $path because base $base is already configured!");
        }
        
        if($v->{path} eq $path) {
            croak("Can't addView for $base / $path because path $path is already configured!");
        }
    }

    my %view = (
        base    => $base,
        path    => $path,
    );

    push @{$self->{view}}, \%view;

    return 1;

}

sub reload {
    my ($self, $ofh) = @_;
    if(!defined($ofh)) {
        $ofh = \*STDOUT;
    }
    delete $self->{cache} if defined $self->{cache};

    my %files;
    
    $self->{reloadwarnings} = [];
    $self->{reloaderrors} = [];

    my @DIRS = reverse @INC;
    if(defined($self->{EXTRAINC})) {
        push @DIRS, @{$self->{EXTRAINC}};
    }

    foreach my $view (@{$self->{view}}) {
        foreach my $bdir (@DIRS) {
            next if($bdir eq "."); # Load "./" at the end
            my $fulldir = $bdir . "/" . $view->{path};
            print $ofh "   ** checking $fulldir \n";
            if(-d $fulldir) {
                #print $ofh "   **** loading extra template files\n";
                $self->load_dir($fulldir, $view->{base}, \%files);
            }
        }
        { # Load "./"
            my $fulldir = $view->{path};
            print $ofh "   ** checking $fulldir \n";
            if(-d $fulldir) {
                #print $ofh "   **** loading local template files\n";
                $self->load_dir($fulldir, $view->{base}, \%files);
            }
        }
    }
    
    if(@{$self->{reloadwarnings}} || @{$self->{reloaderrors}}) {
        sleep(0.5);
    }
    
    foreach my $errline (@{$self->{reloadwarnings}}) {
        print STDERR "TEMPLATE WARNING: $errline\n";
    }
    foreach my $errline (@{$self->{reloaderrors}}) {
        print STDERR "TEMPLATE ERROR: $errline\n";
    }
    if(@{$self->{reloaderrors}}) {
        croak("Encountered errors in Template loading.");
    }
    
    if(@{$self->{reloadwarnings}}) {
        sleep(0.5);
    }

    $self->{cache} = \%files;
    return;
}

sub load_dir {
    my ($self, $dir, $base, $files) = @_;

    $base =~ s/^\///o;
    $base =~ s/\/$//o;

    opendir(my $dfh, $dir) or croak($ERRNO);
    while((my $fname = readdir($dfh))) {
        next if($fname !~ /\.tt$/);
        my $nfname = $dir . "/" . $fname;
        my $kname = $base . '/' . $fname;
        $kname =~ s/^\///o;
        $kname =~s /\.tt$//g;
        my $data = slurpBinFile($nfname);
        $data = $self->do_uninline($data, $kname, $nfname);
        $files->{$kname} = $data;
    }
    closedir($dfh);
    return;
}

sub register {
    my $self = shift;
    
    $self->register_webpath($self->{uninline}->{webpath} . '/static', 'get_uninline_static', 'GET');
    $self->register_webpath($self->{uninline}->{webpath} . '/dynamic', 'get_uninline_dynamic', 'GET');
    
    return;
}

sub get {
    my ($self, $name, $uselayout, %webdata) = @_;
    return unless defined($self->{cache}->{$name});

    # Run a prerender callback on our webdata, so modules
    # like the "views" module can add missing data depending
    # on what the current module put into webdata
    if(!defined($webdata{_templatecache_prerender_done}) || $webdata{_templatecache_prerender_done} != 1) {
        $self->{server}->prerender(\%webdata);
        $webdata{_templatecache_prerender_done} = 1;
    }

    my $fullpage;

    my $layoutname = $self->{layout};
    if(defined($webdata{MobileDesktopClientMode}) && $webdata{MobileDesktopClientMode} eq 'mobile') {
        $layoutname = $self->{mobilelayout};
    }
    if(defined($webdata{UserLayout}) && defined($self->{cache}->{$webdata{UserLayout}})) {
        $layoutname = $webdata{UserLayout};
    }

    if($uselayout) {
        my $debugname;
        if(defined($self->{cache}->{$uselayout})) {
            $debugname = $uselayout;
            $fullpage = $self->{cache}->{$uselayout} . ''; # Make sure we COPY
        } else {
            $debugname = $layoutname;
            $fullpage = $self->{cache}->{$layoutname} . ''; # Make sure we COPY 
        }
        my $page = $self->{cache}->{$name} . ''; # Make sure we COPY
        
        $self->makeDynamicScript(\$page, \%webdata, $name);
        $self->makeDynamicScript(\$fullpage, \%webdata, $debugname);
        
        $fullpage =~ s/XX_BODY_XX/$page/;
    } else {
        $fullpage = $self->{cache}->{$name} . ''; # Make sure we COPY
        
        $self->makeDynamicScript(\$fullpage, \%webdata, $name);
    }

    if($self->{isDebugging} && $name =~ /login/) {
        open(my $tofh, '>', '/home/cavac/temp/fullpage_before_tt.txt') or croak($ERRNO);
        print $tofh $fullpage;
        close $tofh;
    }

    my $output;
    $fullpage = '[% USE tr %]' . $fullpage; # Make sure we load the translation plugin
    $self->{processor}->process(\$fullpage, \%webdata, \$output);
    if(defined($self->{processor}->{_ERROR}) &&
            $self->{processor}->{_ERROR}) {
        $self->{LastError} = $self->{processor}->{_ERROR};
        print STDERR $self->{processor}->{_ERROR}->[1] . "\n";
    }

    if($self->{isDebugging} && defined($output) && $name =~ /login/) {
        open(my $tofh, '>', '/home/cavac/temp/fullpage_after_tt.txt') or croak($ERRNO);
        print $tofh $output;
        close $tofh;
    }
    return $output;
}

sub render_partials {
    my ($self, $name, %webdata) = @_;
    return unless defined($self->{cache}->{$name});

    # Run a prerender callback on our webdata, so modules
    # like the "views" module can add missing data depending
    # on what the current module put into webdata
    if(!defined($webdata{_templatecache_prerender_done}) || $webdata{_templatecache_prerender_done} != 1) {
        $self->{server}->prerender(\%webdata);
        $webdata{_templatecache_prerender_done} = 1;
    }

    my $fullpage = $self->{cache}->{$name} . ''; # Make sure we COPY
    $self->makeDynamicScript(\$fullpage, \%webdata, $name);
    
    my $output;
    $fullpage = '[% USE tr %]' . $fullpage; # Make sure we load the translation plugin
    $self->{processor}->process(\$fullpage, \%webdata, \$output);
    if(defined($self->{processor}->{_ERROR}) &&
            $self->{processor}->{_ERROR}) {
        $self->{LastError} = $self->{processor}->{_ERROR};
        print STDERR $self->{processor}->{_ERROR}->[1] . "\n";
    }

    return $output;
}


sub do_uninline {
    my ($self, $data, $kname, $fname) = @_;
        
    my @newlines;
    
    my ($preparseddata, $autodialogjs, $autodialoghtml) = $self->parseAutoDialogs($fname, $data);
    
    my @oldlines = split/\n/, $preparseddata;
    
    my @jslines;
    my $linecount = 0;
    
    my $jsmode = 0;
    my $scriptcount = 0;
    my $dynamicmode = 0;
    my @scriptstarts;
    my $isemptyline = 0;
    
    my @eventhandlerlines;
    my $lncount;
    
    my $jsname_static = $self->{uninline}->{webpath} . '/static/' . $kname . '.js';
    my $jsname_dynamic = $self->{uninline}->{webpath} . '/dynamic/' . $kname;
    
    # If we overwrite a file, (loading a project specific one for example), make sure we clean out everything first
    delete $self->{uninlinefiles}->{$jsname_static};
    delete $self->{uninlinefiles}->{$jsname_dynamic};
    
    
    my $isautodialogmode = 0;
    my $autodialoglines = 0;
            
    foreach my $line (@oldlines) {
        chomp $line;
        $linecount++;
        
        my $temp = trim($line);
        next if($temp eq '');
        if($temp ne '') {
            $isemptyline = 0;
        } else {
            if($isemptyline) {
                # remove redundant empty lines
                next;
            }
            $isemptyline = 1;
        }
        $line = $temp;
        
        if($line =~ /\[\%\ +dialog\./ && $line !~ /\[\%\ +dialog\.getFormsHTML/) {
            $isautodialogmode = 1;
            $autodialoglines = 1;
            $dynamicmode = 1; # Need dynamic mode
            push @{$self->{reloadwarnings}}, "Autoform in $fname line $linecount forces dynamicmode";
        }
        
        if($autodialoglines) {
            # Copy to JS *and* to HTML
            push @newlines, $line;
            push @jslines, $line;
            if($line =~ /\%\]$/) {
                $autodialoglines = 0;
            }
            next;
        }
        
        if($line =~ /eval.*?\((.*?)\)/i) {
            my ($args) = ($1, $2);
            if($args =~ /\'/ || $args =~ /\"/) {
                push @{$self->{reloaderrors}}, "unsafe string eval in $fname line $linecount";
            }
        }
        if($line =~ /(settimeout|setinterval).*?\((.*?)\)/i) {
            my ($funcname, $args) = ($1, $2);
            if($args =~ /\'/ || $args =~ /\"/) {
                push @{$self->{reloaderrors}}, "unsafe string eval in $funcname in $fname line $linecount";
            }
        }
        
        if($line =~ /(?:\s+|^)style\s*\=\s*\"/i || $line =~ /\<style/i) {
            if($line !~ /DISABLE_INLINE_CSS_WARNINGS/) {
                push @{$self->{reloaderrors}}, "unsafe inline CSS in$fname line $linecount";
            }
        }
        
        # uninline onfoo callbacks in html tags
        my $matchfound = 1;
        while($matchfound) {
            if(!$jsmode && $line =~ /(\s+|^)on([a-z]+?)\=\"(.+?)\"/i) {
                my (undef, $eventtype, $command) = ($1, lc $2, $3);
                #push @{$self->{reloadwarnings}}, "unsafe-inline tag on$eventtype in $fname line $linecount with command ->$command<-";
                
                if($command =~ /\[\%/) {
                    $dynamicmode = 1;
                }
                
                my $evname = $self->gen_eventhandlername();
                my $evtag = 'pagecamelevent="' . $evname . '"';
                $line =~ s/(\s+|^)on[a-zA-Z]+?\=\".+?\"/ $evtag/i;
                push @eventhandlerlines, "\$('[pagecamelevent=\"$evname\"]').on('$eventtype', function() {",
                                        "$command;",
                                        "});";
                
            } else {
                $matchfound = 0;
            }
        }
        
        if($line =~ /\<script.*src\=/) {
            push @newlines, $line;
            next;
        } elsif($line =~ /\<script/) {
            if($jsmode) {
                push @{$self->{reloaderrors}}, "Nested script tags in $fname line $linecount";
            }
            if($line =~ /<\/script/) {
                push @{$self->{reloaderrors}}, "Unhandled one-liner in $fname line $linecount";
            }
            push @scriptstarts, $linecount;
            push @newlines, "XX_TT_SCRIPT_HERE_XX";
            $jsmode = 1;
            next;
        }
        
        if($line =~ /<\/script/) {
            if(!$jsmode) {
                push @{$self->{reloaderrors}}, "unexpected script closing tag in $fname line $linecount";
            }
            $scriptcount++;
            $jsmode = 0;
            
            if(!@jslines) {
                push @{$self->{reloadwarnings}}, "Empty script tag $1 in $fname line $linecount";
            }
            
            next;
        }
        
        if($jsmode) {
            if($line =~ /\[\%/) {
                $dynamicmode = 1;
            }
            push @jslines, $line;
        } else {
            push @newlines, $line;
        }
    }
    
    # Insert event handler lines into js file
    if(@eventhandlerlines) {
        # Try to auto-create the XX_ON_EVENT_HANDLERS_XX line if it does not exist yet
        my $xxlinefound = 0;
        foreach my $line (@jslines) {
            if($line eq 'XX_ON_EVENT_HANDLERS_XX') {
                $xxlinefound = 1;
                last;
            }
        }
        # Ok not found, try to insert it into the extraOnLoad function
        $lncount = 0;
        if(!$xxlinefound) {
            foreach my $line (@jslines) {
                $lncount++;
                if($line =~ /function\ +extraonload/i) {
                    splice @jslines, $lncount, 0, 'XX_ON_EVENT_HANDLERS_XX';
                    last;
                }
            }
        }
        
        # Now insert the eventhandler lines whereever we find the XX_ON_EVENT_HANDLERS_XX tag
        my $evinsertok = 0;
        $lncount = 0;
        foreach my $jsline (@jslines) {
            if($jsline eq 'XX_ON_EVENT_HANDLERS_XX') {
                $jslines[$lncount] = join("\n", @eventhandlerlines);
                $evinsertok = 1;
                last;
            }
            $lncount++;
        }
        if(!$evinsertok) {
            push @{$self->{reloaderrors}}, "no tag to place uninlined eventhandlers in $fname";
        }
    }
    
    # Sanity check if there are still XX_ON_EVENT_HANDLERS_XX tags left, and error out if there are
    foreach my $jsline (@jslines) {
        if($jsline =~ /XX_ON_EVENT_HANDLERS_XX/) {
            push @{$self->{reloaderrors}}, "unused XX_ON_EVENT_HANDLERS_XX tag in $fname";
            last;
        }
    }

    if(@jslines) {
        my $scripttag;
        if($dynamicmode) {
            $scripttag = '<script type="text/javascript" src="%>%DYNAMICJSFILE%|%' . $jsname_dynamic .
                            '%<%" generatedfrom="' . $kname . '"></script>';
        } else {
            $scripttag = '<script type="text/javascript" src="' . $jsname_static . '[% URLReloadPostfix %]"></script>';
        }
        my $xxlinefound = 0;
        $lncount = 0;
        foreach my $line (@newlines) {
            if($line eq 'XX_TT_SCRIPT_HERE_XX') {
                $newlines[$lncount] = $scripttag;
                $xxlinefound = 1;
                last;
            }
            $lncount++;
        }
        if(!$xxlinefound) {
            push @{$self->{reloaderrors}}, "Internal error: XX_TT_SCRIPT_HERE_XX not found in $fname";
        }
        
        my $jsdata = join("\n", @jslines);
        if(!$dynamicmode && !$self->{isDebugging}) {
            my $minified = minify(input => $jsdata);
            if(length($minified) < length($jsdata)) {
                print "   Minified $jsname_static, saved ", length($jsdata) - length($minified), " bytes\n";
                $jsdata = $minified;
            }
        }
        my $etag = sha1_hex(getFileDate() . sha1_hex($jsdata));
        
        my $lastmodified = getLastModifiedWebdate($fname);
        my $tmp = parseWebdate($lastmodified);
        $lastmodified = getWebdate($tmp);
        
        my %filedata = (
            type    => "application/javascript",
            etag    => $etag,
            uncompresseddata    => $jsdata,
            'Last-Modified'     => $lastmodified,
        );

        if($dynamicmode) {
            $filedata{uncompresseddata} = '[% USE tr %]' . $filedata{uncompresseddata} . "\n";
            $self->{uninlinefiles}->{$jsname_dynamic}= \%filedata;
        } else {
            my $gzipped;
            if(gzip(\$jsdata => \$gzipped)) {
                if(length($gzipped) < length($jsdata)) {
                    $filedata{gzipdata} = $gzipped;
                }
            }
            $self->{uninlinefiles}->{$jsname_static}= \%filedata;
        }
    }
  
    if($scriptcount > 1) {
        push @{$self->{reloaderrors}}, "Multiple (" . scalar @scriptstarts . ") inline script tags in $fname in lines " . join(', ', @scriptstarts);
    }

    if($dynamicmode) {
        push @{$self->{reloadwarnings}}, "TT Dynamic mode in $fname";
    }
    
    my $newdata = join("\n", @newlines);
    
    return $newdata;
}

sub get_uninline_static {
    my ($self, $ua) = @_;
    
    my $fname = $ua->{url};
    
    if(!defined($self->{uninlinefiles}->{$fname})) {
        return (status => 404);
    }

    my $lastetag = $ua->{headers}->{'If-None-Match'} || '';
    
    if(defined($self->{uninlinefiles}->{$fname}->{etag}) &&
            $lastetag ne "" &&
            $self->{uninlinefiles}->{$fname}->{etag} eq $lastetag) {
        # Resource matches the cached one in the browser, so just notify
        # we didn't modify it
        return(status   => 304);
    }

    my $lastmodified = $ua->{headers}->{'If-Modified-Since'} || '';

    if(defined($self->{uninlinefiles}->{$fname}->{'Last-Modified'}) &&
            $lastmodified ne "") {
        # Compare the dates
        my $lmclient = parseWebdate($lastmodified);
        my $lmserver = parseWebdate($self->{uninlinefiles}->{$fname}->{'Last-Modified'});
        if($lmclient >= $lmserver) {
            return(status   => 304);
        }
    }
    
    my %retpage = (
        status          =>  200,
        type            => $self->{uninlinefiles}->{$fname}->{type},
        etag            => $self->{uninlinefiles}->{$fname}->{etag},
        expires         => $self->{uninline}->{expires},
        cache_control   =>  $self->{uninline}->{cache_control},
    );

    my $supportedcompress = $ua->{headers}->{'Accept-Encoding'} || '';
    if($supportedcompress =~ /gzip/io && defined($self->{uninlinefiles}->{$fname}->{gzipdata})) {
        $retpage{data} = $self->{uninlinefiles}->{$fname}->{gzipdata};
        $retpage{"Content-Encoding"} = "gzip";
        $self->extend_header(\%retpage, "Vary", "Accept-Encoding");
    } else {
        $retpage{data} = $self->{uninlinefiles}->{$fname}->{uncompresseddata};
        $retpage{disable_compression} = 1;
    }
    
    if(defined($self->{uninlinefiles}->{$fname}->{"Last-Modified"})) {
        $retpage{"Last-Modified"} = $self->{uninlinefiles}->{$fname}->{"Last-Modified"};
    }
    
    return %retpage;
}

sub get_uninline_dynamic {
    my ($self, $ua) = @_;
    
    my $fname = $ua->{url};
    
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    
    my $selsth;

    if(0 && !$self->{isDebugging}) {    
        $selsth = $dbh->prepare_cached("DELETE FROM templatecache_dynamic_scripting
                                        WHERE webpath = ?
                                        AND valid_until >= now()
                                        RETURNING *;")
                or croak($dbh->errstr);
    } else {
        $selsth = $dbh->prepare_cached("SELECT * FROM templatecache_dynamic_scripting
                                        WHERE webpath = ?
                                        AND valid_until >= now()")
                or croak($dbh->errstr);
    }
    
    
    
    if(!$selsth->execute($fname)) {
        $dbh->rollback;
        return (status => 500);
    }
    my $line = $selsth->fetchrow_hashref;
    $selsth->finish;
    $dbh->commit;
    
    if(!defined($line->{scriptdata})) {
        return (status => 404);
    }
    
    
    my %retpage = (
        status          =>  200,
        type            => 'application/javascript',
        expires         => 0,
        cache_control   =>  'no-store, no-cache, must-revalidate',
        pagecamel_debug_info => 'Source template: ' . $line->{source_template},
    );

    my $iszipped = 0;
    my $supportedcompress = $ua->{headers}->{'Accept-Encoding'} || '';
    if($supportedcompress =~ /gzip/io) {
        my $gzipped;
        my $raw = $line->{scriptdata};
        if(gzip(\$raw => \$gzipped)) {
            if(length($gzipped) < length($raw)) {
                $iszipped = 1;
                $retpage{data} = $gzipped;
                $retpage{"Content-Encoding"} = "gzip";
                $self->extend_header(\%retpage, "Vary", "Accept-Encoding");
            }
        }
    }
        
        
    if(!$iszipped) {
        $retpage{data} = $line->{scriptdata};
        $retpage{disable_compression} = 1;
    }
    
    return %retpage;
}

sub makeDynamicScript {
    my ($self, $page, $webdata, $templatename) = @_;
    
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    
    my $dynsource;
    #   %>%DYNAMICJSFILE%|%' . $jsname_dynamic . '%<%
    if($$page =~ /\%\>\%DYNAMICJSFILE\%\|\%(.+)\%\<\%/) {
        $dynsource = $1;
    } else {
        # Nothing to do
        return;
    }
    
    if(!defined($self->{uninlinefiles}->{$dynsource})) {
        print STDERR "INTERNAL ERROR IN TEMPLATECACHE: Dynamic template $dynsource not found!\n";
        return;
    }
    
    my $newname = $self->gen_dynjsname();
    $$page =~ s/\%\>\%DYNAMICJSFILE\%\|\%(.+)\%\<\%/$newname/;
    
    my $rawjs = $self->{uninlinefiles}->{$dynsource}->{uncompresseddata} . ''; # Make sure we COPY

    my $output;
    
    $self->{processor}->process(\$rawjs, $webdata, \$output);
    if(defined($self->{processor}->{_ERROR}) &&
            $self->{processor}->{_ERROR}) {
        $self->{LastError} = $self->{processor}->{_ERROR};
        print STDERR $self->{processor}->{_ERROR}->[1] . "\n";
    } else {
        my $insth = $dbh->prepare_cached("INSERT INTO templatecache_dynamic_scripting
                                         (webpath, scriptdata, source_template)
                                         VALUES (?,?,?)")
                or croak($dbh->errstr);
        
        if(!$insth->execute($newname, $output, $templatename)) {
            print STDERR $dbh->errstr, "\n";
            $dbh->rollback;
        } else {
            $dbh->commit;
        }
    }
    
    return;
}

sub gen_dynjsname {
    my ($self) = @_;
    
    my $namebase = 'abcdefghijklmnopqrstuvwxyz';

    my $name = '';
    my $count = int(rand(30))+20;
    for(1..$count) {
        my $pos = int(rand(length($namebase)));
        $name .= substr($namebase, $pos, 1);
    }
    $name = $self->{uninline}->{webpath} . '/dynamic/' . $name . '.js';

    return $name;
}

sub gen_eventhandlername {
    my ($self) = @_;
    
    my $namebase = 'abcdefghijklmnopqrstuvwxyz';

    my $name = '';
    my $count = 20;
    for(1..$count) {
        my $pos = int(rand(length($namebase)));
        $name .= substr($namebase, $pos, 1);
    }
    $name = 'ev_' . $name;

    return $name;
}

#my ($newdata, $autodialogjs, $autodialoghtml) = $self->parseAutoDialogs($data);
#my @oldlines = split/\n/, $data;

sub parseAutoDialogs {
    my ($self, $fname, $data) = @_;
    
    my @oldlines = split/\n/, $data;
    my @newlines;
    my $generator = PageCamel::Helpers::AutoDialogs->new();
    my $hasautodialogshtmltag = 0;
    my $hasautodialogsjstag = 0;
    my $autodialogcount;
    
    
    while(@oldlines) {
        my $line = shift @oldlines;
        if($line =~ /\[\%\s+AutoDialogsHTML\s+\%\]/) {
            $hasautodialogshtmltag = 1;
        }
        if($line =~ /\[\%\s+AutoDialogsJS\s+\%\]/) {
            $hasautodialogsjstag = 1;
        }
        if($line =~ /\[\%\ +dialog\.(\w+)\ *\(/) {
            # manually parse template lines and generate the corresponding snippets required
            # for AutoDialogs
            my $dialogname = $1;
            $autodialogcount++;
            $line =~ s/^(.+?)\(//g;
            my $readfinished = 0;
            my %config = (
                type => $dialogname,
            );
            while(1) {
                if($line =~ /\%\]/) {
                    $readfinished = 1;
                    $line =~ s/\%\]//;
                }
                $line = stripString($line);
                $line =~ s/\,$//;
                my ($key, $val) = split/\=\>/, $line;
                $key = stripString($key);
                $val = stripString($val);
                $val =~ s/\)$//;
                $val = stripString($val);
                $val =~ s/^\"//g;
                $val =~ s/\"$//g;
                $config{$key} = $val;
                if($readfinished) {
                    $line = '';
                    last;
                }
                $line = shift @oldlines;
            }
            $generator->addDialog(\%config);
        }
        
        if($line ne '') {
            push @newlines, $line;
        }
    }
    
    if($autodialogcount) {
        my $js = $generator->getJS();
        my $html = $generator->getHTML();
        my $htmlinserted = 0;
        my $jsinserted = 0;
        @oldlines = @newlines;
        @newlines = ();
    
        foreach my $line (@oldlines) {
            if($line =~ /\[\%\s+AutoDialogsHTML\s+\%\]/) {
                    $line = $html;;
                    $htmlinserted = 1;
            }
            if($hasautodialogsjstag) {
                if($line =~ /\[\%\s+AutoDialogsJS\s+\%\]/) {
                    $line = $js;
                    $jsinserted = 1;
                }
            } else {
                if($line =~ /\<\/script/) {
                    push @newlines, $js;
                    $jsinserted = 1;
                }
            }
            push @newlines, $line;
        }
        if(!$hasautodialogshtmltag) {
            push @newlines, $html;
            $htmlinserted = 1;
        }
        
        if(!$htmlinserted) {
            croak("Coudln't insert Autoform HTML in $fname");
        }
        if(!$jsinserted) {
            croak("Coudln't insert Autoform JS in $fname");
        }
    }
    
    return join("\n", @newlines);
}

1;
__END__

=head1 NAME

PageCamel::Web::TemplateCache -

=head1 SYNOPSIS

  use PageCamel::Web::TemplateCache;



=head1 DESCRIPTION



=head2 new



=head2 addPath



=head2 addView



=head2 reload



=head2 load_dir



=head2 register



=head2 get



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

Copyright (C) 2008-2016 by Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
