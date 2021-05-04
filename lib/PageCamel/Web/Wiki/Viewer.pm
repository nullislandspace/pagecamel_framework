package PageCamel::Web::Wiki::Viewer;
#---AUTOPRAGMASTART---
use 5.030;
use strict;
use warnings;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 3.4;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use PageCamel::Helpers::UTF;
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

    if($self->{hookrootpath}) {
        $self->register_prefilter('hookrootpath');
    }

    if($self->{supportmobile}) {
        $self->register_postauthfilter("get_wiki_archive");
    }

    return;
}

sub hookrootpath {
    my ($self, $ua) = @_;

    if($ua->{url} ne '/') {
        return;
    }

    my $dbh = $self->{server}->{modules}->{$self->{db}};

    # Re-Route to default wiki entry
    my $startpage = $self->{webpath} . '/' . $self->{default_page};
    return (status   => 307,
            location => $startpage,
            data => "Redirecting to <a href=\"". $startpage . "\">default entry</a>",
           );

}

sub get {
    my ($self, $ua) = @_;

    my $th = $self->{server}->{modules}->{templates};
    my $dbh = $self->{server}->{modules}->{$self->{db}};
    my $sysh = $self->{server}->{modules}->{$self->{systemsettings}};

    my $linktitle = $ua->{url};
    my $remove = $self->{webpath};
    $linktitle =~ s/^$remove//;
    $linktitle =~ s/\///g;

    if($linktitle eq '') {
        $linktitle = $self->{default_page};
    }

    my $selsth = $dbh->prepare_cached("SELECT b.*, u.first_name || ' ' || u.last_name AS realauthorname
                                        FROM " . $self->{tablename} . " b
                                        INNER JOIN users u ON b.author = u.username
                                      WHERE linktitle = ?
                                      LIMIT 1")
            or croak($dbh->errstr);
    $selsth->execute($linktitle) or croak($dbh->errstr);
    my $title = '';
    my $fulltext = '';

    while((my $line = $selsth->fetchrow_hashref)) {
        $title = $line->{title};
        $fulltext = $line->{fulltext};
    }
    $selsth->finish;


    if($title eq '' && $fulltext eq '') {
        $dbh->rollback();
        return (status  =>  404);
    }

    $dbh->pg_savepoint("Viewcount");

    if(!$self->{disable_viewcount}) {
        my $vsth = $dbh->prepare_cached("UPDATE " . $self->{tablename} . "
                                        SET viewcount = viewcount + 1
                                        WHERE linktitle = ?")
                or croak($dbh->errstr);
        if(!$vsth->execute($linktitle)) {
            $dbh->pg_rollback_to("Viewcount");
        } else {
            $vsth->finish;
        }
    }

    $dbh->pg_savepoint("AllTitles");

    my $titlesth = $dbh->prepare_cached("SELECT title, linktitle FROM " . $self->{tablename})
            or croak($dbh->errstr);
    my %fulltitles;
    if(!$titlesth->execute) {
        $dbh->pg_rollback_to("AllTitles");
    } else {
        while((my $line = $titlesth->fetchrow_hashref)) {
            $fulltitles{$line->{linktitle}} = $line->{title};
        }
    }

    $dbh->commit;

    my @headextrascripts;
    my @headextracss;

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

    # Generate TOC (table of contents)
    if($self->{generate_toc}) {
        my $originaltext = $fulltext;
        my $toccount = 0;

        my $toc = '<div class="wikitoc">';
        $toc .= '<b>Table of Contents [<span class="wikitocshowhide" id="wikitochide">Hide</span>]</b>';
        $toc .= '<span id="wikitoctable"><br/>';

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

        if($toccount > 1) {
            $fulltext = $toc . $newtext;
        } else {
            # Not enough headers to need a table of contents...
            $fulltext = $originaltext;
        }
    }


    # Add tag to images so we can enable fullscreen click stuff and page width scaling for article content only
    $fulltext =~ s/\<img\ /<img articlecontent="1" /g;

    # Replace markup links with real links
    my $baselink = $self->{webpath} . '/';
    while($fulltext =~ /\<a\ class\=\"cavacwiki\"/) {
        my ($pre, $rest) = split /\<a\ class\=\"cavacwiki\"\ linktitle\=\"/, $fulltext, 2;
        my ($llinktitle, $post) = split/\"/, $rest, 2;
        $post =~ s/^(.+?)\<\/a\>//;
        if(defined($fulltitles{$llinktitle})) {
            $fulltext = $pre . '<a href="' . $baselink . $llinktitle . '">' . $fulltitles{$llinktitle} . '</a>' . $post;
        } else {
            $fulltext = $pre . ' &#10068;&#10068;&#10068;' . $llinktitle . '&#10068;&#10068;&#10068; ' . $post;
        }
    }

    # Mark legacy links as broken
    while($fulltext =~ /\[wiki\:(.+?)]/) {
        my ($pre, $rest) = split /\[wiki\:/, $fulltext, 2;
        my ($llinktitle, $post) = split/\]/, $rest, 2;
        $fulltext = $pre . ' &#10068;&#10068;&#10068;' . $llinktitle . '&#10068;&#10068;&#10068; ' . $post;
    }

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        PageTitle   =>  $title,
        DisablePageTitleTranslation => 1,
        wikititle   => $title,
        wikientry   => $fulltext,
        archivelink => $self->{archivelink},
        HeadExtraScripts => \@headextrascripts,
        HeadExtraCSS => \@headextracss,
        showads => $self->{showads},
    );

    $dbh->rollback;

    my $clientMode = $self->getClientMode($ua);
    $webdata{MobileDesktopClientMode} = $clientMode;

    my $template = $th->get('wiki/viewer', 1, %webdata);
    return (status  =>  404) unless $template;
    return (status  =>  200,
            type    => "text/html",
            data    => $template,
            'Vary'    => 'User-Agent', # <-- Signal google we support mobile on this page
            );
}
sub get_wiki_archive {
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

    my $selsth = $dbh->prepare_cached("SELECT b.article_id, b.linktitle, b.archive_teaser
                                        b.post_type,
                                        u.first_name || ' ' || u.last_name AS realauthorname
                                        FROM " . $self->{tablename} . " b
                                        INNER JOIN users u ON b.author = u.username
                                        ORDER BY linktitle")
            or croak($dbh->errstr);

    my @articles;
    if(!$selsth->execute) {
        $dbh->rollback;
        return (status => 500);
    }
    while((my $article = $selsth->fetchrow_hashref)) {
        push @articles, $article;
    }
    $selsth->finish;
    $dbh->commit;

    my %webdata = (
        $self->{server}->get_defaultwebdata(),
        Articles => \@articles,
        PageTitle   =>  'Wiki Archive',
        MobileDesktopClientMode => $clientMode,
        showads => $self->{showads},
    );

    my $template = $th->get('wiki/archive_mobile', 1, %webdata);

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

    my $selsth = $dbh->prepare_cached("SELECT article_id FROM " . $self->{tablename} .
                                      " ORDER BY linktitle")
            or croak($dbh->errstr);
    $selsth->execute() or croak($dbh->errstr);

    while((my $line = $selsth->fetchrow_hashref)) {
        push @{$sitemap}, $self->{webpath} . '/' . $line->{linktitle};
    }
    $selsth->finish;
    $dbh->rollback;

    return;
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



=head2 get



=head2 sitemap



=head2 rssfeed



=head1 IMPORTANT NOTE

This module is part of the PageCamel framework. Currently, only limited support
and documentation exists outside my DarkPAN repositories. This source is
currently only provided for your reference and usage in other projects (just
copy&paste what you need, see license terms below).

To see PageCamel in action and for news about the project,
visit my wiki at L<https://cavac.at>.

=head1 AUTHOR

Rene Schickbauer, E<lt>pagecamel@cavac.atE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
