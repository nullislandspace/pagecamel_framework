package PageCamel::WebBase;
#---AUTOPRAGMASTART---
use v5.38;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.3;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use builtin qw[true false is_bool];
no warnings qw(experimental::builtin);
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---

#=!=START-AUTO-INCLUDES
use PageCamel::Web::Accesslog;
use PageCamel::Web::AccesslogDetail;
use PageCamel::Web::AuditlogDetail;
use PageCamel::Web::BaseModule;
use PageCamel::Web::BaseWebSocket;
use PageCamel::Web::Blog::Viewer;
use PageCamel::Web::BrowserWorkarounds;
use PageCamel::Web::CSPHeader;
use PageCamel::Web::Cables::Browse;
use PageCamel::Web::Cables::Search;
use PageCamel::Web::Cables::View;
use PageCamel::Web::ClacksCache;
use PageCamel::Web::CommandQueue;
use PageCamel::Web::ComputerDB::Computers;
use PageCamel::Web::DatablobLoader;
use PageCamel::Web::DirCleaner;
use PageCamel::Web::DirSync::DirSync;
use PageCamel::Web::DynDNS;
use PageCamel::Web::DynamicFiles::Blob;
use PageCamel::Web::DynamicFiles::External;
use PageCamel::Web::Errors;
use PageCamel::Web::ExtraConfig;
use PageCamel::Web::ExtraHTTPHeaders;
use PageCamel::Web::FakeFiles;
use PageCamel::Web::Firewall::AutoBlockByUrl;
use PageCamel::Web::Firewall::BadBot;
use PageCamel::Web::Firewall::BlockCIDR;
use PageCamel::Web::Firewall::BlockIP;
use PageCamel::Web::Firewall::EC2Attack;
use PageCamel::Web::Firewall::Floodcheck;
use PageCamel::Web::Firewall::Hostname;
use PageCamel::Web::ForceFavicon;
use PageCamel::Web::ForceSSL;
use PageCamel::Web::ForceTransportSecurity;
use PageCamel::Web::HTTPCompression;
use PageCamel::Web::Impressum;
use PageCamel::Web::ListAndEdit::ASpell;
use PageCamel::Web::ListAndEdit::Files;
use PageCamel::Web::ListAndEdit::Images;
use PageCamel::Web::ListAndEdit::Main;
use PageCamel::Web::Lists::BadPasswords;
use PageCamel::Web::Lists::DNSBlocks;
use PageCamel::Web::Lists::IPBlocks;
use PageCamel::Web::Livestream::ManageStream;
use PageCamel::Web::Livestream::ServeM3U8;
use PageCamel::Web::Livestream::ServeM3U8Archive;
use PageCamel::Web::Livestream::ShowStream;
use PageCamel::Web::Livestream::ShowStreamArchive;
use PageCamel::Web::Logging::Devices;
use PageCamel::Web::Logging::Graphs;
use PageCamel::Web::Logging::Report;
use PageCamel::Web::Logging::WebAPI;
use PageCamel::Web::Mercurial::Proxy;
use PageCamel::Web::Minecraft::Players;
use PageCamel::Web::OSMTiles;
use PageCamel::Web::PGAdmin4Proxy;
use PageCamel::Web::PTouch::Computers;
use PageCamel::Web::PTouch::Settings;
use PageCamel::Web::PTouch::WebAPI;
use PageCamel::Web::PageCamelStats;
use PageCamel::Web::PageViewStats;
use PageCamel::Web::PathRedirection;
use PageCamel::Web::PluginConfig;
use PageCamel::Web::PostgresDB;
use PageCamel::Web::PreventGetWithArgs;
use PageCamel::Web::PrivacyPolicy;
use PageCamel::Web::Reporting;
use PageCamel::Web::RootFiles;
use PageCamel::Web::SendMail;
use PageCamel::Web::SessionSettings;
use PageCamel::Web::StandardFields;
use PageCamel::Web::StaticCache;
use PageCamel::Web::StaticPage;
use PageCamel::Web::StreetMap;
use PageCamel::Web::Style::Fonts;
use PageCamel::Web::Style::Menubars;
use PageCamel::Web::Style::Themes;
use PageCamel::Web::SystemSettings;
use PageCamel::Web::TemplateCache;
use PageCamel::Web::Testing::Microphone;
use PageCamel::Web::Testing::VoiceComm;
use PageCamel::Web::Tools::AccessToDebuglog;
use PageCamel::Web::Tools::Adsense;
use PageCamel::Web::Tools::ClacksConsole;
use PageCamel::Web::Tools::ContentSecurityPolicyViolation;
use PageCamel::Web::Tools::DSKY;
use PageCamel::Web::Tools::DebugWebHangups;
use PageCamel::Web::Tools::Debuglog;
use PageCamel::Web::Tools::ExecuteScript;
use PageCamel::Web::Tools::HostnameRedirect;
use PageCamel::Web::Tools::KaffeeSim;
use PageCamel::Web::Tools::PIMenu;
use PageCamel::Web::Tools::RemoteConsoleLog;
use PageCamel::Web::Tools::RemoteLog;
use PageCamel::Web::Tools::SQLJS;
use PageCamel::Web::Tools::ScriptDownload;
use PageCamel::Web::Tools::ShortURL;
use PageCamel::Web::Tools::Sitemap;
use PageCamel::Web::Tools::WebDrive;
use PageCamel::Web::Tools::WorkerControl;
use PageCamel::Web::Translate;
use PageCamel::Web::Users::GroupEdit;
use PageCamel::Web::Users::Login;
use PageCamel::Web::Users::PWChange;
use PageCamel::Web::Users::PWReset;
use PageCamel::Web::Users::Register;
use PageCamel::Web::Users::Settings;
use PageCamel::Web::Users::UserEdit;
use PageCamel::Web::Users::Userlevels;
use PageCamel::Web::Users::Views;
use PageCamel::Web::VNC5;
use PageCamel::Web::WebApi::LetsEncryptDNS;
use PageCamel::Web::WebApps;
use PageCamel::Web::Webcam;
use PageCamel::Web::Wiki::Articles;
use PageCamel::Web::Wiki::Viewer;
#=!=END-AUTO-INCLUDES

use Template;
use FileHandle;
use Socket;
use Module::Load;
use PageCamel::Helpers::DateStrings;
use PageCamel::Helpers::URI qw(decode_uri_part decode_uri_path);

use Time::HiRes qw[time sleep alarm];

use Digest::MD5 qw(md5_hex);
use PageCamel::Helpers::WebPrint;

my %httpstatuscodes = (
    100 => "Continue",
    101 => "Switching Protocols",
    102 => "Processing",
    200 => "OK",
    201 => "Created",
    202 => "Accepted",
    203 => "Non-Authoritive Information",
    204 => "No Content",
    205 => "Reset Content",
    206 => "Partial Content",
    207 => "Multi-Status",
    208 => "Already Reported",
    226 => "IM Used",
    230 => "Authentication Successful",
    300 => "Multiple Choices",
    301 => "Moved Permanently",
    302 => "Found",
    303 => "See other",
    304 => "Not modified",
    305 => "Use Proxy",
    306 => "(Unused)",
    307 => "Temporary Redirect",
    308 => "Permanent Redirect", ### EXPERIMENTAL RFC!!!
    400 => "Bad Request",
    401 => "Unauthorized",
    402 => "Payment Required",
    403 => "Forbidden",
    404 => "Not Found",
    405 => "Method Not Allowed",
    406 => "Not Acceptable",
    407 => "Proxy Authentification Required",
    408 => "Request Timeout",
    409 => "Conflict",
    410 => "Gone",
    411 => "Length Required",
    412 => "Precondition Failed",
    413 => "Request Entity Too Large",
    414 => "Request-URI Too Long",
    415 => "Unsupported Media Type",
    416 => "Requested Range Not Satisfiable",
    417 => "Expectation Failed",
    418 => "I'm a teapot",  # HTCPCP
    420 => "Enhance Your Calm", # Twitter
    422 => "Unprocessable Entity",
    423 => "Locked",
    424 => "Failed Dependency",
    425 => "Unordered Collection",
    426 => "Upgrade Required",
    428 => "Precondition Required",
    429 => "Too Many Requests",
    431 => "Request Header Fields Too Large",
    444 => "No Response", # Nginx
    449 => "Retry with", # Microsoft
    450 => "Blocked by Windows Parental Controls", # Microsoft
    451 => "Unavailable For Legal Reasons", # Internet Draft
    494 => "Request Header Too Large", # Nginx
    495 => "Cert Error", # Nginx
    496 => "No Cert", # Nginx
    497 => "HTTP to HTTPS", # Nginx
    499 => "Client Closed Request", # Nginx
    500 => "Internal Server Error",
    501 => "Not Implemented",
    502 => "Bad Gateway",
    503 => "Service Unavailable",
    504 => "Gateway Timeout",
    505 => "HTTP Version Not Supported",
    506 => "Variant Also Negotiates",
    507 => "Insufficient Storage",
    508 => "Loop Detected",
    509 => "Bandwidth Limit Exceeded",
    510 => "Not Extended",
    511 => "Network Authentication Required",
    531 => "Access Denied",
    598 => "Network read timeout error",
    599 => "Network connect timeout error",
);

