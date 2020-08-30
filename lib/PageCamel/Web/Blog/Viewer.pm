package PageCamel::Web::Blog::Viewer;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.3;
use autodie qw( close );
use Array::Contains;
use utf8;
use Encode qw(is_utf8 encode_utf8 decode_utf8);
use Data::Dumper;
#---AUTOPRAGMAEND---

use base qw(PageCamel::Web::BaseModule);
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::Strings qw[webSafeString elemNameQuote];
use HTTP::BrowserDetect;

sub new {
    my ($proto, %config) = @_;
    my $class = ref($proto) || $proto;

    my $self = $class->SUPER::new(%config); # Call parent NEW
    bless $self, $class; # Re-bless with our class

    if(!defined($self->{disable_viewcount})) {
        $self->{disable_viewcount} = 0;
    }

    if(!defined($self->{hookrootpath})) {
        $self->{hookrootpath} = 0;
    }

    if(!defined($self->{releasedrestrictions})) {
        $self->{releasedrestrictions} = 1;
    }

    if(!defined($self->{supportmobile})) {
        $self->{supportmobile} = 0;
    }

    if(!defined($self->{generate_toc})) {
        $self->{generate_toc} = 0;
    }

    return $self;
}

sub reload {
    my ($self) = shift;
    # Nothing to do.. in here, we only use the template and database module
    return;
}

sub register {
    my $self = shift;
    $self->register_webpath($self->{webpath}, "get");

    if(defined($self->{sitemap}) && $self->{sitemap}) {
        $self->register_sitemap('sitemap');
    }

    if(defined($self->{rssfeed})) {
        $self->register_webpath($self->{rssfeed}->{url}, 'rssfeed');
    }

    if($self->{hookrootpath}) {
        $self->register_prefilter('hookrootpath');
    }

    if(defined($self->{shorturl})) {
        $self->register_webpath($self->{shorturl}, "shorturl");
    }

    if($self->{supportmobile}) {
        $self->register_postauthfilter("get_blog_archive");
    }

    return;
}

sub crossregister {
    my ($self) = @_;

    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    $sysh->createBool(modulename => $self->{modname},
                        settingname => "enable_blog_comments",
                        settingvalue => "0",
                        description => 'Enable Blog Comments',
                        processinghints => [
                            'type=switch',
                                            ])
            or croak("Failed to create setting enable_comments!");

    $sysh->createBool(modulename => $self->{modname},
                        settingname => "show_comments_disclaimer",
                        settingvalue => "0",
                        description => 'Show the disclaimer (see TRANSLATE to edit text)',
                        processinghints => [
                            'type=switch',
                                            ])
            or croak("Failed to create setting show_comments_disclaimer!");

    return;
}

