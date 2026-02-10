package PageCamel::Helpers::UserAgent;
#---AUTOPRAGMASTART---
use v5.42;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 5.0;
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

use base qw(Exporter);
our @EXPORT_OK = qw(simplifyUA);

use HTTP::BrowserDetect;

sub simplifyUA($useragentname) {
    my $simpleUserAgent = '';
    my $denyAccess = 0;

    my $browser = HTTP::BrowserDetect->new($useragentname);
    my $browserName = $browser->browser_string();
    my $majorVersion = $browser->browser_major();

    if($useragentname eq '' || $useragentname eq "''") { ## no critic (ControlStructures::ProhibitCascadingIfElse)
        $useragentname = '--unknown--';
    } elsif($useragentname =~ /CC Client\/(\d+)/o) {
        $simpleUserAgent = "CC Client/$1";
    } elsif($useragentname eq "CCOld Bot") {
        $simpleUserAgent = "CC Client/1";
    } elsif($useragentname eq "--unknown--" ) {
        $simpleUserAgent = "NONE";
    } elsif($useragentname =~ /XML\-RPC/o) {
        $simpleUserAgent = "XML-RPC";
    } elsif($useragentname =~ /Scarecrow\/(\d+)/o) {
        $simpleUserAgent = "Scarecrow/$1";
    } elsif($useragentname =~ /RBSDirect\/(.*)/o) {
        $simpleUserAgent = "RBSDirect/$1";
    } elsif($useragentname =~ /PonyExpress\/(\d+)/o) {
        $simpleUserAgent = "PonyExpress/$1";
    } elsif($useragentname =~ /PageCamel LetsEncrypt\/(\d+)/o) {
        $simpleUserAgent = "PageCamel LetsEncrypt/$1";
    } elsif($useragentname =~ /PTouch\/(\d+)/o) {
        $simpleUserAgent = "PTouch/$1";
    } elsif($useragentname =~ /mercurial\/proto-(\d+)/o) {
        $simpleUserAgent = "Mercurial/Proto $1";
    } elsif($useragentname =~ /Microsoft\ Office\ (.*)\ Discovery/o) {
        $simpleUserAgent = "MSOffice $1 Discovery";
    } elsif($useragentname =~ /WWW\-Mechanize\/(\d+)/io) {
        $simpleUserAgent = "Mechanize/$1";
    } elsif($useragentname =~ /Java.*SDK/io) {
        $simpleUserAgent = "JAVA SDK";
    } elsif($useragentname =~ /Java\/.*/io) {
        $simpleUserAgent = "JAVA";
    } elsif($useragentname =~ /ssllabs\.com/io) {
        $simpleUserAgent = "SSL Labs Checker";
    } elsif($useragentname =~ /mostly.*cavac.at/io) {
        $simpleUserAgent = "cavac";
    } elsif($useragentname =~ /(DavClnt)/io) {
        $simpleUserAgent = "Potential_Virus/" . lc($1);
    } elsif($useragentname =~ /Discordbot/io) {
        $simpleUserAgent = "DiscordBot";
    } elsif($useragentname =~ /(ZmEu|Morfeus|Comodo\ ssl\ checker)/io) {
        $simpleUserAgent = "Virus/" . lc($1);
        $denyAccess = 1;
    } elsif($useragentname =~ /(bingbot|googlebot|pagesinventory|feedfetcher\-google|plukkie|msnbot|yandex|google\-desktop|seznambot|turnitinbot|baidu|yahoo\!\ slurp|nerdybot|orangebot|twitterbot|paperlibot|duckduckgo|qwantify|xforce\-security\.com)/io) { ## no critic (RegularExpressions::ProhibitComplexRegexes RegularExpressions::RequireExtendedFormatting)
        $simpleUserAgent = "Webspider_good/" . lc($1);
    } elsif($useragentname =~ /(netcraft.*survey|synapse|phpcrawl|wotbox|yacybot|zend_http_client|mail.ru\_bot|spbot|crazywebcrawler|go.*package\ http)/io) {
        $simpleUserAgent = "Webspider_undecided/" . lc($1);
    } elsif($useragentname =~ /(indy\ library|ezooms|mj12bot|wbsearchbot|webcollage|exabot|meanpathbot|binaryedge)/io) {
        $simpleUserAgent = "Webspider_probation/" . lc($1);
        $denyAccess = 0;
    } elsif($useragentname =~ /^axios\//io) {
        $simpleUserAgent = "nodejs/axios";
    } elsif($useragentname =~ /(x00_-gawa.sa.pilipinas.2015|blexbot|ahrefsbot|seostats|seokicks|seostar\.co|dataforseo\.com|censys\.io|paloaltonetworks\.com|expanseinc\.com|dotbot)/io) {
        $simpleUserAgent = "Webspider_bad/" . lc($1);
        $denyAccess = 1;
    } elsif($useragentname =~ /(alittle\ client|hello\, world|dataprovider\.com)/io) {
        $simpleUserAgent = "Webspider_bad/" . lc($1);
        $denyAccess = 1;
    } elsif($useragentname =~ /nmap\ scripting\ engine/io) {
        $simpleUserAgent = "Hacker/NMAP";
        $denyAccess = 1;
    } elsif($useragentname =~ /(monitis)/io) {
        $simpleUserAgent = "DOS_ATTACK/" . lc($1);
        $denyAccess = 1;
    } elsif($useragentname =~ /CPAN\:\:MINI/io) {
        $simpleUserAgent = "CPAN-MINI";
    } elsif($useragentname =~ /AdsTxtCrawler/o) {
        $simpleUserAgent = "AdsTxtCrawler/ads.txt";
    } elsif($useragentname =~ /miniflux\.app/io) {
        $simpleUserAgent = "FeedReader/MiniFlux";
    } elsif($useragentname =~ /NextCloud\-News/io) {
        $simpleUserAgent = "FeedReader/NextCloud-News";
    } elsif($useragentname =~ /entferbot/io) {
        $simpleUserAgent = "SearchEngine/EntferBot";
    } elsif($useragentname =~ /LWP\:\:Simple/io) {
        $simpleUserAgent = "LWP-Simple";
    } elsif($useragentname =~ /ISOCIPv6Bot/io) {
        $simpleUserAgent = "IPv6 Checker Bot";
    } elsif($useragentname =~ /Magic\ Browser/io) {
        $simpleUserAgent = "Magic Browser";
    } elsif($useragentname =~ /Fritz.Box/io) {
        $simpleUserAgent = "Fritz!Box";
    } elsif($useragentname =~ /(?:libwww-perl|LWP)/io) {
        $simpleUserAgent = "LWP";
    } elsif($useragentname =~ /wget/io) {
        $simpleUserAgent = "wget";
    } elsif($useragentname =~ /curl/io) {
        $simpleUserAgent = "curl";
    } elsif($useragentname =~ /python\-requests/io) {
        $simpleUserAgent = "python";
    } elsif($useragentname =~ /Microsoft-WebDAV-MiniRedir/io) {
        $simpleUserAgent = "Microsoft WebDAV";
    } elsif($useragentname =~ /facebookexternalhit/io || $useragentname =~ /facebook.*externalhit/o) {
        $simpleUserAgent = "Facebook";
    } elsif($useragentname =~ /bitlybot\/(.*?)\ /o) {
        $simpleUserAgent = "Bit.ly/$1";
    } elsif($useragentname =~ /Cliqzbot\/(.*?)\ /io) {
        $simpleUserAgent = "Cliqz.com/$1";
    } elsif($useragentname =~ /redditbot\/(.*?)\;/o) {
        $simpleUserAgent = "RedditBot/$1";
    } elsif($useragentname =~ /^newspaper\//o) {
        $simpleUserAgent = "Python/Newspaperlib";
    } elsif($useragentname =~ /^python\-urllib/io) {
        $simpleUserAgent = "Python/urllib";
    } elsif($useragentname =~ /^python.*aiohttp/io) {
        $simpleUserAgent = "Python/aiohttp";
    } elsif($useragentname =~ /^Ruby$/o) {
        $simpleUserAgent = "Ruby";
    } elsif($useragentname =~ /^okhttp\//o) {
        $simpleUserAgent = "Java/okhttplib";
    } elsif($useragentname =~ /^slackbot\-linkexpanding\ (.*?)\ /i || $useragentname =~ /^Slackbot\ (.*?)\ /io) {
        $simpleUserAgent = "Slackbot/$1";
    } elsif($useragentname =~ /^AlienBlue/o) {
        $simpleUserAgent = "AlienBlue-Browser";
    } elsif($useragentname =~ /^SafeDNSBot/o) {
        $simpleUserAgent = "SafeDNS/ContentBlocker"; # Used by families and companies to only allow specific categories of content
    } elsif($useragentname =~ /^Dillo\//o) {
        $simpleUserAgent = "Dillo-Browser";
    } elsif($useragentname =~ /go\-http\-client\/(.*?)/io) {
        $simpleUserAgent = "GO-HTTP/$1";
    } elsif($useragentname =~ /windows\-media\-player\/(.*?)/io) {
        $simpleUserAgent = "MS/MediaPlayer/$1";
    } elsif($useragentname =~ /www\.karriere\.at/o) {
        $simpleUserAgent = "Jobs/karriere.at";
    } elsif($useragentname =~ /www\.metajob\.at/o) {
        $simpleUserAgent = "Jobs/metajob.at";
    } elsif($useragentname =~ /^com\.google\.GoogleMobile/io) {
        $simpleUserAgent = "GoogleBot/Mobile";
    } elsif($useragentname =~ /Google\-Site\-Verification/io) {
        $simpleUserAgent = "GoogleBot/Site-Verification";
    } elsif($useragentname =~ /alexa\ site\ audit/io) {
        $simpleUserAgent = "AlexaBot";
    } elsif($useragentname =~ /^archive\.org/io || $useragentname =~ /wayback\ machine/io || $useragentname =~ /www\.archive\.org/io) {
        $simpleUserAgent = "Archive.org";
    } elsif($useragentname =~ /coccocbot\-web/o) {
        $simpleUserAgent = "Coccoc.co/Web (Vietnam)";
    } elsif($useragentname =~ /coccocbot\-image/o) {
        $simpleUserAgent = "Coccoc.co/Image (Vietnam)";
    } elsif($useragentname =~ /^GarlikCrawler/o) {
        $simpleUserAgent = "Garlik.com";
    } elsif($useragentname =~ /Uptimebot/o || $useragentname =~ /Uptime\.com/o) {
        $simpleUserAgent = "Uptime.com"; # Seems useful, more or less
    } elsif($useragentname =~ /soup\.io/o) {
        $simpleUserAgent = "Soup.IO";
    } elsif($useragentname =~ /^BUbiNG/o) {
        $simpleUserAgent = "BUbiNG"; # Some university experimental crawler. Let it in for now
    } elsif($useragentname =~ /^WizeNoze\ Discovery\ Crawler/io) {
        $simpleUserAgent = "Wizenoze.com"; # Some child learning thingamabobcrawler. Let it in for now
    } elsif($useragentname =~ /^CSS\ Certificate\ Spider\ /o) {
        $simpleUserAgent = "CertChecker"; # Seems to check/cache SSL public certs, seems legit
    } elsif($useragentname =~ /^Nuzzel$/o) {
        $simpleUserAgent = "Nuzzel/NewsCollector"; # Seems legit
    } elsif($useragentname =~ /researchscan\.comsys\.rwth\-aachen\.de/io) {
        # Some university security research
        $simpleUserAgent = "Research/RWTH_Achen_Uni";
    } elsif($useragentname =~ /netsystemsresearch\.com/io) {
        # Some IoT security research
        $simpleUserAgent = "Research/IoT";
    } elsif($useragentname =~ /Akregator/io) {
        # Part of KDE it seems
        $simpleUserAgent = "KDE/Akregator";
    } elsif($useragentname =~ /CakePHP/io) {
        # CakePHP
        $simpleUserAgent = "CakePHP";
    } elsif($useragentname =~ /com\.google\.android\.apps\.searchlite/io) {
        # Google Go?
        $simpleUserAgent = "Google Go/searchlite";
    } elsif($useragentname =~ /mindup\.de/io) {
        # mindup.de "Marketing using artificial intelligence"
        $simpleUserAgent = "Marketing/mindup.de";
        $denyAccess = 1;
    } elsif($useragentname =~ /facebook.*externalhit/io) {
        # Facebook
        $simpleUserAgent = "Facebook";
    } elsif($useragentname =~ /di\-cloud\-parser/io) {
        # I have NO idea what that is supposed to be. For now, let it in
        $simpleUserAgent = "di-cloud-parser";
    } elsif($useragentname =~ /security\.ipip\.net/io) {
        # Chinese "Security" site that collects data on http headers and open ports. Block it
        $simpleUserAgent = "Suspicious/security.ipip.net";
        $denyAccess = 1;
    } elsif($useragentname =~ /^m$/io) {
        # Whatever the hell this is, is highly strange. Let's just block it. As far as i can see, it's some kind of crawler
        $simpleUserAgent = "Suspicious/M";
        $denyAccess = 1;
    } elsif($useragentname =~ /mediatoolkit\.com/io) {
        # Another of those strange "brand protection" crawlers. Go to hell
        $simpleUserAgent = "BrandProtection/mediatoolkit.com";
        $denyAccess = 1;
    } elsif($useragentname =~ /domainsono\.com/io) {
        # Crawler, but the domain is currently "for sale". Block it
        $simpleUserAgent = "Suspicious/domainsono.com";
        $denyAccess = 1;
    } elsif($useragentname =~ /crawler\@alexa\.com/io) {
        # Alexa crawler
        $simpleUserAgent = "Alexa";
    } elsif($useragentname =~ /cloudsystemnetworks\.com/io) {
        # Crawler without good description. Or any described purpose at all. Block it
        $simpleUserAgent = "Suspicious/cloudsystemnetworks.com";
        $denyAccess = 1;
    } elsif($useragentname =~ /trendsmapresolver/io) {
        # Strange crawler, can't find anything concrete about it. Make it go away
        $simpleUserAgent = "Suspicious/trendsmapresolver";
        $denyAccess = 1;
    } elsif($useragentname =~ /vebidoobot/io) {
        # "person search crawler". In my opinion, this violates the EU General Data Protection Regulation, so block it
        $simpleUserAgent = "GDPR violation/vebidoobot";
        $denyAccess = 1;
    } elsif($useragentname =~ /wappalyzer/io) {
        # Strange crawler that analyses technology used by a website. Accept it, at least for now
        $simpleUserAgent = "Suspicious/Wappalyzer";
    } elsif($useragentname =~ /linkfluence\.com/io) {
        # Strange crawler that does "social data research". Block it
        $simpleUserAgent = "Suspicious/linkfluence.com";
        $denyAccess = 1;
    } elsif($useragentname =~ /pleskbot/io) {
        # "Server DDOS protection". I don't use it, so deny access
        $simpleUserAgent = "Suspicious/PleskBot";
        $denyAccess = 1;
    } elsif($useragentname =~ /getpocket\.com/io) {
        # Website aggregation tool. Accept it.... for now
        $simpleUserAgent = "Aggregation/getpocket.com";
    } elsif($useragentname =~ /sogou\.com/io) {
        # Chinese search engine
        $simpleUserAgent = "Search/Chinese/sogou";
    } elsif($useragentname =~ /researchbot/io) {
        # unknown crawler with the name "researchbot". This is too generic a name to block.
        $simpleUserAgent = "Suspicious/ResearchBot";
    } elsif($useragentname =~ /symfony\ browserkit/io) {
        # Generic toolkit/library for web automation. As far as i can see, similar to www::mechanize and stuff. Accept it for now
        $simpleUserAgent = "Suspicious/Symfony BrowserKit";
    } elsif($useragentname =~ /petalsearch\.com/io) {
        # Aggressive search engine
        $simpleUserAgent = "Webspider_bad/Petalbot";
        $denyAccess = 1;
    } elsif($useragentname =~ /thither\.direct/io) {
        #  Not sure, seems to be marketing. Block it.
        $simpleUserAgent = "Suspicious/Thither.Direct";
        $denyAccess = 1;
    } elsif($useragentname =~ /MauiBot/io) {
        # Seems kind of a new bot, not much info, but according to forums at least tries to comply to robots.txt
        $simpleUserAgent = "MauiBot";
    } elsif($useragentname =~ /datenbutler\.de/io) {
        # Seems to sell access for searching webshops and blogs. Block it.
        $simpleUserAgent = "Webspider_bad/datenbutler.de";
        $denyAccess = 1;
    } elsif($useragentname =~ /openai\.com/io) {
        # ShitGPT aka ChatGPT
        $simpleUserAgent = "Webspider_bad/openai-chatgpt";
        $denyAccess = 1;
    } elsif($useragentname =~ /nlpproject\.info/io) {
        # Crawler that doesn't provide ANY info (website down)
        $simpleUserAgent = "Suspicious/nlpproject.info";
        $denyAccess = 1;
    } elsif($useragentname =~ /tracemyfile\.com/io) {
        # See who copied whos images. Seems kinda useful
        $simpleUserAgent = "tracemyfile.com";
    } elsif($useragentname =~ /backlinktest\.com/io) {
        # Some german backlink tester. Seem like a genuine (private) research project
        $simpleUserAgent = "BacklinkCrawler";
    } elsif($useragentname =~ /istellabot\//io) {
        # Some italian ISP search engine
        $simpleUserAgent = "ISP/istellabot";
    } elsif($useragentname =~ /commoncrawl\.org/io) {
        # provides "copies of the internet for research". Ugh...
        $simpleUserAgent = "CommonCrawl scraper";
        $denyAccess = 1;
    } elsif($useragentname =~ /re\-re\.ru/io) {
        # Soem online flash tool. Didn't look any further than that, let it die.
        $simpleUserAgent = "Re-Re Studio";
        $denyAccess = 1;
    } elsif($useragentname =~ /ltx71/io) {
        # LTX71 "crawling the net for research purposes" without giving a hint what the research is about.
        # Yeah, right, fuck you.
        $simpleUserAgent = "LTX71/unknown";
        $denyAccess = 1;
    } elsif($useragentname =~ /findxbot/io) {
        $simpleUserAgent = "FindXBot/spambot";
        $denyAccess = 1;
    } elsif($useragentname =~ /daum\.net/io) {
        $simpleUserAgent = "Daum/webscraper";
        $denyAccess = 1;
    } elsif($useragentname =~ /gluten\ free\ crawler/io) {
        # Strange crawler, missing privacy clauses and no hint how the data gets used
        $simpleUserAgent = "GlutenFree/suspicious";
        $denyAccess = 1;
    } elsif($useragentname =~ /^web\ fire\ spider/io) {
        # SEO garbage
        $simpleUserAgent = "WebFire.com/SEO";
        $denyAccess = 1;
    } elsif($useragentname =~ /Nutch\-/io) {
        # SEO garbage
        $simpleUserAgent = "Nutch/SEO";
        $denyAccess = 1;
    } elsif($useragentname =~ /linkdex\.com/io) {
        # SEO garbage
        $simpleUserAgent = "Linkdex/SEO";
        $denyAccess = 1;
    } elsif($useragentname =~ /SemrushBot/io) {
        # "SEO consulting"
        $simpleUserAgent = "Semrush/SEO";
        $denyAccess = 1;
    } elsif($useragentname =~ /ubermetrics\-technologies\.com/io) {
        # Data reseller? SEO? Who cares?
        $simpleUserAgent = "Ubermetrics/SEO";
        $denyAccess = 1;
    } elsif($useragentname =~ /^masscan\//io) {
        # Portscanner. Don't need it
        $simpleUserAgent = "masscan/portsca";
        $denyAccess = 1;
    } elsif($useragentname =~ /adscanner\//io) {
        # Portscanner. Don't need it
        $simpleUserAgent = "Adscanner";
        $denyAccess = 1;
    } elsif($useragentname =~ /megaindex/io) {
        # bandwidth wasting crawler
        $simpleUserAgent = "MegaIndex";
        $denyAccess = 1;
    } elsif($useragentname =~ /7ooo\.ru/io) {
        # very strange russion site, let's block its crawler
        $simpleUserAgent = "7ooo.ru";
        $denyAccess = 1;
    } elsif($useragentname =~ /A6\-Indexer/io) {
        # Web scraper hosted in Amazon cloud
        $simpleUserAgent = "A6-Indexer";
        $denyAccess = 1;
    } elsif($useragentname =~ /Barkrowler/io || $useragentname =~ /exensa\.com/o) {
        # "Big data analysis", yeah, right, go fuck yourself
        $simpleUserAgent = "Barkrowler";
        $denyAccess = 1;
    } elsif($useragentname =~ /bot\.myoha\.at/io) {
        # scrapes email anmd postal adresses
        $simpleUserAgent = "myoha adress scraper";
        $denyAccess = 1;
    } else {
        if(defined($browserName) && defined($majorVersion)) {
            $simpleUserAgent = $browserName . '/' . $majorVersion;
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

Copyright (C) 2008-2020 Rene Schickbauer

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.

=cut