my @httpheaders = qw[
    Accept
    Accept-Charset
    Accept-Datetime
    Accept-Encoding
    Accept-Language
    Accept-Patch
    Accept-Ranges
    Access-Control-Allow-Origin
    Access-Control-Request-Method
    Access-Control-Allow-Methods
    Access-Control-Max-Age
    Age
    Allow
    Authorization
    Cache-Control
    Connection
    Content-Disposition
    Content-Encoding
    Content-Language
    Content-Length
    Content-Location
    Content-MD5
    Content-Range
    Content-Security-Policy
    Content-Type
    Cookie
    Date
    DNT
    ETag
    Expect
    Expires
    From
    Front-End-Https
    Host
    If-Match
    If-Modified-Since
    If-None-Match
    If-Range
    If-Unmodified-Since
    Last-Modified
    Link
    Location
    Max-Forwards
    Origin
    P3P
    Pragma
    Proxy-Authenticate
    Proxy-Authorization
    Proxy-Connection
    Public-Key-Pins
    Range
    Referer
    Refresh
    Retry-After
    Sec-WebSocket-Extensions
    Sec-WebSocket-Key
    Sec-WebSocket-Protocol
    Sec-WebSocket-Version
    Server
    Set-Cookie
    Status
    Strict-Transport-Security
    TE
    Trailer
    Transfer-Encoding
    Upgrade
    User-Agent
    Vary
    Via
    Warning
    WWW-Authenticate
    X-ATT-DeviceId
    X-Content-Duration
    X-Content-Type-Options
    X-Csrf-Token
    X-Forwarded-For
    X-Forwarded-Host
    X-Forwarded-Proto
    X-Frame-Options
    X-Http-Method-Override
    X-Powered-By
    X-Requested-With
    X-UA-Compatible
    X-UIDH
    X-Wap-Profile
    X-XSS-Protection

    Content-Security-Policy
    X-Content-Security-Policy
    X-WebKit-CSP

];

my %httpheadersmapping;
foreach my $header (@httpheaders) {
    $httpheadersmapping{lc $header} = $header;
}

sub new($class, $config) {
    my $self = bless $config, $class;
        
    return $self;
}

sub processing_error_hook($self, @errors) {
    print STDERR "Unhandled exception: \n", join("\n", @errors);
    print STDERR "Suiciding (SIGINT)  / PID $PID\n";
    return 0;
}


sub allow_deny_hook($self, $peerhost) {

    $self->{last_accepted_client} = '0.0.0.0';

    if(!defined($peerhost)) {
        print STDERR "Undefined \$peerhost in allow_deny_hook\n";
        return 0;
    }

    if (!(defined $peerhost)) {
        print STDERR "Couldn't get peer name!\n";
        return 0;
    }

    if($peerhost =~ /^\:\:ffff\:(\d+\.\d+\.\d+\.\d+)/) {
        $peerhost = $1;
    }


    #print STDERR "Accepting connction from $client\n";
    $self->{last_accepted_client} = $peerhost;
    return 1;
};

sub post_process_request_hook($self) {

    #print STDERR "Closing connection to ", $self->{last_accepted_client}, "\n";
    $self->{last_accepted_client} = '0.0.0.0';

    return;
}

sub set_usessl($self, $usessl) {

    $self->{usessl} = $usessl;
    foreach my $modname (keys %{$self->{modules}}) {
        $self->{modules}->{$modname}->{usessl} = $usessl;
    }

    return;
}

sub child_init_hook($self) {

    if(0 && $self->{isDebugging}) {
        print STDERR "******************** CHILD START *********************\n";
    }
    foreach my $modname (keys %{$self->{modules}}) {
        $self->{modules}->{$modname}->handle_child_start;   # Notify a new child that it was just forked (re-init socket handles and such)
    }
    $self->{need_srand_call} = 1;

    return;
}

sub child_finish_hook($self) {

    if(0 && $self->{isDebugging}) {
        print STDERR "******************** CHILD STOP *********************\n";
    }
    foreach my $modname (keys %{$self->{modules}}) {
        $self->{modules}->{$modname}->handle_child_stop;   # Notify a child that it is about to be destroyed
    }

    return;
}

sub readheader($self, $timeout, $socket) {

    my $line;
    my $ok = 0;
    my $buf;

    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
        my $endtime = time + $timeout;

        while(1) {
            $buf = undef;
            #my $bufstatus = sysread($socket, $buf, 1);
            my $bufstatus = $socket->sysread($buf, 1);
            #if(defined($bufstatus) && !$bufstatus) {
            #    return;
            #}
            if(!defined($buf) || !length($buf)) {
                if(time > $endtime) {
                    last;
                }
                sleep(0.01);
                next;
            }
            $line .= $buf;
            last if($buf eq "\n");
        }
        if(time <= $endtime) {
            $ok = 1;
        }
    };
    if(!$ok || !defined($line)) {
        return;
    }

    $ok = 0;
    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
        my $temp = decode_utf8($line);
        $line = $temp;
        $ok = 1;
    };
    if(!$ok) {
        return;
    }
    $line =~ s/[\r\n]+$//;
    return $line;
}

sub get_request_body($self, $socket, $ua, $timeout, $blocksize) {

    # Note: Timeout is set per datablock

    my $line;
    my $datalen = 0;
    my $postdata;
    my $ok = 0;
    my $unread = $ua->{headers}->{'Content-Length'};
    my $tempdata;
    #print STDERR Dumper($ua->{headers});
    eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
        my $endtime = time + $timeout;
        while($unread) {
            my $thisblocksize = $blocksize;
            if($unread < $thisblocksize) {
                $thisblocksize = $unread;
            }
            $tempdata = undef;
            my $lastread = sysread($socket, $tempdata, $thisblocksize);
            if(!defined($tempdata) || !length($tempdata)) {
                if(time > $endtime) {
                    last;
                }
                sleep(0.01);
                next;
            }

            # Got data, move timeout window
            $endtime = time + $timeout;
           
            $unread -= $lastread;
            $datalen += $lastread;
            $postdata .= $tempdata;

            #print STDERR "Getting POST data ($unread to go)....\n";

        }

        if(!$unread) {
            $ok = 1;
        }
    };

    if(!$ok) {
        print STDERR "POST data recieve timeout\n";
        return 0;
    } elsif($datalen != $ua->{headers}->{'Content-Length'}) {
        print STDERR "Failed to read postdata\n";
        return 0;
    } elsif($datalen != length($postdata)) {
        print STDERR "INTERNAL ERROR: read() reported wrong number of bytes read\n";
        return 0;
    }
    $ua->{postdata} = $postdata;
    return 1;
}

sub parse_request_line($self, $ua, $header) {

    if($header =~ /^([A-Z]+)\ (\S+)\ HTTP\/(.*)$/) {
        ($ua->{method}, $ua->{url}, $ua->{httpversion}) = ($1, $2, $3);
    } else {
        return 0;
    }

    if($ua->{url} =~ /([^\?]+)\?(.+)/) {
        my $params;
        ($ua->{url}, $params) = ($1, $2);
        my %uriparams;
        my @parts = split/\&/, $params;
        foreach my $part (@parts) {
            my ($rawkey, $rawval) = split/\=/, $part;
            my $dkey = decode_uri_part($rawkey);
            my $dval = decode_uri_part($rawval);
            if(!defined($uriparams{$dkey})) {
                $uriparams{$dkey} = $dval;
            } else {
                if(ref($uriparams{$dkey}) ne 'ARRAY') {
                    my $tempval = $uriparams{$dkey};
                    my @temp = ($tempval, $dval);
                    $uriparams{$dkey} = \@temp;
                } else {
                    push @{$uriparams{$dkey}}, $dval;
                }
            }
        }
        $ua->{uriparams} = \%uriparams;
    } else {
        $ua->{uriparams} = {};
    }
    $ua->{url} = decode_uri_path($ua->{url});

    return 1;
}

sub parse_header_line($self, $ua, $header) {

    if($header =~ /^(\S+)\:\ (.+)$/) {
        my ($name, $value) = ($1, $2);
        if(defined($httpheadersmapping{lc $name})) {
            # Map header to a normed upper/lowercase form for
            # easier access within modules
            $name = $httpheadersmapping{lc $name};
        }

        if($name eq 'Accept-Encoding') {
            my $lval = '' . $value;
            $lval = lc $lval;
            $lval =~ s/\ //g; # Remove whitespaces
            my @parts = split/\,/, $lval;
            $ua->{headers}->{'Accept-Encoding-Array'} = \@parts;
        }

        $ua->{headers}->{$name} = $value;
        if($name eq 'Cookie') {
            my @parts = split/\;/, $value;
            foreach my $part (@parts) {
                $part =~ s/^\s+//g;
                $part =~ s/\s+$//g;
                next if($part !~ /\=/);
                my ($cname, $cval) = split/\=/, $part;
                if(defined($cname) && $cname ne '' && defined($cval) && $cval ne '') {
                    $ua->{cookies}->{$cname} = $cval;
                }
            }
        }
    } else {
        print STDERR "Illegal header line!\n";
        return 0;
    }

    return 1;
}

