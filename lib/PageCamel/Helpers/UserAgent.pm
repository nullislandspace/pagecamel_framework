package PageCamel::Helpers::UserAgent;
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
our @EXPORT_OK = qw(simplifyUA);

use HTTP::BrowserDetect;

sub simplifyUA { ## no critic (Subroutines::ProhibitExcessComplexity)
    my ($useragentname) = @_;

    my $simpleUserAgent = '';
    my $denyAccess = 0;

    my $browser = HTTP::BrowserDetect->new($useragentname);
    my $browserName = $browser->browser_string();
    my $majorVersion = $browser->browser_major();
    if(defined($browserName) && defined($majorVersion)) {
        $simpleUserAgent = $browserName . '/' . $majorVersion;
    } else {
        if($useragentname eq '' || $useragentname eq "''") { ## no critic (ControlStructures::ProhibitCascadingIfElse)
            $useragentname = '--unknown--';
        } elsif($useragentname =~ /CC Client\/(\d+)/) {
            $simpleUserAgent = "CC Client/$1";
        } elsif($useragentname eq "CCOld Bot") {
            $simpleUserAgent = "CC Client/1";
        } elsif($useragentname eq "--unknown--" ) {
            $simpleUserAgent = "NONE";
        } elsif($useragentname =~ /XML\-RPC/) {
            $simpleUserAgent = "XML-RPC";
        } elsif($useragentname =~ /Scarecrow\/(\d+)/) {
            $simpleUserAgent = "Scarecrow/$1";
        } elsif($useragentname =~ /RBSDirect\/(.*)/) {
            $simpleUserAgent = "RBSDirect/$1";
        } elsif($useragentname =~ /PonyExpress\/(\d+)/) {
            $simpleUserAgent = "PonyExpress/$1";
        } elsif($useragentname =~ /PageCamel LetsEncrypt\/(\d+)/) {
            $simpleUserAgent = "PageCamel LetsEncrypt/$1";
        } elsif($useragentname =~ /PTouch\/(\d+)/) {
            $simpleUserAgent = "PTouch/$1";
        } elsif($useragentname =~ /mercurial\/proto-(\d+)/) {
            $simpleUserAgent = "Mercurial/Proto $1";
        } elsif($useragentname =~ /Microsoft\ Office\ (.*)\ Discovery/) {
            $simpleUserAgent = "MSOffice $1 Discovery";
        } elsif($useragentname =~ /WWW\-Mechanize\/(\d+)/i) {
            $simpleUserAgent = "Mechanize/$1";
        } elsif($useragentname =~ /Java.*SDK/i) {
            $simpleUserAgent = "JAVA SDK";
        } elsif($useragentname =~ /Java\/.*/i) {
            $simpleUserAgent = "JAVA";
        } elsif($useragentname =~ /ssllabs\.com/i) {
            $simpleUserAgent = "SSL Labs Checker";
        } elsif($useragentname =~ /mostly.*cavac.at/i) {
            $simpleUserAgent = "cavac";
        } elsif($useragentname =~ /(DavClnt)/i) {
            $simpleUserAgent = "Potential_Virus/" . lc($1);
        } elsif($useragentname =~ /Discordbot/i) {
            $simpleUserAgent = "DiscordBot";
        } elsif($useragentname =~ /(ZmEu|Morfeus|Comodo\ ssl\ checker)/i) {
            $simpleUserAgent = "Virus/" . lc($1);
            $denyAccess = 1;
        } elsif($useragentname =~ /(bingbot|googlebot|pagesinventory|feedfetcher\-google|plukkie|msnbot|yandex|google\-desktop|seznambot|turnitinbot|baidu|yahoo\!\ slurp|nerdybot|orangebot|twitterbot|paperlibot|duckduckgo|qwantify)/i) {
            $simpleUserAgent = "Webspider_good/" . lc($1);
        } elsif($useragentname =~ /(netcraft.*survey|synapse|phpcrawl|wotbox|yacybot|zend_http_client|mail.ru\_bot|spbot|crazywebcrawler|go.*package\ http)/i) {
            $simpleUserAgent = "Webspider_undecided/" . lc($1);
        } elsif($useragentname =~ /(seokicks|indy\ library|ezooms|mj12bot|wbsearchbot|webcollage|dotbot|exabot|meanpathbot|binaryedge)/i) {
            $simpleUserAgent = "Webspider_probation/" . lc($1);
            $denyAccess = 0;
        } elsif($useragentname =~ /(x00_-gawa.sa.pilipinas.2015|blexbot|ahrefsbot|seostats)/i) {
            $simpleUserAgent = "Webspider_bad/" . lc($1);
            $denyAccess = 1;
        } elsif($useragentname =~ /nmap\ scripting\ engine/i) {
            $simpleUserAgent = "Hacker/NMAP";
            $denyAccess = 1;
        } elsif($useragentname =~ /(monitis)/i) {
            $simpleUserAgent = "DOS_ATTACK/" . lc($1);
            $denyAccess = 1;
        } elsif($useragentname =~ /CPAN\:\:MINI/i) {
            $simpleUserAgent = "CPAN-MINI";
        } elsif($useragentname =~ /LWP\:\:Simple/i) {
            $simpleUserAgent = "LWP-Simple";
        } elsif($useragentname =~ /ISOCIPv6Bot/i) {
            $simpleUserAgent = "IPv6 Checker Bot";
        } elsif($useragentname =~ /Magic\ Browser/i) {
            $simpleUserAgent = "Magic Browser";
        } elsif($useragentname =~ /Fritz.Box/i) {
            $simpleUserAgent = "Fritz!Box";
        } elsif($useragentname =~ /(?:libwww-perl|LWP)/i) {
            $simpleUserAgent = "LWP";
        } elsif($useragentname =~ /wget/i) {
            $simpleUserAgent = "wget";
        } elsif($useragentname =~ /curl/i) {
            $simpleUserAgent = "curl";
        } elsif($useragentname =~ /python\-requests/i) {
            $simpleUserAgent = "python";
        } elsif($useragentname =~ /Microsoft-WebDAV-MiniRedir/i) {
            $simpleUserAgent = "Microsoft WebDAV";
        } elsif($useragentname =~ /facebookexternalhit/i || $useragentname =~ /facebook.*externalhit/) {
            $simpleUserAgent = "Facebook";
        } elsif($useragentname =~ /bitlybot\/(.*?)\ /) {
            $simpleUserAgent = "Bit.ly/$1";
        } elsif($useragentname =~ /Cliqzbot\/(.*?)\ /i) {
            $simpleUserAgent = "Cliqz.com/$1";
        } elsif($useragentname =~ /redditbot\/(.*?)\;/) {
            $simpleUserAgent = "RedditBot/$1";
        } elsif($useragentname =~ /^newspaper\//) {
            $simpleUserAgent = "Python/Newspaperlib";
        } elsif($useragentname =~ /^python\-urllib/i) {
            $simpleUserAgent = "Python/urllib";
        } elsif($useragentname =~ /^Ruby$/) {
            $simpleUserAgent = "Ruby";
        } elsif($useragentname =~ /^okhttp\//) {
            $simpleUserAgent = "Java/okhttplib";
        } elsif($useragentname =~ /^slackbot\-linkexpanding\ (.*?)\ /i || $useragentname =~ /^Slackbot\ (.*?)\ /i) {
            $simpleUserAgent = "Slackbot/$1";
        } elsif($useragentname =~ /^AlienBlue/) {
            $simpleUserAgent = "AlienBlue-Browser";
        } elsif($useragentname =~ /^SafeDNSBot/) {
            $simpleUserAgent = "SafeDNS/ContentBlocker"; # Used by families and companies to only allow specific categories of content
        } elsif($useragentname =~ /^Dillo\//) {
            $simpleUserAgent = "Dillo-Browser";
        } elsif($useragentname =~ /go\-http\-client\/(.*?)/i) {
            $simpleUserAgent = "GO-HTTP/$1";
        } elsif($useragentname =~ /windows\-media\-player\/(.*?)/i) {
            $simpleUserAgent = "MS/MediaPlayer/$1";
        } elsif($useragentname =~ /www\.karriere\.at/) {
            $simpleUserAgent = "Jobs/karriere.at";
        } elsif($useragentname =~ /www\.metajob\.at/) {
            $simpleUserAgent = "Jobs/metajob.at";
        } elsif($useragentname =~ /^com\.google\.GoogleMobile/i) {
            $simpleUserAgent = "GoogleBot/Mobile";
        } elsif($useragentname =~ /Google\-Site\-Verification/i) {
            $simpleUserAgent = "GoogleBot/Site-Verification";
        } elsif($useragentname =~ /alexa\ site\ audit/i) {
            $simpleUserAgent = "AlexaBot";
        } elsif($useragentname =~ /^archive\.org/i || $useragentname =~ /wayback\ machine/i || $useragentname =~ /www\.archive\.org/i) {
            $simpleUserAgent = "Archive.org";
        } elsif($useragentname =~ /coccocbot\-web/) {
            $simpleUserAgent = "Coccoc.co/Web (Vietnam)";
        } elsif($useragentname =~ /coccocbot\-image/) {
            $simpleUserAgent = "Coccoc.co/Image (Vietnam)";
        } elsif($useragentname =~ /^GarlikCrawler/) {
            $simpleUserAgent = "Garlik.com";
        } elsif($useragentname =~ /Uptimebot/ || $useragentname =~ /Uptime\.com/) {
            $simpleUserAgent = "Uptime.com"; # Seems useful, more or less
        } elsif($useragentname =~ /soup\.io/) {
            $simpleUserAgent = "Soup.IO";
        } elsif($useragentname =~ /^BUbiNG/) {
            $simpleUserAgent = "BUbiNG"; # Some university experimental crawler. Let it in for now
        } elsif($useragentname =~ /^WizeNoze\ Discovery\ Crawler/i) {
            $simpleUserAgent = "Wizenoze.com"; # Some child learning thingamabobcrawler. Let it in for now
        } elsif($useragentname =~ /^CSS\ Certificate\ Spider\ /) {
            $simpleUserAgent = "CertChecker"; # Seems to check/cache SSL public certs, seems legit
        } elsif($useragentname =~ /^Nuzzel$/) {
            $simpleUserAgent = "Nuzzel/NewsCollector"; # Seems legit
        } elsif($useragentname =~ /researchscan\.comsys\.rwth\-aachen\.de/i) {
            # Some university security research
            $simpleUserAgent = "Research/RWTH_Achen_Uni";
        } elsif($useragentname =~ /netsystemsresearch\.com/i) {
            # Some IoT security research
            $simpleUserAgent = "Research/IoT";
        } elsif($useragentname =~ /Akregator/i) {
            # Part of KDE it seems
            $simpleUserAgent = "KDE/Akregator";
        } elsif($useragentname =~ /CakePHP/i) {
            # CakePHP
            $simpleUserAgent = "CakePHP";
        } elsif($useragentname =~ /com\.google\.android\.apps\.searchlite/i) {
            # Google Go?
            $simpleUserAgent = "Google Go/searchlite";
        } elsif($useragentname =~ /mindup\.de/i) {
            # mindup.de "Marketing using artificial intelligence"
            $simpleUserAgent = "Marketing/mindup.de";
            $denyAccess = 1;
        } elsif($useragentname =~ /facebook.*externalhit/i) {
            # Facebook
            $simpleUserAgent = "Facebook";
        } elsif($useragentname =~ /di\-cloud\-parser/i) {
            # I have NO idea what that is supposed to be. For now, let it in
            $simpleUserAgent = "di-cloud-parser";
        } elsif($useragentname =~ /security\.ipip\.net/i) {
            # Chinese "Security" site that collects data on http headers and open ports. Block it
            $simpleUserAgent = "Suspicious/security.ipip.net";
            $denyAccess = 1;
        } elsif($useragentname =~ /^m$/i) {
            # Whatever the hell this is, is highly strange. Let's just block it. As far as i can see, it's some kind of crawler
            $simpleUserAgent = "Suspicious/M";
            $denyAccess = 1;
        } elsif($useragentname =~ /mediatoolkit\.com/i) {
            # Another of those strange "brand protection" crawlers. Go to hell
            $simpleUserAgent = "BrandProtection/mediatoolkit.com";
            $denyAccess = 1;
        } elsif($useragentname =~ /domainsono\.com/i) {
            # Crawler, but the domain is currently "for sale". Block it
            $simpleUserAgent = "Suspicious/domainsono.com";
            $denyAccess = 1;
        } elsif($useragentname =~ /crawler\@alexa\.com/i) {
            # Alexa crawler
            $simpleUserAgent = "Alexa";
        } elsif($useragentname =~ /cloudsystemnetworks\.com/i) {
            # Crawler without good description. Or any described purpose at all. Block it
            $simpleUserAgent = "Suspicious/cloudsystemnetworks.com";
            $denyAccess = 1;
        } elsif($useragentname =~ /trendsmapresolver/i) {
            # Strange crawler, can't find anything concrete about it. Make it go away
            $simpleUserAgent = "Suspicious/trendsmapresolver";
            $denyAccess = 1;
        } elsif($useragentname =~ /vebidoobot/i) {
            # "person search crawler". In my opinion, this violates the EU General Data Protection Regulation, so block it
            $simpleUserAgent = "GDPR violation/vebidoobot";
            $denyAccess = 1;
        } elsif($useragentname =~ /wappalyzer/i) {
            # Strange crawler that analyses technology used by a website. Accept it, at least for now
            $simpleUserAgent = "Suspicious/Wappalyzer";
        } elsif($useragentname =~ /linkfluence\.com/i) {
            # Strange crawler that does "social data research". Block it
            $simpleUserAgent = "Suspicious/linkfluence.com";
            $denyAccess = 1;
        } elsif($useragentname =~ /pleskbot/i) {
            # "Server DDOS protection". I don't use it, so deny access
            $simpleUserAgent = "Suspicious/PleskBot";
            $denyAccess = 1;
        } elsif($useragentname =~ /getpocket\.com/i) {
            # Website aggregation tool. Accept it.... for now
            $simpleUserAgent = "Aggregation/getpocket.com";
        } elsif($useragentname =~ /sogou\.com/i) {
            # Chinese search engine
            $simpleUserAgent = "Search/Chinese/sogou";
        } elsif($useragentname =~ /researchbot/i) {
            # unknown crawler with the name "researchbot". This is too generic a name to block.
            $simpleUserAgent = "Suspicious/ResearchBot";
        } elsif($useragentname =~ /symfony\ browserkit/i) {
            # Generic toolkit/library for web automation. As far as i can see, similar to www::mechanize and stuff. Accept it for now
            $simpleUserAgent = "Suspicious/Symfony BrowserKit";
        } elsif($useragentname =~ /thither\.direct/i) {
            #  Not sure, seems to be marketing. Block it.
            $simpleUserAgent = "Suspicious/Thither.Direct";
            $denyAccess = 1;
        } elsif($useragentname =~ /MauiBot/i) {
            # Seems kind of a new bot, not much info, but according to forums at least tries to comply to robots.txt
            $simpleUserAgent = "MauiBot";
        } elsif($useragentname =~ /datenbutler\.de/i) {
            # Seems to sell access for searching webshops and blogs. Block it.
            $simpleUserAgent = "Suspicious/datenbutler.de";
            $denyAccess = 1;
        } elsif($useragentname =~ /nlpproject\.info/i) {
            # Crawler that doesn't provide ANY info (website down)
            $simpleUserAgent = "Suspicious/nlpproject.info";
            $denyAccess = 1;
        } elsif($useragentname =~ /tracemyfile\.com/i) {
            # See who copied whos images. Seems kinda useful
            $simpleUserAgent = "tracemyfile.com";
        } elsif($useragentname =~ /backlinktest\.com/i) {
            # Some german backlink tester. Seem like a genuine (private) research project
            $simpleUserAgent = "BacklinkCrawler";
        } elsif($useragentname =~ /istellabot\//i) {
            # Some italian ISP search engine
            $simpleUserAgent = "ISP/istellabot";
        } elsif($useragentname =~ /commoncrawl\.org/i) {
            # provides "copies of the internet for research". Ugh...
            $simpleUserAgent = "CommonCrawl scraper";
            $denyAccess = 1;
        } elsif($useragentname =~ /re\-re\.ru/i) {
            # Soem online flash tool. Didn't look any further than that, let it die.
            $simpleUserAgent = "Re-Re Studio";
            $denyAccess = 1;
        } elsif($useragentname =~ /ltx71/i) {
            # LTX71 "crawling the net for research purposes" without giving a hint what the research is about.
            # Yeah, right, fuck you.
            $simpleUserAgent = "LTX71/unknown";
            $denyAccess = 1;
        } elsif($useragentname =~ /findxbot/i) {
            $simpleUserAgent = "FindXBot/spambot";
            $denyAccess = 1;
        } elsif($useragentname =~ /daum\.net/i) {
            $simpleUserAgent = "Daum/webscraper";
            $denyAccess = 1;
        } elsif($useragentname =~ /gluten\ free\ crawler/i) {
            # Strange crawler, missing privacy clauses and no hint how the data gets used
            $simpleUserAgent = "GlutenFree/suspicious";
            $denyAccess = 1;
        } elsif($useragentname =~ /^web\ fire\ spider/i) {
            # SEO garbage
            $simpleUserAgent = "WebFire.com/SEO";
            $denyAccess = 1;
        } elsif($useragentname =~ /Nutch\-/i) {
            # SEO garbage
            $simpleUserAgent = "Nutch/SEO";
            $denyAccess = 1;
        } elsif($useragentname =~ /linkdex\.com/i) {
            # SEO garbage
            $simpleUserAgent = "Linkdex/SEO";
            $denyAccess = 1;
        } elsif($useragentname =~ /SemrushBot/i) {
            # "SEO consulting"
            $simpleUserAgent = "Semrush/SEO";
            $denyAccess = 1;
        } elsif($useragentname =~ /ubermetrics\-technologies\.com/i) {
            # Data reseller? SEO? Who cares?
            $simpleUserAgent = "Ubermetrics/SEO";
            $denyAccess = 1;
        } elsif($useragentname =~ /^masscan\//i) {
            # Portscanner. Don't need it
            $simpleUserAgent = "masscan/portsca";
            $denyAccess = 1;
        } elsif($useragentname =~ /adscanner\//i) {
            # Portscanner. Don't need it
            $simpleUserAgent = "Adscanner";
            $denyAccess = 1;
        } elsif($useragentname =~ /megaindex/i) {
            # bandwidth wasting crawler
            $simpleUserAgent = "MegaIndex";
            $denyAccess = 1;
        } elsif($useragentname =~ /7ooo\.ru/i) {
            # very strange russion site, let's block its crawler
            $simpleUserAgent = "7ooo.ru";
            $denyAccess = 1;
        } elsif($useragentname =~ /A6\-Indexer/i) {
            # Web scraper hosted in Amazon cloud
            $simpleUserAgent = "A6-Indexer";
            $denyAccess = 1;
        } elsif($useragentname =~ /Barkrowler/i || $useragentname =~ /exensa\.com/) {
            # "Big data analysis", yeah, right, go fuck yourself
            $simpleUserAgent = "Barkrowler";
            $denyAccess = 1;
        } elsif($useragentname =~ /bot\.myoha\.at/i) {
            # scrapes email anmd postal adresses
            $simpleUserAgent = "myoha adress scraper";
            $denyAccess = 1;
        } else {
            $simpleUserAgent = 'REALLY_UNKNOWN';
        }
    }

    return ($simpleUserAgent, $denyAccess);
}


1;
__END__

=head1 NAME

PageCamel::Helpers::UserAgent - try to decode a UserAgent string into a "simplified" version

=head1 SYNOPSIS

  use PageCamel::Helpers::UserAgent;

=head1 DESCRIPTION

This tries to decode useragent strings into a simplified version that is easier to read and understand. This is far from perfekt, but it helps a lot. It also marks some useragents as "bad".

=head2 simplifyUA

Simplifies a useragent string.

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

Copyright (C) 2008-2019 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
