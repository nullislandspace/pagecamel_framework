package PageCamel::Protocol::HTTP2::StaticTable;
#---AUTOPRAGMASTART---
use v5.40;
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
use parent qw(Exporter);
our ( @stable, %rstable );
our @EXPORT = qw(@stable %rstable);

@stable = (
    [ ":authority",                  "" ],
    [ ":method",                     "GET" ],
    [ ":method",                     "POST" ],
    [ ":path",                       "/" ],
    [ ":path",                       "/index.html" ],
    [ ":scheme",                     "http" ],
    [ ":scheme",                     "https" ],
    [ ":status",                     "200" ],
    [ ":status",                     "204" ],
    [ ":status",                     "206" ],
    [ ":status",                     "304" ],
    [ ":status",                     "400" ],
    [ ":status",                     "404" ],
    [ ":status",                     "500" ],
    [ "accept-charset",              "" ],
    [ "accept-encoding",             "gzip, deflate" ],
    [ "accept-language",             "" ],
    [ "accept-ranges",               "" ],
    [ "accept",                      "" ],
    [ "access-control-allow-origin", "" ],
    [ "age",                         "" ],
    [ "allow",                       "" ],
    [ "authorization",               "" ],
    [ "cache-control",               "" ],
    [ "content-disposition",         "" ],
    [ "content-encoding",            "" ],
    [ "content-language",            "" ],
    [ "content-length",              "" ],
    [ "content-location",            "" ],
    [ "content-range",               "" ],
    [ "content-type",                "" ],
    [ "cookie",                      "" ],
    [ "date",                        "" ],
    [ "etag",                        "" ],
    [ "expect",                      "" ],
    [ "expires",                     "" ],
    [ "from",                        "" ],
    [ "host",                        "" ],
    [ "if-match",                    "" ],
    [ "if-modified-since",           "" ],
    [ "if-none-match",               "" ],
    [ "if-range",                    "" ],
    [ "if-unmodified-since",         "" ],
    [ "last-modified",               "" ],
    [ "link",                        "" ],
    [ "location",                    "" ],
    [ "max-forwards",                "" ],
    [ "proxy-authenticate",          "" ],
    [ "proxy-authorization",         "" ],
    [ "range",                       "" ],
    [ "referer",                     "" ],
    [ "refresh",                     "" ],
    [ "retry-after",                 "" ],
    [ "server",                      "" ],
    [ "set-cookie",                  "" ],
    [ "strict-transport-security",   "" ],
    [ "transfer-encoding",           "" ],
    [ "user-agent",                  "" ],
    [ "vary",                        "" ],
    [ "via",                         "" ],
    [ "www-authenticate",            "" ],
    # Note: RFC 8441 :protocol pseudo-header is NOT in the HPACK static table.
    # It's encoded using literal representation, not indexed.
);

for my $k ( 0 .. $#stable ) {
    my $key = join ' ', @{ $stable[$k] };
    $rstable{$key} = $k + 1;
    $rstable{ $stable[$k]->[0] . ' ' } = $k + 1
      if ( $stable[$k]->[1] ne ''
        && !exists $rstable{ $stable[$k]->[0] . ' ' } );
}

1;