sub parse_post_data($self, $ua) {

    my $ok = 1;

    if($ua->{headers}->{'Content-Type'} =~ /application\/x\-www\-form\-urlencoded/ && $ua->{method} eq 'POST') {
        #print STDERR Dumper($ua);
        my %postparams;
        my @parts = split/\&/, $ua->{postdata};
        foreach my $part (@parts) {
            my ($rawkey, $rawval) = split/\=/, $part;
            my $dkey = decode_uri_part($rawkey);
            my $dval = decode_uri_part($rawval);
            eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                my $temp = decode_utf8($dkey);
                $dkey = $temp;
            };
            if($EVAL_ERROR) {
                print STDERR "Warning: $EVAL_ERROR\n";
            }
            eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                my $temp = decode_utf8($dval);
                $dval = $temp;
            };
            if($EVAL_ERROR) {
                print STDERR "Warning: $EVAL_ERROR\n";
            }
            if(!defined($postparams{$dkey})) {
                $postparams{$dkey} = $dval;
            } else {
                if(ref($postparams{$dkey}) ne 'ARRAY') {
                    my $tempval = $postparams{$dkey};
                    my @temp = ($tempval, $dval);
                    $postparams{$dkey} = \@temp;
                } else {
                    push @{$postparams{$dkey}}, $dval;
                }
            }
        }
        $ua->{postparams} = \%postparams;
    } elsif($ua->{headers}->{'Content-Type'} =~ /^multipart\/form\-data\;\ boundary\=(.+)/) {
        my $boundary = "--" . $1;

        my @parts = split $boundary, $ua->{postdata};
        foreach my $part (@parts) {
            $part =~ s/^\r\n//;
            $part =~ s/\r\n$//;
            next if($part eq '' || $part eq '--');
            my ($pline, $pcontent) = split/\r\n/, $part, 2;
            if($pline =~ /^(.+?)\:\ (.+?)\; (.*)/) {
                my ($hname, $htype, $params) = ($1, $2, $3);
                if($hname ne 'Content-Disposition' || $htype ne 'form-data') {
                    $ok = 0;
                    last;
                }
                my %pparams;
                my @pparts = split/\;\ /, $params;
                foreach my $ppart (@pparts) {
                    my ($pkey, $pval) = split/\=/, $ppart, 2;
                    $pval =~ s/^\"//;
                    $pval =~ s/\"$//;
                    $pparams{$pkey} = $pval;
                }
                if(defined($pparams{filename})) {

                    # **************************************
                    # Under certain circumstances IE11 sends
                    # the local file path ('C:\bla\bla\bla.txt')
                    # instead of only the filename.
                    # From what we can tell it's "security setting
                    # Intranet applies" AND we use a hostname
                    # instead of an IP in the URL
                    #
                    # "Fix" this by discarding the path of the filename
                        $pparams{filename} =~ s/^.*\\//;
                    # **************************************

                    if($pcontent =~ s/^Content-Type\:\ (.+?)\r\n\r\n//) {
                        $ua->{files}->{$pparams{filename}}->{type} = $1;
                        $ua->{files}->{$pparams{filename}}->{data} = $pcontent;
                        #print STDERR "File: ", $pparams{filename}, " is type ", $ua->{files}->{$pparams{filename}}->{type}, " size ", length($pcontent), " bytes, MD5 ", md5_hex($pcontent), "\n";
                        if(!defined($ua->{postparams}->{$pparams{name}})) {
                            $ua->{postparams}->{$pparams{name}} = $pparams{filename};
                        } else {
                            if(ref($ua->{files}->{$pparams{name}}) ne 'ARRAY') {
                                my $tempval = $ua->{postparams}->{$pparams{name}};
                                my @temp = ($tempval, $pparams{filename});
                                $ua->{postparams}->{$pparams{name}} = \@temp;
                            } else {
                                push @{$ua->{postparams}->{$pparams{name}}}, $pparams{filename};
                            }
                        }
                    } else {
                        $ok = 0;
                    }
                } else {
                    $pcontent =~ s/^\r\n//;
                    if(!defined($ua->{postparams}->{$pparams{name}})) {
                        $ua->{postparams}->{$pparams{name}} = $pcontent;
                    } else {
                        if(ref($ua->{postparams}->{$pparams{name}}) ne 'ARRAY') {
                            my $tempval = $ua->{postparams}->{$pparams{name}};
                            my @temp = ($tempval, $pcontent);
                            $ua->{postparams}->{$pparams{name}} = \@temp;
                        } else {
                            push @{$ua->{postparams}->{$pparams{name}}}, $pcontent;
                        }
                    }
                }

            } else {
                $ok = 0;
                last;
            }
        }
    }
    
    # Make sure we have utf8 decoded properly
    foreach my $key (keys %{$ua->{postparams}}) {        
        if(ref $ua->{postparams}->{$key} eq '' && !is_utf8($ua->{postparams}->{$key})) {
            eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                my $temp = decode_utf8($ua->{postparams}->{$key});
                $ua->{postparams}->{$key} = $temp;
            };
        }
    }
    return $ok;
}

sub process_request($self, $realsocket, $frontendheader) {

#    Prepared/tested for future ALPN needs (e.g. HTTP/2)
#    my $alpnversion = 'http/1.1';
#    if(ref $realsocket eq 'PageCamel::Net::Server::Proto::SSL') {
#        my $alpninfo = $realsocket->alpn_selected();
#        if(defined($alpninfo) && $alpninfo ne '') {
#            $alpnversion = $alpninfo;
#        }
#    }

    local $INPUT_RECORD_SEPARATOR = undef;
    binmode($realsocket, ':bytes');
    $realsocket->blocking(0);

    local $SIG{USR2} = sub {
        print STDERR "******************   SIGNAL USR2 DETECTED ****************\n";
        eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
            confess();
        };
        my $stacktrace = join("\n", $EVAL_ERROR);
        #print STDERR "###########\n$stacktrace\n###########\n";
        foreach my $filtermodule (@{$self->{logstacktrace}}) {
            my $module = $filtermodule->{Module};
            my $funcname = $filtermodule->{Function};
            $module->$funcname($stacktrace);
        }
        return;
    };


    # Run pre-connection handling functions (for example, check that all translations are up to date etc...)
    foreach my $worker (@{$self->{preconnect}}) {
        my $module = $worker->{Module};
        my $funcname = $worker->{Function} ;

        $module->$funcname();
    }