sub hookrootpath {
    my ($self, $ua) = @_;

    if($ua->{url} ne '/') {
        return;
    }

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $latest = 0;

    my $whereclause = '';
    if($self->{releasedrestrictions}) {
        $whereclause = "WHERE releasedate <= now() AND is_released = true"
    }

    my $lsth = $dbh->prepare_cached("SELECT * FROM " . $self->{tablename} . "
                                    $whereclause
                                    ORDER BY releasedate DESC
                                    LIMIT 1")
            or croak($dbh->errstr);
    $lsth->execute or croak($dbh->errstr);
    while((my $line = $lsth->fetchrow_hashref)) {
        $latest = $line->{article_id};
    }
    $lsth->finish;
    $dbh->rollback;

    if($latest == 0) {
        # No articles yet
        return;
    }

    # Re-Route to latest blog entry
    return (status   => 307,
            location => $self->{webpath} . '/' . $latest,
            data => "Redirecting to <a href=\"". $self->{webpath} . '/' . $latest . "\">most recent blob entry</a>",
           );

}

sub shorturl {
    my ($self, $ua) = @_;

    my $article_id;

    my $matcher = $self->{shorturl} . '/';
    if($ua->{url} =~ /^$matcher(\d+)$/) {
        $article_id = $1;
    } else {
        return (status => 404);
    }

    return (status   => 307,
            location => $self->{webpath} . '/' . $article_id,
            data => "Redirecting to full URL...",
           );

}

sub get {
    my ($self, $ua) = @_;

    my $th = $self->{server}->{modules}->{templates};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    my $enablecomments = 0;
    {
        my ($ok, $data) = $sysh->get($self->{modname}, "enable_blog_comments");
        if($ok) {
            $enablecomments = $data->{settingvalue};
        }
    }
    my $showdisclaimer = 0;
    {
        my ($ok, $data) = $sysh->get($self->{modname}, "show_comments_disclaimer");
        if($ok) {
            $showdisclaimer = $data->{settingvalue};
        }
    }

    my $id = $ua->{url};
    my $remove = $self->{webpath};
    $id =~ s/^$remove//;
    $id =~ s/\///g;

    # Check if we need to deliver Article's Java script
    if($id =~ /(.+)\.js$/) {
        $id = 0 + $1;
        if($id) {
            return $self->get_script($ua, $id);
        }
    }

    if($id eq '') {
        $id = 0;
    } else {
        $id = 0 + $id;
    }

    # No ID, so redirect to latest article
    if($id == 0) {
        my $latest = 0;
        my $whereclause = '';
        if($self->{releasedrestrictions}) {
            $whereclause = "WHERE releasedate <= now() AND is_released = true"
        }
        my $lsth = $dbh->prepare_cached("SELECT * FROM " . $self->{tablename} . "
                                        $whereclause
                                        ORDER BY releasedate DESC
                                        LIMIT 1")
                or croak($dbh->errstr);
        $lsth->execute or croak($dbh->errstr);
        while((my $line = $lsth->fetchrow_hashref)) {
            $latest = $line->{article_id};
        }
        $lsth->finish;
        $dbh->rollback;

        if($latest == 0) {
            # No articles yet
            return (status  =>  404);
        }

        return (status   => 303,
                location => $self->{webpath} . '/' . $latest
               );
    }

    my $selclause = '';
    if($self->{releasedrestrictions}) {
        $selclause = "AND releasedate <= now() AND is_released = true"
    }

    my $selsth = $dbh->prepare_cached("SELECT b.*, u.first_name || ' ' || u.last_name AS realauthorname
                                        FROM " . $self->{tablename} . " b
                                        INNER JOIN users u ON b.author = u.username
                                      WHERE article_id = ?
                                      $selclause
                                      LIMIT 1")
            or croak($dbh->errstr);
    $selsth->execute($id) or croak($dbh->errstr);
    my $pretitle = '';
    my $title = '';
    my $subtitle = '';
    my $gsp_mission_status = '';
    my $fulltext = '';
    my $releasedate = '';
    my $eternalseptember = '';
    my $author = '';
    my $posttype = 0;
    my $javascript_onload = '';
    my $javascript_functions = '';

    while((my $line = $selsth->fetchrow_hashref)) {
        $pretitle = $line->{pretitle};
        $title = $line->{title};
        $subtitle = $line->{subtitle};
        $fulltext = $line->{fulltext};
        $gsp_mission_status = $line->{gsp_mission_status};
        $releasedate = $line->{releasedate};
        $eternalseptember = eternalseptemberize($line->{releasedate});
        $author = $line->{realauthorname};
        $posttype = $line->{post_type};
        $javascript_onload = $line->{javascript_onload};
        $javascript_functions = $line->{javascript_functions};
    }
    $selsth->finish;


    if($title eq '' && $fulltext eq '') {
        $dbh->rollback();
        return (status  =>  404);
    }

    my $nextlink = '';
    my $nextlinktitle = '';
    my $prevlink = '';
    my $prevlinktitle = '';
    {
        my $nsth = $dbh->prepare_cached("SELECT * FROM " . $self->{tablename} . "
                                         WHERE releasedate > ?
                                         $selclause
                                         ORDER BY releasedate
                                         LIMIT 1")
                or croak($dbh->errstr);
        $nsth->execute($releasedate) or croak($dbh->errstr);
        while((my $line = $nsth->fetchrow_hashref)) {
            $nextlink = $self->{webpath} . '/' . $line->{article_id};
            $nextlinktitle = $line->{title};
        }
        $nsth->finish;
    }
    {
        my $psth = $dbh->prepare_cached("SELECT * FROM " . $self->{tablename} . "
                                         WHERE releasedate < ?
                                         $selclause
                                         ORDER BY releasedate DESC
                                         LIMIT 1")
                or croak($dbh->errstr);
        $psth->execute($releasedate) or croak($dbh->errstr);
        while((my $line = $psth->fetchrow_hashref)) {
            $prevlink = $self->{webpath} . '/' . $line->{article_id};
            $prevlinktitle = $line->{title};
        }
        $psth->finish;
    }

    $dbh->pg_savepoint("Viewcount");

    if(!$self->{disable_viewcount}) {
        my $vsth = $dbh->prepare_cached("UPDATE blog
                                        SET viewcount = viewcount + 1
                                        WHERE article_id = ?")
                or croak($dbh->errstr);
        if(!$vsth->execute($id)) {
            $dbh->pg_rollback_to("Viewcount");
        } else {
            $vsth->finish;
        }
    }

    $dbh->commit;

    my @headextrascripts = ('/static/codehighlight/highlight.pack.js',
                            );

    my @headextracss = ('/static/codehighlight/styles/sunburst.css',
                        );

    # Handle some tags that don't work in CVCEditor. Currently, designed to handle only one per line
    my @flines = split/\n/, $fulltext;
    foreach my $fline (@flines) {
        if($fline =~ /\[audio\|(.*?)\]/) { # Non-greedy audio match urls
            my @urls = split/\|/, $1;
            my $replace = '<audio controls>';
            my %ftypemap = (
                ogg     => 'audio/ogg',
                mp3     => 'audio/mpeg',
                wav     => 'audio/wav',

            );
            foreach my $url (@urls) {
                my ($suffix) = $url =~ /\.([^\.]+)$/;
                my $type = 'audio/other';
                if(defined($ftypemap{$suffix})) {
                    $type = $ftypemap{$suffix};
                }
                $replace .= "<source src=\"$url\" type=\"$type\">";
            }
            $replace .= '</audio>';
            $fline =~ s/\[audio\|.*?\]/$replace/;
        }
    }
    $fulltext = join("\n", @flines);

    if($javascript_onload ne '' || $javascript_functions ne '') {
        push @headextrascripts, $self->{webpath} . '/' . $id . '.js';
    }

    # Generate TOC (table of contents)
    if($self->{generate_toc}) {
        my $originaltext = $fulltext;
        my $toccount = 0;

        my $toc = '<div class="blogtoc">';
        $toc .= '<b>Table of Contents [<span class="blogtocshowhide" id="blogtochide">Hide</span>]</b>';
        $toc .= '<span id="blogtoctable"><br/>';

        my $newtext = '';
        my %knowntocs;
        while(length($fulltext)) {
            if($fulltext =~ /^(\<h\d\>)/) {
                my $tag = $1;

                # Remove header tag from source text
                substr($fulltext, 0, 4, '');

                # Now we need to find the closing tag and the matching title text
                my $ttext = '';
                my $tempchar = '';
                while(length($fulltext)) {
                    last if($fulltext =~ /^\<\/h\d\>/);
                    $tempchar = substr($fulltext, 0, 1);
                    substr($fulltext, 0, 1, '');
                    #$newtext .= $tempchar;
                    $ttext .= $tempchar;
                }

                my $endtag = substr($fulltext, 0, 5);
                substr($fulltext, 0, 5, '');

                # Remove unwanted stuff
                my $tocid = lc $ttext;
                $tocid =~ s/\&.*?\;//g;
                $tocid =~ s/\s//g;
                $tocid =~ s/[^\w\s]//g;

                if($tocid eq '') {
                    # Empty header, known bug in CVCEditor.
                    # Replace it with a <br/> in article and ignore otherwhise
                    $newtext .= '<br/>';
                    next;
                }

                # Now need to check if it is the FIRST tocid with that name (especially sub-headers
                # could repeat). If a repeat, just add a sequential number, specific to that tocid
                if(!defined($knowntocs{$tocid})) {
                    $knowntocs{$tocid} = 1;
                } else {
                    $knowntocs{$tocid}++;
                    $tocid .= $knowntocs{$tocid};
                }

                # Prefix tocid with 'toc'
                $tocid = 'toc' . $tocid;

                # Add anchor and header to body text
                $newtext .= '<a name="' . $tocid . '"></a>' . $tag . $ttext . $endtag;

                my $indents = '';
                my $formatedtext = '';
                if($tag eq '<h1>') {
                    $formatedtext = '<br/><b>' . $ttext . '</b>';
                } else {
                    my $indentcount = substr($tag, 2, 1);
                    $indents = '&nbsp;' x ($indentcount * 3);
                    if($indentcount == 2) {
                        $indents .= '&#x2022;&nbsp;';
                    } elsif($indentcount == 3) {
                        $indents .= '&#x2023;&nbsp;';
                    } else {
                        $indents .= '&nbsp;&nbsp;'; # Shouldn't happen, article doo deeply leveled ;-)
                    }

                    $formatedtext = $ttext;
                }

                # Add Line to TOC
                #$toc .= '<tr><td>' . $indents . '<a href="' . $tocid . '">' . $formatedtext . '</a></td></tr>';
                $toc .= $indents . '<a href="#' . $tocid . '">' . $formatedtext . '</a><br/>';
                $toccount++;
            } else {
                $newtext .= substr($fulltext, 0, 1);
                substr($fulltext, 0, 1, '');
            }
        }

        $toc .= '</div></p>';

        if($toccount > 2) {
            $fulltext = $toc . $newtext;
        } else {
            # Not enough headers to need a table of contents...
            $fulltext = $originaltext;
        }
    }


    # Add tag to images so we can enable fullscreen click stuff and page width scaling for article content only
    $fulltext =~ s/\<img\ /<img articlecontent="1" /g;

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $title,
        DisablePageTitleTranslation => 1,
        blogtitle   => $title,
        pretitle   => $pretitle,
        subtitle   => $subtitle,
        gsp_mission_status => $gsp_mission_status,
        blogentry   => $fulltext,
        author      => $author,
        posttype    => $posttype,
        releasedate => $releasedate,
        eternalseptember => $eternalseptember,
        nextlink    => $nextlink,
        nexttitle   => $nextlinktitle,
        prevlink    => $prevlink,
        prevtitle   => $prevlinktitle,
        archivelink => $self->{archivelink},
        HeadExtraScripts => \@headextrascripts,
        HeadExtraCSS => \@headextracss,
        EnableComments => $enablecomments,
        ShowDisclaimer => $showdisclaimer,
        showads => $self->{showads},
    );

    if(defined($self->{rssfeed})) {
        $webdata{RSSFeed} = $self->{rssfeed}->{url};
    }

    if($enablecomments && defined($webdata{userData}->{user}) && $webdata{userData}->{user} ne 'guest') {
        if($ua->{method} eq 'POST') {
            my $mode = $ua->{postparams}->{'mode'} || '';
            my $comment = $ua->{postparams}->{'comment'} || '';
            $comment = webSafeString($comment);
            if($mode eq 'comment' && $comment ne '') {
                my $insth = $dbh->prepare_cached("INSERT INTO " . $self->{commentstablename} . "
                                                 (article_id, username, usercomment)
                                                 VALUES (?,?,?)")
                        or croak($dbh->errstr);
                if($insth->execute($id, $webdata{userData}->{user}, $comment)) {
                    $dbh->commit;
                } else {
                    $dbh->rollback;
                }
            }
        }

        $webdata{commentsenabled} = 1;
    }

    my @comments;

    my $cselsth = $dbh->prepare_cached("SELECT c.comment_id, c.username, date_trunc('seconds', c.logtime) AS tlogtime, c.usercomment,
                                                u.first_name || ' ' || u.last_name AS realusername
                                    FROM " . $self->{commentstablename} . " c
                                    JOIN users u ON u.username = c.username
                                    WHERE c.article_id = ?
                                    ORDER BY c.logtime")
        or croak($dbh->errstr);
    $cselsth->execute($id) or croak($dbh->errstr);

    while((my $line = $cselsth->fetchrow_hashref)) {
        push @comments, $line;
    }
    $cselsth->finish;
    $webdata{comments} = \@comments;

    $dbh->rollback;

    my $clientMode = $self->getClientMode($ua);
    $webdata{MobileDesktopClientMode} = $clientMode;

    my $template = $self->{server}->{modules}->{templates}->get('blog/viewer', 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template,
            'Vary'    => 'User-Agent', # <-- Signal google we support mobile on this page
            );
}

sub get_script {
    my ($self, $ua, $id) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $selclause = '';
    if($self->{releasedrestrictions}) {
        $selclause = "AND releasedate <= now() AND is_released = true"
    }

    my $selsth = $dbh->prepare_cached("SELECT javascript_onload, javascript_functions
                                        FROM " . $self->{tablename} . "
                                      WHERE article_id = ?
                                      $selclause
                                      LIMIT 1")
            or croak($dbh->errstr);
    $selsth->execute($id) or croak($dbh->errstr);

    my $javascript_onload = '';
    my $javascript_functions = '';

    while((my $line = $selsth->fetchrow_hashref)) {
        $javascript_onload = $line->{javascript_onload};
        $javascript_functions = $line->{javascript_functions};
    }
    $selsth->finish;
    $dbh->commit;

    my $fullscript = $javascript_functions . "\n" .
                     "function blogExtraOnLoad() {\n" .
                     $javascript_onload .
                     "}";

    return (status  =>  200,
        type    => "application/javascript",
        data    => $fullscript,
        'Vary'    => 'User-Agent', # <-- Signal google we support mobile on this page
    );

}

sub get_blog_archive {
    my ($self, $ua) = @_;

    my $clientMode = $self->getClientMode($ua);
    if($clientMode ne 'mobile') {
        # Don't do anything
        return;
    }

    # Ok mobile mode.
    if($ua->{url} ne $self->{archivelink}) {
        # Not the arhive link
        return;
    }

    my $th = $self->{server}->{modules}->{templates};
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $selsth = $dbh->prepare_cached("SELECT b.article_id, b.archive_teaser, b.releasedate,
                                        b.post_type,
                                        u.first_name || ' ' || u.last_name AS realauthorname
                                        FROM " . $self->{tablename} . " b
                                        INNER JOIN users u ON b.author = u.username
                                        WHERE releasedate <= now() AND is_released = true
                                        ORDER BY releasedate DESC")
            or croak($dbh->errstr);

    my @articles;
    if(!$selsth->execute) {
        $dbh->rollback;
        return (status => 500);
    }
    while((my $article = $selsth->fetchrow_hashref)) {
        $article->{releasedate} =~ s/\ .*//;
        push @articles, $article;
    }
    $selsth->finish;
    $dbh->commit;

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        Articles => \@articles,
        PageTitle   =>  'Blog Archive',
        MobileDesktopClientMode => $clientMode,
    );

    my $template = $self->{server}->{modules}->{templates}->get('blog/archive_mobile', 1, %webdata);

    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template,
            'Vary'    => 'User-Agent', # <-- Signal google we support mobile on this page
            );


}

sub sitemap {
    my ($self, $sitemap) = @_;

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $whereclause = '';
    if($self->{releasedrestrictions}) {
        $whereclause = "WHERE releasedate <= now() AND is_released = true"
    }

    my $selsth = $dbh->prepare_cached("SELECT article_id FROM " . $self->{tablename} . "
                                      $whereclause
                                      ORDER BY releasedate DESC")
            or croak($dbh->errstr);
    $selsth->execute() or croak($dbh->errstr);

    while((my $line = $selsth->fetchrow_hashref)) {
        push @{$sitemap}, $self->{webpath} . '/' . $line->{article_id};
    }
    $selsth->finish;
    $dbh->rollback;

    return;
}

sub rssfeed {
    my ($self, $ua) = @_;

    my $th = $self->{server}->{modules}->{templates};
    my $dbh = $self->{server}->{modules}->{$self->{db}};

    my $whereclause = '';
    if($self->{releasedrestrictions}) {
        $whereclause = "WHERE releasedate <= now() AND is_released = true"
    }

    my @articles;

    my $selsth = $dbh->prepare_cached("SELECT b.*, u.first_name || ' ' || u.last_name AS realauthorname
                                        FROM " . $self->{tablename} . " b
                                        INNER JOIN users u ON b.author = u.username
                                      $whereclause
                                      ORDER BY releasedate DESC
                                      LIMIT 10")
            or croak($dbh->errstr);
    $selsth->execute() or croak($dbh->errstr);

    my $lastchange = 0;
    while((my $line = $selsth->fetchrow_hashref)) {
        #push @{$sitemap}, $self->{webpath} . '/' . $line->{article_id};
        my $tmp = parseWebdate($line->{releasedate});
        if($tmp > $lastchange) {
            $lastchange = $tmp;
        }
        my $lastmodified = getWebdate($tmp);
        my %article = (
            title   => $line->{title},
            article_id => $line->{article_id},
            pubdate => $lastmodified,
            description => $line->{teaser},
            author => $line->{realauthorname},
            category => $line->{post_type},
        );
        push @articles, \%article;
    }
    $selsth->finish;
    $dbh->rollback;

    my %webdata = (
        Articles    => \@articles,
        PageTitle   => $self->{pagetitle},
        WebPath     => $self->{webpath},
        RSSConfig   => $self->{rssfeed},
        LastChange  => getWebdate($lastchange),
    );

    my $template = $th->get("blog/rssfeed", 0, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "application/rss+xml",
            data    => $template,
            expires         => $self->{expires},
            cache_control   =>  $self->{cache_control},
    );
}

sub getClientMode {
    my ($self, $ua) = @_;

    if(!$self->{supportmobile}) {
        return '';
    }

    my $clientMode = 'desktop';
    if(!defined($ua->{cookies}->{clientMode}) || ($ua->{cookies}->{clientMode} ne 'mobile' && $ua->{cookies}->{clientMode} ne 'desktop'))  {
        my $bd = HTTP::BrowserDetect->new($ua->{headers}->{"User-Agent"});
        if($bd->mobile() || $bd->tablet()) {
            $clientMode = 'mobile';
        }
    } elsif($ua->{cookies}->{clientMode} eq 'mobile') {
        $clientMode = 'mobile';
    }

    return $clientMode;
}

1;
__END__

=head1 NAME

PageCamel::Web::Blog::Viewer -

=head1 SYNOPSIS

  use PageCamel::Web::Blog::Viewer;



=head1 DESCRIPTION



=head2 new



=head2 reload



=head2 register



=head2 crossregister



=head2 hookrootpath



=head2 shorturl



=head2 get



=head2 sitemap



=head2 rssfeed



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