nextrequest:

    my %uatemp = (keepalive => 0);
    my $ua = \%uatemp;
    $ua->{headers} = {};
    $ua->{cookies} = {};
    $ua->{postparams} = {};
    $ua->{uriparams} = {};
    $ua->{files} = {};
    $ua->{realsocket} = $realsocket;
    $ua->{remote_addr} = $self->{last_accepted_client} || '0.0.0.0';
    $ua->{extra_response_headers} = {};
    $ua->{frontend} = $frontendheader;

    my $starttime = time();

    if($self->{need_srand_call}) {
        $self->{need_srand_call} = 0;
        srand();
        #my $testnumber = rand(999999);
        #print STDERR "Restarted PRNG for $PID: testnumber = $testnumber\n";
        #die;
    }

    # Run cleanup functions in case the last cycle bailed out with croak
    foreach my $worker (@{$self->{cleanup}}) {
        my $module = $worker->{Module};
        my $funcname = $worker->{Function} ;

        #$workCount += $module->$funcname();
        $module->$funcname();
    }

    # ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

    # Run the "firewall" stuff before even looking at the client request. If client
    # if marked as "blocked", just send an HTTP status line and minimalistic body
    # to notify the client, then close the connection
    {
        foreach my $item (@{$self->{firewall}}) {
            my $module = $item->{Module};
            my $funcname = $item->{Function};
            my $ok = $module->$funcname($ua->{remote_addr});
            if(!$ok) {
                #print STDERR "BLOCKING CLIENT " . $ua->{remote_addr} . "!!!\n";
                my $message = "Attack or server policy violation detected. Client " . $ua->{remote_addr} . " blocked for some time.";
                webPrint($realsocket, "HTTP/1.1 403 Policy violation\r\n" .
                                    "Content-Type: text/plain\r\n".
                                    "Content-Length: " . length($message) . "\r\n" .
                                    "Connection: close\r\n" .
                                    "\r\n" .
                                    $message);
                $ua->{keepalive} = 0;
                goto cleanup;
            }
        }
    }

    # ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

    my $requestline = $self->readheader(15, $realsocket);
    if(!defined($requestline)) {
        #print STDERR "REQUEST LINE TIMEOUT OR ERROR\n" if($self->{isDebugging});
        $ua->{keepalive} = 0;
        webPrint($realsocket, "HTTP/1.1 408 Request Timeout\r\n");

        goto cleanup;
    }


    if(!$self->parse_request_line($ua, $requestline)) {
        $ua->{keepalive} = 0;
        goto cleanup;
    }

    my $hcount = 0;

    while(1) {
        my $header = $self->readheader(5, $realsocket);
        if(!defined($header)) {
            #print STDERR "HEADER LINE TIMEOUT\n" if($self->{isDebugging});
            $ua->{keepalive} = 0;
            webPrint($realsocket, "HTTP/1.1 408 Request Timeout\r\n");
            goto cleanup;
        }
        $hcount++;
        if($hcount > 500) {
            # too many headers, may be an attack
            #print STDERR "Too many headers!\n";
            $ua->{keepalive} = 0;
            webPrint($realsocket, "HTTP/1.1 413 Request Entity Too Large\r\n");
            goto cleanup;
        }
        last if($header eq "");
        if(!$self->parse_header_line($ua, $header)) {
            #print STDERR "Error parsing header!\n";
            $ua->{keepalive} = 0;
            webPrint($realsocket, "HTTP/1.1 400 Bad Request\r\n");
            goto cleanup;
        }
    }

    if($ua->{httpversion} eq '1.1') {
        # In HTTP/1.1 all connections are "keep-alive" by default,
        # except when declared "close" in the Connection header
        if(!defined($ua->{headers}->{Connection}) || $ua->{headers}->{Connection} !~ /close/i) {
            $ua->{keepalive} = 1;
        }
    } elsif(defined($ua->{headers}->{Connection}) && $ua->{headers}->{Connection} =~ /keep\-alive/i) {
        $ua->{keepalive} = 1;
    }

    my $isdynamicpath = 0;
    my $webpath = $ua->{url};
    $ua->{original_path_info} =  $webpath;
    # remove double slashes and fix backslashes
    $webpath =~ s/\\/\//go;
    $webpath =~ s#//#/#go;
    $webpath =~ s#//#/#go;
    # Remove dynamic URL postfix used for forcing the browser to update cached data ("refresh forcer")
    # This is usually the date of the last reload or some manually set postfix
    # Remove dynamic path string
    if($webpath =~ /\*(\d+)$/o) {
        $webpath =~ s/\*(\d+)$//go;
        $isdynamicpath = 1;
    }
    $ua->{url} = $webpath;

    if($self->{isDebugging} && $webpath eq '/crashme' && $ua->{remote_addr} eq '127.0.0.1') {
        croak("/crashme triggered!");
    }

    my %header = (  "-Server"  =>  "PAGECAMEL/$VERSION",
                    -expires => 'now',
                    -cache_control=>"no-cache, no-store, must-revalidate",
                    -charset => 'utf-8',
                    "-Content-Language" => 'en',

            #'-x-frame-options'    => 'deny', # deny clickjacking, see http://www.webmasterworld.com/webmaster/4022867.htm
        );

    if(defined($self->{pagecamel}->{useragent})) {
        $header{"-Server"} = $self->{pagecamel}->{useragent};
    }

    my %result = (status    => 404, # Default result
                  type      => "text/plain",
                  data      => "Error 404: Kindly check your URL and try again!\n" .
                                "If you think this error is in error, please contact your " .
                                "system administrator or local network expert\n.",
                  pagedone => 0, # Remember if we still have only the ugly default page.
                  );
    my %fallbackresult = %result; # Just in case
    my $head_automagic = 0;

    # This starts logging with basic information before ANY filtering
    foreach my $filtermodule (@{$self->{logstart}}) {
        my $module = $filtermodule->{Module};
        my $funcname = $filtermodule->{Function};
        my %preresult = $module->$funcname($ua);
        if(%preresult) {
            %result = %preresult;
            $result{pagedone} = 1;
            last;
        }
    }

    # See, if we can do any short circuit fast redirecting
    foreach my $filtermodule (@{$self->{fastredirect}}) {
        my $module = $filtermodule->{Module};
        my $funcname = $filtermodule->{Function};
        my %preresult = $module->$funcname($ua);
        if(%preresult) {
            %result = %preresult;
            $result{pagedone} = 1;
            last;
        }
    }

    # At this point in time, we only check the allowed method for the function
    # at the requested URL. pre- and postfilter modules have to be aware of this
    # and just "do the right thing". When everything fails, doing a 303 to the
    # login dialog is always a safe option for prefilters, passing the reply
    # unmodified as the prefered option for post- and prerender filters
    #
    # Methods that are not allowed by a specific handler will get a
    # "405 Method not allowed" response.
    #
    # Unknown methods (e.g. the methods not specified in RFC2616 or custom methods)
    # will recieve a "501 Not Implemented" - no matter if the handler
    # registered it (because *this* module doesn't know how to handle it)
    #
    my $methodok = 0;
    my $targeturlfound = 0;
    my @allowedmethods;
    my $uamethod = $ua->{method};

    # Check valid http versions
    if(!$result{pagedone}) {
        if($ua->{httpversion} ne '1.0' && $ua->{httpversion} ne '1.1') {
            $result{status} = 400;
            $result{data} = "unsupported HTTP version";
            $result{type} = "text/plain";
            $result{pagedone} = 1;
        }
    }

    if(!$result{pagedone} && !defined($ua->{headers}->{Host})) {
        if($ua->{httpversion} eq '1.1') {
            $result{status} = 400;
            $result{data} = "Host header missing";
            $result{type} = "text/plain";
            $result{pagedone} = 1;
        }
    }

    # First check if this is a forbidden method (e.g. one with known vulnerabilities in its basic design). The is a
    # possibility a module registered a method like this *after* we done our final configuration check. We still wont allow it...
    if(!$result{pagedone} && contains($uamethod, $self->{forbidden_methods})) {
        $result{status} = 403;
        $result{data} = "Unsafe method requested. Request refused.";
        $result{type} = "text/plain";
        $result{pagedone} = 1;
    }

    # Next, check if the method is supported at all (lowers CPU time used on certain hack attemps)
    elsif(!$result{pagedone} && !contains($uamethod, $self->{supportedmethods})) {
        # Send a no-content "501 Not Implemented" reply
        $result{status} = 501;
        delete $result{data};
        delete $result{type};
        $result{pagedone} = 1;
    }

    if(!$result{pagedone} && $uamethod eq "OPTIONS") {
        if($webpath eq "*") {
            @allowedmethods = @{$self->{supportedmethods}};

            # We don't support CORS globally (on all paths) because that would be unsafe
            # So just ignore any request for it in the OPTIONS method when webpath equals '*'

        } else {
            my $found = 0;
            foreach my $dpath (keys %{$self->{webpaths}}) {
                if($webpath =~ /^$dpath/) {
                    my $pathmodule = $self->{webpaths}->{$dpath};
                    my @pmethods = @{$pathmodule->{Methods}};
                    @allowedmethods = @pmethods;
                    $found = 1;
                }
            }
            if(!$found) {
                # TODO: Now, this is a bit of a problem. A non-existent URL might still
                # be handled by prefilters. There is no completely correct way to handle this except
                # actually running the code in question and seeing what we get in return. This is
                # of course completely unacceptable. So, therefore we just return the full list
                # of supported methods and wait if the client actually uses any of them.
                #
                # If it does, it will get the correct Allow header with the method limited to
                # what the resource actually supports. This is neither nice nor perfect. But it
                # seems to be the most reasonable way to support this.
                @allowedmethods = @{$self->{supportedmethods}};
            }

            # Ok, lets check if the clients wants to know about CORS.
            # If it does AND we got a matching CORS entry on that path AND
            # if the requested method is allowed THEN we send the CORS headers
            # If any of this preconditions do NOT meet, we fall back to non-CORS
            # mode and pretend it does not exist (e.g. let the client fail)
            if(defined($ua->{headers}->{Origin}) && defined($ua->{headers}->{'Access-Control-Request-Method'})) {
                my $corsconf = $self->get_cors_config($ua->{url}, $ua->{headers}->{Origin});
                if(defined($corsconf) && defined($corsconf->{Methods})) {
                    my $xmethodok = 0;
                    foreach my $key (@{$corsconf->{Methods}}) {
                        if($key eq $ua->{headers}->{'Access-Control-Request-Method'}) {
                            $xmethodok = 1;
                            last;
                        }
                    }
                    if($xmethodok) {
                        $ua->{extra_response_headers}->{'Access-Control-Allow-Origin'} = $ua->{headers}->{Origin};
                        $ua->{extra_response_headers}->{'Access-Control-Allow-Methods'} = join(', ', @{$corsconf->{Methods}});
                        $ua->{extra_response_headers}->{'Access-Control-Max-Age'} = "3600"; # 1 hour
                    }
                }
            }
        }

        delete $result{data};
        delete $result{type};
        $result{pagedone} = 1;
        $result{status} = 200;
    }

    # Check if we have this method registered as custom handler.
    # Warning! This does not call the usual authentification modules
    # (if any are registered). Custom method handlers have to handle that
    # by themselfs!!
    if(!$result{pagedone}) {
        if(defined($self->{custom_methods}->{$uamethod})) {
            my $module = $self->{custom_methods}->{$uamethod}->{Module};
            my $funcname = $self->{custom_methods}->{$uamethod}->{Function};
            my %preresult = $module->$funcname($ua);
            if(%preresult) {
                %result = %preresult;
                $result{pagedone} = 1;
            } else {
                # Ooops, something went horribly wrong!
                # "500 Internal Server Error"
                $result{pagedone} = 1;
                $result{status} = 500;
                delete $result{data};
                delete $result{type};
            }
        }
    }

    # Now check if we find the URL and see if it supports the given method
    if(!$result{pagedone}) {
        foreach my $dpath (keys %{$self->{webpaths}}) {
            if($webpath =~ /^$dpath/) {
                my $pathmodule = $self->{webpaths}->{$dpath};
                my @pmethods = @{$pathmodule->{Methods}};
                @allowedmethods = @pmethods;
                if(contains($uamethod, \@pmethods)) {
                    $methodok = 1;
                } elsif($uamethod eq "HEAD" &&
                            contains('GET', \@pmethods)) {
                    # Allow HEAD when only GET is specified since
                    # modules handle this transparently (assume GET anyway)
                    # and Web.pm then just drops the content and we're done...
                    $methodok = 1;
                    $head_automagic = 1;
                    push @allowedmethods, 'HEAD';
                } else {
                    $result{status} = 405;
                }
                $targeturlfound = 1;
                last;
            }
        }
    }

    if(!$result{pagedone}) {
        # No target url found to check the METHOD against? Use some default handling, so
        # filter-modules still work:
        # Only allow GET and POST, as well as use the head_automagic.
        if(!$targeturlfound) {
            if($uamethod !~ /^(?:GET|POST|HEAD)$/io) {
                $result{status} = 405;
                @allowedmethods = qw[GET POST HEAD];
            } else {
                $methodok = 1;
                $head_automagic = 1;
            }
        }

        # Method not ok? Delete the content and we're done.
        if(!$methodok) {
            delete $result{data};
            delete $result{type};
            $result{pagedone} = 1;
        }
    }

    # Check if we are handling a Cross Origin Resource Sharing request. If so,
    # check if the given path allows us to handle a CORS request
    if(!$result{pagedone} && defined($ua->{headers}->{Origin})) {
        my $corsconf = $self->get_cors_config($ua->{url}, $ua->{headers}->{Origin});
        if(!defined($corsconf) || !defined($corsconf->{Methods})) {
            # No CORS handling defined, handle the "classic way", e.g. do nothing special
            #$result{status} = 403;
            #$result{statustext} = 'Cross Origin Resource Sharing not allowed on this URI';
            #delete $result{data};
            #delete $result{type};
            #$result{pagedone} = 1;
        } else {
            my $xmethodok = 0;
            foreach my $key (@{$corsconf->{Methods}}) {
                if($ua->{method} eq $key) {
                    $xmethodok = 1;
                    last;
                }
            }

            if(!$xmethodok) {
                $result{status} = 405;
                $result{statustext} = 'Cross Origin Resource Sharing with forbidden method';
                delete $result{data};
                delete $result{type};
                $result{pagedone} = 1;
            } else {
                $ua->{extra_response_headers}->{'Access-Control-Allow-Origin'} = $ua->{headers}->{Origin};
            }
        }
    }

    if(!$result{pagedone}) {
        if(defined($ua->{headers}->{'Content-Length'}) && $ua->{headers}->{'Content-Length'} > 0) {
            if(defined($ua->{headers}->{'Expect'}) && $ua->{headers}->{'Expect'} =~ /100\-continue/i) {
                #print STDERR "Continue header detected\n";

                my $expectok = 1;
                foreach my $dpath (keys %{$self->{continueheaders}}) {
                    if($webpath =~ /^$dpath/) {
                        my $pathmodule = $self->{continueheaders}->{$dpath};
                        my $module = $pathmodule->{Module};
                        my $funcname = $pathmodule->{Function};
                        if(!$module->$funcname($ua)) {
                            $expectok = 0;
                            last;
                        }
                    }
                }

                if(!$expectok) {
                    $ua->{keepalive} = 0;
                    webPrint($realsocket, "HTTP/1.1 417 Expectation Failed\r\n");
                    #print STDERR "      Expectation failed\n";
                    goto cleanup;
                }
                #print STDERR "      Expectation matched\n";
                webPrint($realsocket, "HTTP/1.1 100 Continue\r\n\r\n");
            }

            if(!$self->get_request_body($realsocket, $ua, 15, 1024)) {
                $ua->{keepalive} = 0;
                webPrint($realsocket, "HTTP/1.1 408 Request Timeout\r\n");
                goto cleanup;
            }

            if(!$self->parse_post_data($ua)) {
                $ua->{keepalive} = 0;
                webPrint($realsocket, "HTTP/1.1 400 Bad Request\r\n");
                goto cleanup;
            }
        }
    }


    # This works on "prefilters" checks, path
    # re-routing ("/" -> "302 /index") and similar.
    # This is the part BEFORE auth checks
    if(!$result{pagedone}) {
        foreach my $filtermodule (@{$self->{prefilter}}) {
            my $module = $filtermodule->{Module};
            my $funcname = $filtermodule->{Function};
            my %preresult = $module->$funcname($ua);
            if(%preresult) {
                %result = %preresult;
                $result{pagedone} = 1;
                last;
            }
        }
    }

    #Prefilters might modify the URL in $ua, so update local copy from there
    $webpath = $ua->{url};

    # Run all authentification checks
    if(!$result{pagedone}) {
        foreach my $filtermodule (@{$self->{authcheck}}) {
            my $module = $filtermodule->{Module};
            my $funcname = $filtermodule->{Function};
            my %preresult = $module->$funcname($ua);
            if(%preresult) {
                %result = %preresult;
                $result{pagedone} = 1;
                last;
            }
        }
    }

    # This works like the "prefilters" checks, but
    # AFTER authentication. This is for stuff where we need to
    # know the username, selected theme or something similar
    if(!$result{pagedone}) {
        foreach my $filtermodule (@{$self->{postauthfilter}}) {
            my $module = $filtermodule->{Module};
            my $funcname = $filtermodule->{Function};
            my %preresult = $module->$funcname($ua);
            if(%preresult) {
                %result = %preresult;
                $result{pagedone} = 1;
                last;
            }
        }
    }

    # Run the override page handling callbacks
    if(!$result{pagedone}) {
        foreach my $dpath (keys %{$self->{overridewebpaths}}) {
            if($webpath =~ /^$dpath/) {
                my $pathmodule = $self->{overridewebpaths}->{$dpath};
                my $module = $pathmodule->{Module};
                my $funcname = $pathmodule->{Function};
                %result = $module->$funcname($ua);
                $result{pagedone} = 1;
                last;
            }
        }
    }

    # Run the normal page handling callbacks
    if(!$result{pagedone}) {
        foreach my $dpath (keys %{$self->{webpaths}}) {
            if($webpath =~ /^$dpath/) {
                my $pathmodule = $self->{webpaths}->{$dpath};
                my $module = $pathmodule->{Module};
                my $funcname = $pathmodule->{Function};
                %result = $module->$funcname($ua);
                $result{pagedone} = 1;
                last;
            }
        }
    }

    # run some postfilter callbacks, except for custom and internal methods
    if(!defined($self->{custom_methods}->{$uamethod}) && !contains($uamethod, $self->{internal_methods})) {
        foreach my $filtermodule (@{$self->{postfilter}}) {
            my $module = $filtermodule->{Module};
            my $funcname = $filtermodule->{Function};
            $module->$funcname($ua, \%header, \%result);
        }
    }

    # run some logging callbacks
    foreach my $filtermodule (@{$self->{logend}}) {
        my $module = $filtermodule->{Module};
        my $funcname = $filtermodule->{Function};
        $module->$funcname($ua, \%header, \%result);
    }

    # workaround for simpler in-module handling of 404, when no data segment is given
    if(!defined($result{data})) {
        if($result{status} == 404) {
            %result = %fallbackresult;
        } elsif($result{status} == 405) {
            $result{data} = "The requested method '$uamethod' is not available for this resource.";
            $result{type} = "text/plain";
        }
    }


    # Set statustext. This uses the standard RFC 2616 texts for the status codes.
    # If a module sets the statustext itself (bad idea except in special circumstances), this
    # is the default
    if(!defined($result{statustext}) || $result{statustext} eq "") {
        if(defined($httpstatuscodes{$result{status}})) {
            $result{statustext} = $httpstatuscodes{$result{status}};
        } else {
            $result{statustext} = "Warning UNDEFINED HTTP STATUS CODE";
        }
    }

    if(!webPrint($realsocket, "HTTP/1.1 " . $result{status} . " " . $result{statustext} . "\r\n")) {
        $ua->{keepalive} = 0;
        goto cleanup;
    }

    if(defined($result{type}) && $result{type} ne '') {
        $header{"-type"} = $result{type};
    }
    if(defined($result{location})) {
        $header{"-location"} = $result{location};
    }
    if(defined($result{expires})) {
        $header{"-expires"} = $result{expires};
    }
    if(defined($result{cache_control})) {
        $header{"-cache_control"} = $result{cache_control};
    }

    # Disable body generation for specific error codes as defined in RFC 2616
    foreach my $nbcode (qw[100 101 204 205 304]) {
        if($result{status} eq $nbcode) {
            delete $result{data};
        }
    }

    # Check to see if we are allowed to generate a Content-Length header field (a "should" in RFC 2616)
    if(defined($result{data})) {
        if(!defined($header{"-Transfer-Encoding"})) {
            if(is_utf8($result{data})) {
                # Need to turn high bytes into utf-8 BEFORE calculating the content length, otherwise we might
                # output more bytes than we said in Content-Length. Darn Unicode strikes again....!
                $header{"-Content-Length"} = length(encode_utf8($result{data}));
            } else {
                $header{"-Content-Length"} = length($result{data});
            }
        }
    } elsif(defined($result{content_length})) {
        $header{"-Content-Length"} = $result{content_length};
    } elsif(!defined($header{"-Content-Length"}) && !defined($header{"-Transfer-Encoding"}) && !defined($result{data})) {
        $header{"-Content-Length"} = 0;
    }

    # Check deprecated result keys
    foreach my $hname ('lastmod',
                       ) {
        if(defined($result{$hname}) || defined($result{lc $hname})) {
            print STDERR "!!!!! Deprecated result key $hname detected. HTTP stream may be invalid!\n";
        }
    }

    foreach my $hname ("Content-Disposition",
                       "Content-Encoding",
                       "Content-Range",
                       "Content-Language",
                       "ETag",
                       "Date",
                       "Accept-Ranges",
                       "Last-Modified",
                       "Vary",
                       "Allow",
                       "Upgrade",
                       "Connection",
                       "Sec-WebSocket-Accept",
                       "Sec-WebSocket-Protocol",
                       "WWW-Authenticate",

                       # XSS Security Policy
                       # See http://www.heise.de/security/artikel/XSS-Bremse-Content-Security-Policy-1888522.html
                       "Content-Security-Policy",
                       "X-Content-Security-Policy",
                       "X-Webkit-CSP",
                       "Content-Security-Policy-Reporty-Only",
                       "X-Content-Security-Policy-Reporty-Only",
                       "X-Webkit-CSP-Reporty-Only",
                       "p3p",
                       ) {
        if(defined($result{$hname})) {
            $header{"-" . $hname} = $result{$hname};
        } elsif(defined($result{lc $hname})) {
            $header{"-" . $hname} = $result{lc $hname};
        } elsif(defined($result{'-' . lc $hname})) {
            $header{"-" . $hname} = $result{'-' . lc $hname};
        }
    }

    # Handle cookie headers
    if(defined($header{'-cookie'})) {
        if(ref $header{'-cookie'} eq 'ARRAY') {
            foreach my $cookie (@{$header{'-cookie'}}) {
                if(!webPrint($realsocket, "Set-Cookie: ", $cookie, "\r\n")) {
                    $ua->{keepalive} = 0;
                    goto cleanup;
                }
            }
        } else {
            if(!webPrint($realsocket, "Set-Cookie: ", $header{'-cookie'}, "\r\n")) {
                $ua->{keepalive} = 0;
                goto cleanup;
            }
        }
        delete $header{'-cookie'};
    }

    # Create "Allow" header automagically when not set explicitly
    if($result{status} ne "101" && !defined($header{"-Allow"}) && @allowedmethods) {
        if(contains('GET', \@allowedmethods) && !contains('HEAD', \@allowedmethods)) {
            # Always allow HEAD where GET is allowed since HEAD is also
            # created dynamically
            push @allowedmethods, 'HEAD';
        }
        $header{"-Allow"} = join(', ', sort @allowedmethods);
    }

    # Confirm to HEAD request standard. Disable body generation. This should
    # NOT touch any headers incl. Content-Length, we just don't *deliver*
    # the content. Only do this if head_automagic is true (e.g. if the function
    # registered the GET method but not the HEAD method)
    if( $head_automagic == 1 && $ua->{method} eq "HEAD" && defined($result{data})) {
        delete $result{data};
    }

    # Copy the "extra headers" over the originally created headers. This is used for example in CORS
    foreach my $key (keys %{$ua->{extra_response_headers}}) {
        $header{'-' . lc $key} = $ua->{extra_response_headers}->{$key};
    }

    my $broken_header_key = 0;
    foreach my $header_key (keys %header) {
        if($header_key !~ /^\-/) {
            carp("Broken Header key $header_key");
            $broken_header_key = 1;
        }
    }
    if($broken_header_key) {
        croak("Broken header keys detected!");
    }


    # Print the headers
    my $dateprinted = 0;
    foreach my $header_key (keys %header) {
        my $printkey = $header_key;
        $printkey =~ s/^\-//g;
        $printkey =~ s/\_/\-/g;
        if(defined($httpheadersmapping{lc $printkey})) {
            $printkey = $httpheadersmapping{lc $printkey};
        }

        if($printkey eq 'Date') {
            if($dateprinted) {
                # Already printed enforced to current date and time
                next;
            } else {
                $dateprinted = 1;
            }
        }

        if($printkey eq 'type') {
            $printkey = 'Content-Type';
        }

        if($printkey eq 'Expires') {
            my $val = $header{$header_key};
            if(lc $val eq 'now') {
                $val = getWebdate();
            } elsif($val =~ /^[\+\-]/) {
                $val = getWebdate(undef, $val);
            }
            if(!webPrint($realsocket, $printkey, ": ", $val, "\r\n")) {
                $ua->{keepalive} = 0;
                goto cleanup;
            }
        } elsif(ref $header{$header_key} eq 'ARRAY') {
            foreach my $headerval (@{$header{$header_key}}) {
                if(!webPrint($realsocket, $printkey, ": ", $headerval, "\r\n")) {
                    $ua->{keepalive} = 0;
                    goto cleanup;
                }
            }
        } else {
            if(!webPrint($realsocket, $printkey, ": ", $header{$header_key}, "\r\n")) {
                $ua->{keepalive} = 0;
                goto cleanup;
            }
        }

    }

    # Force printing current time as "Date" header
    if(!$dateprinted) {
        if(!webPrint($realsocket, "Date: " . getWebdate(). "\r\n")) {
            $ua->{keepalive} = 0;
            goto cleanup;
        }
    }

    # Removing this header may break things, don't touch!
    if(!webPrint($realsocket, "X-Clacks-Overhead: GNU Terry Pratchett\r\n")) {
        $ua->{keepalive} = 0;
        goto cleanup;
    }

    if(!webPrint($realsocket, "\r\n")) {
        $ua->{keepalive} = 0;
        goto cleanup;
    }

    if(defined($result{data})) {
        # Some results do not have a body
        if(!webPrint($realsocket, $result{data})) {
            $ua->{keepalive} = 0;
            goto cleanup;
        }
    }   

    # handle protocol upgrades like WebSockets
    if($result{status} eq "101") {
        # run some logging callbacks
        foreach my $filtermodule (@{$self->{logwebsocket}}) {
            my $module = $filtermodule->{Module};
            my $funcname = $filtermodule->{Function};
            $module->$funcname($ua, \%header, \%result);
        }

        $ua->{keepalive} = 0;
        my $upgradeTo = $ua->{headers}->{'Upgrade'} || '';
        foreach my $dpath (keys %{$self->{protocolupgrade}}) {
            if($webpath =~ /^$dpath/) {
                my $pathmodule = $self->{protocolupgrade}->{$dpath};
                my $module = $pathmodule->{Module};
                my $funcname = $pathmodule->{Function};
                my $upgradetofound = 0;
                foreach my $tmpkey (@{$pathmodule->{Protocols}}) {
                    if($tmpkey =~ /$upgradeTo/i) {
                        $upgradetofound = 1;
                        last;
                    }
                }
                next unless $upgradetofound;
                print STDERR getISODate() . " Upgrading connection to $upgradeTo in PID $PID\n";
                my $evalok = 0;
                my $conok;
                eval { ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                    $conok = $module->$funcname($ua);
                    $evalok = 1;
                };
                if(!$evalok) {
                    print STDERR getISODate(), " Eval error in connection upgrade: $EVAL_ERROR\n";
                }
                print STDERR getISODate() . " Connection for $upgradeTo closed in PID $PID, status $conok\n";
                last;
            }
        }
    } elsif(defined($result{dataGenerator})) {
        # run some logging callbacks
        foreach my $filtermodule (@{$self->{logrequestfinished}}) {
            my $module = $filtermodule->{Module};
            my $funcname = $filtermodule->{Function};
            $module->$funcname($ua, \%header, \%result);
        }

        my $module = $result{dataGenerator}->{module};
        my $funcname = $result{dataGenerator}->{funcname};
        my ($totallength, $partcount) = (0, 0);
        while(1) {
            my %dpart = $module->$funcname($ua);
            $partcount++;
            $totallength += length($dpart{data});
            #print STDERR getISODate() . "     Data part, length ", length($dpart{data}), " bytes\n";
            if(!webPrint($realsocket, $dpart{data})) {
                $ua->{keepalive} = 0;
                goto cleanup;
            }
            last if($dpart{done});
        }
        print STDERR getISODate() . "     Send $totallength bytes in $partcount datagenerator parts.\n";
    }
    
    # run some logging callbacks
    foreach my $filtermodule (@{$self->{logrequestfinished}}) {
        my $module = $filtermodule->{Module};
        my $funcname = $filtermodule->{Function};
        $module->$funcname($ua, \%header, \%result);
    }

    my $endtime = time();

    my $timetaken = int(($endtime - $starttime)*1000);

    # run some remote logging callbacks
    my $webapimethod = '';
    if(defined($result{"webapi_method"})) {
        $webapimethod = "[" . $result{"webapi_method"} . "()]";
    }
    my $debugmark = "";
    if(defined($result{dataGenerator})) {
        $debugmark .= 'D';
    }
    if($isdynamicpath) {
        $debugmark .= "*";
    }

    if(!defined($result{__do_not_log_to_debuglog}) || !$result{__do_not_log_to_debuglog}) {
        my %remotelog = (
            result  => $result{status},
            method  => $uamethod,
            webpath => $webpath,
            client  => $ua->{remote_addr},
            timetaken => $timetaken,
            webapimethod => $webapimethod,
            allowedmethods => join(',', @allowedmethods),
            debugmark => $debugmark,
        );
        foreach my $filtermodule (@{$self->{remotelog}}) {
            my $module = $filtermodule->{Module};
            my $funcname = $filtermodule->{Function};
            $module->$funcname(\%remotelog);
        }
    }


cleanup:
    # Run cleanup functions
    foreach my $worker (@{$self->{cleanup}}) {
        my $module = $worker->{Module};
        my $funcname = $worker->{Function} ;

        #$workCount += $module->$funcname();
        $module->$funcname();
    }

    if($ua->{keepalive}) {
        #print STDERR getISODate() . "  keepalive, restarting protocol handler\n";
        goto nextrequest;
    }

    return;
}

sub startconfig($self) {

    # Pre-create empty lists and hashes
    foreach my $anonhash (qw[paths modules custom_methods protocolupgrade cors basic_auth continueheaders]) {
        $self->{$anonhash} = {};
    }
    foreach my $anonarrays (qw[logstart logend logdatadelivery logwebsocket logrequestfinished logstacktrace authcheck prefilter postauthfilter prerender lateprerender tasks postfilter
                                default_webdata late_default_webdata loginitems logoutitems sessionrefresh cleanup
                                public_urls remotelog sitemap firewall fastredirect
                                ]) {
        $self->{$anonarrays} = [];
    }

    return;
}

sub load_base_project($self, $projectname) {
    my $perlmodule = "PageCamel::Web::$projectname";
    if(!defined($perlmodule->VERSION)) {
        print "Dynamically loading base project module $perlmodule...\n";
        load $perlmodule;
    }

    # Check again
    if(!defined($perlmodule->VERSION)) {
        croak("$perlmodule not loaded");
    }

    # Module must be the same version as this module
    if($perlmodule->VERSION ne $VERSION) {
        croak("$perlmodule has version " . $perlmodule->VERSION . " but we need $VERSION");
    }

    return;
}

sub endconfig($self) {

    print "For great justice...\n"; # We REQUIRE an all-your-base reference here!!1!
    print "Cross registering modules...\n";
    foreach my $modname (keys %{$self->{modules}}) {
        #print "  crossregistering for $modname\n";
        $self->{modules}->{$modname}->crossregister;   # Reload module's data
    }
    print "Loading dynamic data...\n";
    foreach my $modname (keys %{$self->{modules}}) {
        #print "  Loading data for $modname\n";
        $self->{modules}->{$modname}->reload;   # Reload module's data
    }

    print "Running final checks in modules before preparing to fork...\n";
    foreach my $modname (keys %{$self->{modules}}) {
        #print "  finalcheck for $modname\n";
        $self->{modules}->{$modname}->finalcheck;   # finalcheck() calls
    }

    print "Final checks complete - calling endconfig...\n";
    foreach my $modname (keys %{$self->{modules}}) {
           $self->{modules}->{$modname}->endconfig;   # Mostly used in preforking servers
    }

    print "Scanning all webpaths for supported methods...\n";
    # Always mark the basic HTTP methods as supported even when we don't use them in the configured modules
    # This helps to minimize problems (PageCamel will report "405 Method Not Allowed" instead of "501 Not Implemented")
    my %methods;
    foreach my $method (qw[HEAD GET POST PUT DELETE]) {
        $methods{$method} = 0;
    }

    my $pathcount = 0;
    foreach my $dpath (keys %{$self->{webpaths}}) {
        my $pathmodule = $self->{webpaths}->{$dpath};
        $pathcount++;
        #print "      Path: $dpath  ", join(' ', sort @{$pathmodule->{Methods}}), "\n";

        foreach my $method (@{$pathmodule->{Methods}}) {
            if(!defined($methods{$method})) {
                $methods{$method} = 0;
            }
            $methods{$method} += 1;
        }
    }
    foreach my $dpath (keys %{$self->{overridewebpaths}}) {
        my $pathmodule = $self->{overridewebpaths}->{$dpath};
        $pathcount++;
        #print "      Path: $dpath  ", join(' ', sort @{$pathmodule->{Methods}}), "\n";

        foreach my $method (@{$pathmodule->{Methods}}) {
            if(!defined($methods{$method})) {
                $methods{$method} = 0;
            }
            $methods{$method} += 1;
        }
    }
    print "Found $pathcount registered paths (not including dynamically in-module generated sub-paths) with the following method counts:\n";
    foreach my $method (sort keys %methods) {
        next if(!$methods{$method});
        print "   $method (" . $methods{$method} . ")\n";
    }

    my @supportedmethods = sort keys %methods;

    # Add internally supported HTTP methods that currently can't be overridden
    print "Add non-overrideable handling for some HTTP methods...\n";
    my @internal_methods = qw[OPTIONS];
    foreach my $method (@internal_methods) {
        if(contains($method, \@supportedmethods)) {
            croak("Method $method already in use!");
        }
        print "  $method registered as internal method.\n";
        push @supportedmethods, $method;
        $methods{$method}++;
    }
    $self->{internal_methods} = \@internal_methods;

    # Now, scan all the custom method handlers. Custom methods for already used
    # methods are forbidden and produce an error.
    print "Scanning custom methods...\n";
    foreach my $method (keys %{$self->{custom_methods}}) {
        if(contains($method, \@supportedmethods)) {
            croak("Method $method already in use!");
        }
        print "  $method registered as custom method. (This may circumvent authentification!)\n";
        push @supportedmethods, $method;
    }

    print "Scanning for forbidden HTTP methods...\n";
    my @forbidden_methods = qw[TRACE TRACK];
    foreach my $method (@forbidden_methods) {
        if(contains($method, \@supportedmethods)) {
            croak("Method $method in use! Startup canceled due to security risks!");
        } else {
            print "  OK, forbidden $method not found\n";
        }
    }
    $self->{forbidden_methods} = \@forbidden_methods;


    $self->{supportedmethods} = \@supportedmethods;
    print "Done.\n";

    $self->{need_srand_call} = 1;

    print "\n";
    print "Startup configuration complete!\n\n";
    print "+------------------------------------+\n";
    print "| We are GO for auto-sequence start! |\n";
    print "+------------------------------------+\n\n";
    return;

}

sub configure_module($self, $modname, $perlmodulename, %config) {

    # Let the module know its configured module name...
    $config{modname} = $modname;

    # ...what perl module it's supposed to be...
    my $perlmodule = "PageCamel::Web::$perlmodulename";
    if(!defined($perlmodule->VERSION)) {
        print "Dynamically loading $perlmodule...\n";
        load $perlmodule;
    }

    # Check again
    if(!defined($perlmodule->VERSION)) {
        croak("$perlmodule not loaded");
    }

    # Module must be the same version as this module
    if($perlmodule->VERSION ne $VERSION) {
        croak("$perlmodule has version " . $perlmodule->VERSION . " but we need $VERSION");
    }

    $config{pmname} = $perlmodule;

    # and its parent
    $config{server} = $self;

    # also notify the module if it needs to take care of forking issues (database
    # modules probably will)
    $config{forking} = 1;

    if(defined($self->{modules}->{$modname})) {
        croak("Module with name '$modname' already configured!");
    }

    $self->{modules}->{$modname} = $perlmodule->new(%config);
    $self->{modules}->{$modname}->register; # Register handlers provided by the module
    #print "Module $modname ($perlmodule) configured.\n";
    return;
}

sub reload($self) {

    foreach my $modname (keys %{$self->{modules}}) {
        $self->{modules}->{$modname}->reload;   # Reload module's data
    }
    return;
}

sub run_task($self) {


    # only run tasks if there was no connection (there might be a browser just loading more files)
    my $taskCount = 0;
    foreach my $task (@{$self->{tasks}}) {
        my $module = $task->{Module};
        my $funcname = $task->{Function};
        $taskCount += $module->$funcname();
    }
    return ($taskCount);
}

# Multi-Module calls: Called from one module to run multiple other module functions
sub get_defaultwebdata($self) {

    my %webdata = ();
    foreach my $item (@{$self->{default_webdata}}) {
        my $module = $item->{Module};
        my $funcname = $item->{Function};
        $module->$funcname(\%webdata);
    }

    foreach my $item (@{$self->{late_default_webdata}}) {
        my $module = $item->{Module};
        my $funcname = $item->{Function};
        $module->$funcname(\%webdata);
    }

    return %webdata;
}

sub get_sitemap($self) {

    my @sitemap;
    foreach my $item (@{$self->{sitemap}}) {
        my $module = $item->{Module};
        my $funcname = $item->{Function};
        $module->$funcname(\@sitemap);
    }

    return \@sitemap;
}

# This is used by the template engine to get last-minute data fields
# just before rendering webdata with a template into a webpage
# Takes a reference to webdata
sub prerender($self, $webdata) {

    foreach my $item (@{$self->{prerender}}) {
        my $module = $item->{Module};
        my $funcname = $item->{Function};
        $module->$funcname($webdata);
    }
    return;
}
sub lateprerender($self, $webdata) {

    foreach my $item (@{$self->{lateprerender}}) {
        my $module = $item->{Module};
        my $funcname = $item->{Function};
        $module->$funcname($webdata);
    }
    return;
}


sub user_login($self, $username, $sessionid) {

    foreach my $item (@{$self->{loginitems}}) {
        my $module = $item->{Module};
        my $funcname = $item->{Function};
        $module->$funcname($username, $sessionid);
    }
    return;
}

sub user_logout($self, $sessionid) {

    print STDERR "\n\n";
    foreach my $item (@{$self->{logoutitems}}) {
        my $module = $item->{Module};
        my $funcname = $item->{Function};
        #my $starttime = time;
        $module->$funcname($sessionid);
        #my $endtime = time;
        #print STDERR "***** logoutitem for ", $module->{modname}, " took ", $endtime - $starttime, " seconds\n";

    }
    return;
}

sub sessionrefresh($self, $sessionid) {

    foreach my $item (@{$self->{sessionrefresh}}) {
        my $module = $item->{Module};
        my $funcname = $item->{Function};
        $module->$funcname($sessionid);
    }
    return;
}

# Register a webpath (e.g. register with module/function to call when a specific
# URL is called)
#
# This also does the registering for method handlers (e.g. allow "special" methods like PUT, DELETE,...
# on this URL's). If no list of methods is provided, PageCamel assumes that the the function can only
# handle GET and POST.
# The HEAD method is a special case as well: If the registered function
# also specifies HEAD, PageCamel assumes that it shouldn't automagically handle this. Also,
# PageCamel can only automagically assume HEAD if the function provides GET because of the required
# idempotency of GET and HEAD.
sub add_webpath($self, $path, $module, $funcname, @methods) {

    if(!@methods) {
        @methods = qw[GET POST];
    }

    if(defined($self->{webpaths}->{$path})) {
        croak($module->{modname} . " error: $path already registered, previously registered in " . $self->{webpaths}->{$path}->{Module}->{modname});
    }

    my %conf = (
        Module  => $module,
        Function=> $funcname,
        Methods => \@methods,
    );

    $self->{webpaths}->{$path} = \%conf;
    return;
}

sub add_overridewebpath($self, $path, $module, $funcname, @methods) {

    if(!@methods) {
        @methods = qw[GET POST];
    }

    if(defined($self->{overridewebpaths}->{$path})) {
        croak($module->{modname} . " error: $path already registered, previously registered in " . $self->{overridewebpaths}->{$path}->{Module}->{modname});
    }

    my %conf = (
        Module  => $module,
        Function=> $funcname,
        Methods => \@methods,
    );

    $self->{overridewebpaths}->{$path} = \%conf;
    return;
}

sub add_continueheader($self, $path, $module, $funcname) {
    if(defined($self->{continueheaders}->{$path})) {
        croak($module->{modname} . " error: continueheader $path already registered, previously registered in " . $self->{continueheaders}->{$path}->{Module}->{modname});
    }

    my %conf = (
        Module  => $module,
        Function=> $funcname,
    );

    $self->{continueheaders}->{$path} = \%conf;
    return;
}

sub get_webpaths($self) {

    return $self->{webpaths};
}

sub get_overridewebpaths($self) {

    return $self->{overridewebpaths};
}

# Add a custom method handler
sub add_custom_method($self, $method, $module, $funcname) {

    $method = uc($method);

    if($method eq '') {
        croak("add_custom_method failed, method name empty!");
    }

    if(defined($self->{custom_methods}->{$method})) {
        croak("Custom method $method already defined!");
    }

    my %conf = (
        Module  => $module,
        Function=> $funcname,
    );

    $self->{custom_methods}->{$method} = \%conf;
    return;
}

sub add_protocolupgrade($self, $path, $module, $funcname, @protocols) {

    if(!@protocols) {
        croak("add_protocolupgrade requires protocols to be defined!");
    }

    my %conf = (
        Module  => $module,
        Function=> $funcname,
        Protocols => \@protocols,

    );

    $self->{protocolupgrade}->{$path} = \%conf;
    return;
}

sub add_basic_auth($self, $url, $realm) {

    if(!defined($url) || $url eq '') {
        croak("Undefined URL in add_basic_auth()");
    }

    if(!defined($realm) || $realm eq '') {
        croak("Undefined $realm in add_basic_auth()");
    }

    if(defined($self->{basic_auth}->{$url})) {
        croak("$url already registered as basic_auth capable");
    }

    $self->{basic_auth}->{$url} = $realm;

    return;
}

sub get_basic_auths($self) {

    return $self->{basic_auth};
}

sub add_public_url($self, $url) {

    if(!defined($url) || $url eq '') {
        croak("Undefined URL in add_public_url()");
    }

    if(contains($url, \@{$self->{public_urls}})) {
        croak("$url already registered as public URL");
    }

    push @{$self->{public_urls}}, $url;

    return;
}

sub get_public_urls($self) {

    return $self->{public_urls};

}

# Cross Origin Resource requests
sub add_cors($self, $path, $module, $origin, @methods) {

    if(defined($self->{cors}->{$path}->{$origin})) {
        croak($module->{modname} . " error: $path for $origin already registered, previously registered in " . $self->{cors}->{$path}->{$origin}->{Module}->{modname});
    }

    my %conf = (
        Module  => $module,
        Methods => \@methods,
    );

    $self->{cors}->{$path}->{$origin} = \%conf;
    return;
}

sub get_cors_config($self, $path, $origin) {

    if($origin eq '*') {
        # Origin can not be a wildcard star
        return;
    }

    # First, find a matching path
    my $foundpath = '';
    foreach my $key (keys %{$self->{cors}}) {
        if(substr($path, 0, length($key)) eq $key) {
            $foundpath = $key;
            last;
        }
    }

    if($foundpath eq '') {
        # No matching path found
        return;
    }

    if(defined($self->{cors}->{$foundpath}->{$origin})) {
        # Found exact match for the given origin
        return $self->{cors}->{$foundpath}->{$origin};
    }

    if(defined($self->{cors}->{$foundpath}->{'*'})) {
        # Found wildcard origin for this path
        return $self->{cors}->{$foundpath}->{'*'};
    }

    # No matching origin defined
    return;
}

BEGIN {
    # Auto-magically generate a number of similar functions without actually
    # writing them down one-by-one. This makes consistent changes much easier, but
    # you need perl wizardry level +12 to understand how it works...

    no strict 'refs'; ## no critic (TestingAndDebugging::ProhibitNoStrict)

    # -- Deep magic begins here...
    my %varsubs = (
        prefilter       => "prefilter",
        postauthfilter       => "postauthfilter",
        postfilter      => "postfilter",
        defaultwebdata  => "default_webdata",
        sitemap         => "sitemap",
        firewall        => "firewall",
        late_defaultwebdata  => "late_default_webdata",
        task            => "tasks",
        loginitem       => "loginitems",
        logoutitem      => "logoutitems",
        sessionrefresh  => "sessionrefresh",
        cleanup         => "cleanup",
        preconnect      => "preconnect",
        prerender       => "prerender",
        lateprerender       => "lateprerender",
        authcheck       => "authcheck",
        logstart        => "logstart",
        logend          => "logend",
        logdatadelivery => "logdatadelivery",
        logwebsocket    => "logwebsocket",
        logrequestfinished => "logrequestfinished",
        logstacktrace   => "logstacktrace",
        remotelog       => "remotelog",
        fastredirect    => "fastredirect",
    );
    for my $a (keys %varsubs){
        *{__PACKAGE__ . "::add_$a"} =
            sub {
                my %conf = (
                    Module  => $_[1],
                    Function=> $_[2],
                );
                push @{$_[0]->{$varsubs{$a}}}, \%conf;
            };
    }
    # ... and ends here
}

1;
__END__

=head1 NAME

PageCamel::WebBase - base class of the webserver

=head1 SYNOPSIS

  use PageCamel::WebBase;


=head1 DESCRIPTION

This is the base class of the webserver, the module through which each and every web request passes

=head2 valid_http_method

Backwards compatibility method, previously used with HTTP::Server::Simple to allow handling all HTTP methods.


=head2 allow_deny_hook

Check if client is allowed to connect

=head2 post_process_request_hook

reset IP of last accepted client after processing the request

=head2 handle_childstart

Called in multiforking mode when new child is created

=head2 handle_childstop

Called in multiforking mode when child is killed

=head2 readheader

Read a header line

=head2 get_request_body

Read in the request body (POST, PUT)

=head2 parse_request_line

Parse the REQUEST line (e.g. 'GET / HTTP/1.1').
All further processing depends of the request line.

=head2 parse_header_line

Parse a normal HTTP header line

=head2 parse_post_data

Parse all different kinds of postdata (multipart forms etc.)

=head2 process_request

The main function that processes requests

=head2 get_cors_config

Handle stuff for HTTP Cross-Origin Resource Sharing

=head2 startconfig

Prepare for configuration of plugins/webserver modules

=head2 endconfig

Finish up configuration of plugins/webserver modules

=head2 configure_module

Configure a plugin/webserver module

=head2 reload

(Re-)load all data

=head2 run_task

Run internal tasks in plugins

=head2 get_defaultwebdata

Ask all plugins for their default webdata

=head2 get_sitemap

Get sitemap partials from all plugins

=head2 prerender

Trigger the prerender callback in all plugins

=head2 user_login

Trigger the login callback in all plugins

=head2 user_logout

Trigger the logout callback in all plugins

=head2 sessionrefresh

Trigger the sessionrefresh callback in all plugins

=head2 add_webpath

Add a known webpath

=head2 add_overridewebpath

Add an "override" webpath

=head2 get_webpaths

Get all webpaths

=head2 get_overridewebpaths

Get all override webpaths

=head2 add_custom_method

Add handler for customs HTTP methods

=head2 add_protocolupgrade

Add callback for protocol upgrades in specific plugins (for example a websocket handler)

=head2 add_public_url

Register a public URL (circumventing authorization)

=head2 get_public_urls

List all public URLs

=head2 add_cors

Add CORS

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
