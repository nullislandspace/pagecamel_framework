# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license
package PageCamel::CMDLine::Legacy::LetsEncrypt;
#---AUTOPRAGMASTART---
use v5.40;
use strict;
use diagnostics;
use mro 'c3';
use English;
use Carp qw[carp croak confess cluck longmess shortmess];
our $VERSION = 4.7;
use autodie qw( close );
use Array::Contains;
use utf8;
use Data::Dumper;
use Data::Printer;
use PageCamel::Helpers::UTF;
#---AUTOPRAGMAEND---
use IO::File;
use JSON::MaybeXS;
use Module::Load;
use Digest::SHA 'sha256';
use MIME::Base64 'encode_base64url';
use Crypt::LE ':errors', ':keys';
use URI::_punycode;

use PageCamel::Helpers::ConfigLoader;
use PageCamel::Helpers::Logo;
use PageCamel::Helpers::DateStrings;
use XML::RPC;

use DBI;
use Sys::Hostname;

#use constant PEER_CRT  => 4;
#use constant CRT_DEPTH => 5;

sub new($proto, $configfile, $isDebugging, $isVerbose) {
    my $class = ref($proto) || $proto;

    print "Loading config file ", $configfile, "\n";
    my $self = LoadConfig($configfile,
                        ForceArray => [ 'domain', 'prefix', 'restartcommand'],);
    bless $self, $class; # Re-bless with our class

    $self->{isDebugging} = $isDebugging;
    $self->{isVerbose} = $isVerbose;

    my $hname = hostname;
    if(defined($self->{hosts}->{$hname})) {
        print "   Host-specific configuration for '$hname'\n";
        foreach my $keyname (keys %{$self->{hosts}->{$hname}}) {
            $self->{$keyname} = $self->{hosts}->{$hname}->{$keyname};
        }
    }

    my $APPNAME = $self->{appname};
    if(!defined($self->{remotedns})) {
        $self->{usedb} = 1;
    } else {
        $self->{usedb} = 0;
    }

    PageCamelLogo($APPNAME, $VERSION);
    print "Changing application name to '$APPNAME'\n\n";
    my $ps_appname = lc($APPNAME);
    $ps_appname =~ s/[^a-z0-9]+/_/gio;

    $PROGRAM_NAME = $ps_appname;

    if($self->{usedb}) {
        croak("No DB config for hostname $hname") unless(defined($self->{$hname}));
        my $dbconf = $self->{$hname};
        my $dbh = DBI->connect($dbconf->{dburl}, $dbconf->{dbuser}, $dbconf->{dbpassword}, {AutoCommit => 0, RaiseError => 0})
                    or croak("Can't connect to database: $ERRNO");
        $self->{dbh} = $dbh;
    }

    return $self;
}

my $needrestart;

sub run($self) {
    chdir($self->{homedir});
    my $lastrun = '';

    while(1) {

        my $now = getCurrentHour();
        if($now ne $lastrun) {
            $lastrun = $now;
            print "RENEWING CERTS\n";

            foreach my $domain (@{$self->{domain}}) {
                $self->{currentdomain} = $domain;
                $self->debuglog("Running for " . $domain->{workdir});
                my $filedir = $self->{homedir} . '/' . $domain->{workdir};
                my @domainlist;
                foreach my $prefix (@{$domain->{prefix}}) {
                    if($prefix eq '' || ref $prefix eq 'HASH') {
                        push @domainlist, $domain->{hostname};
                    } else {
                        push @domainlist, $prefix . '.' . $domain->{hostname};
                    }
                }

                my %options = (
                    'key' => $filedir . '/account.key',
                    'csr' => $filedir . '/domain.csr',
                    'crt' => $filedir . '/domain.crt',
                    'csr-key' => $filedir . '/domain.key',
                    'generate-missing' => 1,
                    'domains' => join(',', @domainlist),
                    'handle-as' => 'dns',
                    'email' => 'letsencrypt@cavac.at',
                    'live' => 1,
                );
                #if($self->{isDebugging}) {
                #    $options{live} = 0;
                #}
                if(-f $options{crt}) {
                    $options{renew} = 5;
                    $self->debuglog("Activating RENEW option");
                }
                $self->debuglog("Working");
                $self->work(\%options);
                $self->debuglog("Work done");
                if($needrestart) {
                    print "Restart required...\n";
                    foreach my $cmd (@{$self->{currentdomain}->{restartcommand}}) {
                        print "EXECUTING $cmd...\n";
                        my @lines = `$cmd`;
                        print join('', @lines);
                    }
                }
            }
            print "Going to sleep.....\n";
        }
        sleep 2;
    }
    return;
}

# -----------------------------------
# HELLLO WOOOOOORLLLLLLLLLDDDDDDDDDDD
# -----------------------------------
sub debuglog($self, @args) {
    #return unless($self->{isDebugging});

    my $printarg = join(' ## ', @args);
    print STDERR $printarg, "\n";
    return;
}

sub work($self, $opt) {
    my $rv = $self->parse_options($opt);
    return $rv if $rv;

    $needrestart = 0;

    my $le = Crypt::LE->new(autodir => 0, debug => $opt->{'debug'}, live => $opt->{'live'});

    if (-r $opt->{'key'}) {
        $self->debuglog("Loading an account key from $opt->{'key'}");
        $le->load_account_key($opt->{'key'}) == OK or return $self->_error("Could not load an account key: " . $le->error_details);
    } else {
        $self->debuglog("Generating a new account key");
        $le->generate_account_key == OK or return $self->_error("Could not generate an account key: " . $le->error_details);
        $self->debuglog("Saving generated account key into $opt->{'key'}");
        return $self->_error("Failed to save an account key file") if $self->_write($opt->{'key'}, $le->account_key);
    }

    if ($opt->{'revoke'}) {
        my $crt = $self->_read($opt->{'crt'});
        return $self->_error("Could not read the certificate file.") unless $crt;
        # Take the first certificate in file, disregard the issuer's one.
        $crt=~s/^(.*?-+\s*END CERTIFICATE\s*-+).*/$1/s;
        my $lrv = $le->revoke_certificate(\$crt);
        if ($lrv == OK) {
            $self->debuglog("Certificate has been revoked.");
        } elsif ($lrv == ALREADY_DONE) {
            $self->debuglog("Certificate has been ALREADY revoked.");
        } else {
            return $self->_error("Problem with revoking certificate: " . $le->error_details);
        }
        return;
    }

    if ($opt->{'domains'}) {
        if ($opt->{'e'}) {
            $self->debuglog("Could not encode arguments, support for internationalized domain names may not be available.");
        } else {
            my @domains = grep { $_ } split /\s*\,\s*/, $opt->{'domains'};
            $opt->{'domains'} = join ",", map { _puny($_) } @domains;
        }
    }
    if (-r $opt->{'csr'}) {
        $self->debuglog("Loading a CSR from $opt->{'csr'}");
        $le->load_csr($opt->{'csr'}, $opt->{'domains'}) == OK or return $self->_error("Could not load a CSR: " . $le->error_details);
        return $self->_error("For multi-webroot path usage, the amount of paths given should match the amount of domain names listed.") if $self->_path_mismatch($le, $opt);
        # Load existing CSR key if specified, even if we have CSR (for example for PFX export).
        if ($opt->{'csr-key'} and -e $opt->{'csr-key'}) {
            return $self->_error("Could not load existing CSR key from $opt->{'csr-key'} - " . $le->error_details) if $le->load_csr_key($opt->{'csr-key'});
        }
    } else {
        return $self->_error("For multi-webroot path usage, the amount of paths given should match the amount of domain names listed.") if $self->_path_mismatch($le, $opt);
        $self->debuglog("Generating a new CSR for domains $opt->{'domains'}");
        if (-e $opt->{'csr-key'}) {
             # Allow using pre-existing key when generating CSR
             return $self->_error("Could not load existing CSR key from $opt->{'csr-key'} - " . $le->error_details) if $le->load_csr_key($opt->{'csr-key'});
             $self->debuglog("New CSR will be based on '$opt->{'csr-key'}' key");
        } else {
             $self->debuglog("New CSR will be based on a generated key");
        }
        my ($type, $attr) = $opt->{'curve'} ? (KEY_ECC, $opt->{'curve'}) : (KEY_RSA, $opt->{'legacy'} ? 2048 : 4096);
        $le->generate_csr($opt->{'domains'}, $type, $attr) == OK or return $self->_error("Could not generate a CSR: " . $le->error_details);
        $self->debuglog("Saving a new CSR into $opt->{'csr'}");
        return "Failed to save a CSR" if $self->_write($opt->{'csr'}, $le->csr);
        if(!-e $opt->{'csr-key'}) {
            $self->debuglog("Saving a new CSR key into $opt->{'csr-key'}");
            return $self->_error("Failed to save a CSR key") if $self->_write($opt->{'csr-key'}, $le->csr_key);
        }
    }

    return if $opt->{'generate-only'};

    if ($opt->{'renew'}) {
        if ($opt->{'crt'} and -r $opt->{'crt'}) {
            $self->debuglog("Checking certificate for expiration (local file).");
            $opt->{'expires'} = $le->check_expiration($opt->{'crt'});
            $self->debuglog("Problem checking existing certificate file.") unless (defined $opt->{'expires'});
        }
        if(!defined $opt->{'expires'}) {
            $self->debuglog("Checking certificate for expiration (website connection).");
            foreach my $domain (@{$le->domains}) {
                $self->debuglog("Checking $domain");
                $opt->{'expires'} = $le->check_expiration("https://$domain/");
                last if (defined $opt->{'expires'});
            }
        }
        return $self->_error("Could not get the certificate expiration value, cannot renew.") unless (defined $opt->{'expires'});
        if ($opt->{'expires'} > $opt->{'renew'}) {
            $self->debuglog("Too early for renewal, certificate expires in $opt->{'expires'} days.");
            return;
        }
        $self->debuglog("Expiration threshold set at $opt->{'renew'} days, the certificate " . ($opt->{'expires'} < 0 ? "has already expired" : "expires in $opt->{'expires'} days") . " - will be renewing.");
    }

    if ($opt->{'email'}) {
        return $self->_error($le->error_details) if $le->set_account_email($opt->{'email'});
    }

    # Register.
    my $reg = $self->_register($le, $opt);
    return $reg if $reg;

    # We might not need to re-verify, verification holds for a while.
    my $new_crt_status = $le->request_certificate();
    if(!$new_crt_status) {
        $self->debuglog("Received domain certificate, no validation required at this time.");
    } else {
        # If it's not an auth problem, but blacklisted domains for example - stop.
        return $self->_error("Error requesting certificate: " . $le->error_details) if $new_crt_status != AUTH_ERROR;
        # Add multi-webroot option to parameters passed if it is set.
        $opt->{'handle-params'}->{'multiroot'} = $opt->{'multiroot'} if $opt->{'multiroot'};
        # Handle DNS internally along with HTTP
        my ($challenge_handler, $verification_handler) = ($opt->{'handler'}, $opt->{'handler'});
        if (!$opt->{'handler'}) {
            if ($opt->{'handle-as'}) {
                return $self->_error("Only 'dns' can be handled internally, use external modules for other verification types.") unless $opt->{'handle-as'}=~/^(dns)$/i;
            }
        }
        $opt->{'handle-params'}->{caller} = $self;
        return $self->_error($le->error_details) if $le->request_challenge();
        return $self->_error($le->error_details) if $le->accept_challenge(\&process_challenge_dns, $opt->{'handle-params'}, $opt->{'handle-as'});
        return $self->_error($le->error_details) if $le->verify_challenge(\&process_verification_dns, $opt->{'handle-params'}, $opt->{'handle-as'});
    }
    if(!$le->certificate) {
        $self->debuglog("Requesting domain certificate.");
        return $self->_error($le->error_details) if $le->request_certificate();
    }
    $self->debuglog("Requesting issuer's certificate.");
    if ($le->request_issuer_certificate()) {
        $self->debuglog("Could not download an issuer's certificate, try to download manually from " . $le->issuer_url);
        $self->debuglog("Will be saving the domain certificate alone, not the full chain.");
        return $self->_error("Failed to save the domain certificate file") if $self->_write($opt->{'crt'}, $le->certificate);
    } else {
        if(!$opt->{'legacy'}) {
            $self->debuglog("Saving the full certificate chain to $opt->{'crt'}.");
            return $self->_error("Failed to save the domain certificate file") if $self->_write($opt->{'crt'}, $le->certificate . "\n" . $le->issuer . "\n");
        } else {
            $self->debuglog("Saving the domain certificate to $opt->{'crt'}.");
            return $self->_error("Failed to save the domain certificate file") if $self->_write($opt->{'crt'}, $le->certificate);
            $opt->{'crt'}=~s/\.[^\.]+$//;
            $opt->{'crt'}.='.ca';
            $self->debuglog("Saving the issuer's certificate to $opt->{'crt'}.");
            $self->debuglog("Failed to save the issuer's certificate, try to download manually from " . $le->issuer_url) if $self->_write($opt->{'crt'}, $le->issuer);
        }
    }

    $self->debuglog("===> NOTE: You have been using the test server for this certificate. To issue a valid trusted certificate add --live option.") unless $opt->{'live'};
    $self->debuglog("The job is done, enjoy your certificate! For feedback and bug reports contact us at [ https://ZeroSSL.com | https://Do-Know.com ]\n");
    return { code => $opt->{'issue-code'}||0 };
}

sub parse_options($self, $opt) {
    $self->debuglog("[ ZeroSSL Crypt::LE client v$VERSION started. ]");
    $self->debuglog("Could not encode arguments, support for internationalized domain names may not be available.") if $opt->{'e'};

    return $self->_error("Incorrect parameters - need account key file name specified.") unless $opt->{'key'};
    if (-e $opt->{'key'}) {
        return $self->_error("Account key file is not readable.") unless (-r $opt->{'key'});
    } else {
        return $self->_error("Account key file is missing and the option to generate missing files is not used.") unless $opt->{'generate-missing'};
    }

    if(!$opt->{'crt'} && !$opt->{'generate-only'} && !$opt->{'update-contacts'}) {
        return $self->_error("Please specify a file name for the certificate.");
    }

    if ($opt->{'revoke'}) {
        return $self->_error("Need a certificate file for revoke to work.") unless ($opt->{'crt'} and -r $opt->{'crt'});
        return $self->_error("Need an account key - revoke assumes you had a registered account when got the certificate.") unless (-r $opt->{'key'});
    } elsif (!$opt->{'update-contacts'}) {
        return $self->_error("Incorrect parameters - need CSR file name specified.") unless $opt->{'csr'};
        if (-e $opt->{'csr'}) {
            return $self->_error("CSR file is not readable.") unless (-r $opt->{'csr'});
        } else {
            return $self->_error("CSR file is missing and the option to generate missing files is not used.") unless $opt->{'generate-missing'};
            return $self->_error("CSR file is missing and CSR-key file name is not specified.") unless $opt->{'csr-key'};
            return $self->_error("Domain list should be provided to generate a CSR.") unless ($opt->{'domains'} and $opt->{'domains'}!~/^[\s\,]*$/); ## no critic (ControlStructures::ProhibitNegativeExpressionsInUnlessAndUntilConditions)
        }

        if ($opt->{'path'}) {
            my @non_writable = ();
            foreach my $path (grep { $_ } split /\s*,\s*/, $opt->{'path'}) {
                push @non_writable, $path unless (-d $path and -w _);
            }
            return $self->_error("Path to save challenge files into should be a writable directory for: " . join(', ', @non_writable)) if @non_writable;
        } elsif ($opt->{'unlink'}) {
            return $self->_error("Unlink option will have no effect without --path.");
        }

        $opt->{'handle-as'} = $opt->{'handle-as'} ? lc($opt->{'handle-as'}) : 'http';

        if ($opt->{'handle-with'}) {
            eval {
                load $opt->{'handle-with'};
                $opt->{'handler'} = $opt->{'handle-with'}->new();
            };
            return $self->_error("Cannot use the module to handle challenges with.") if $@;
            my $method = 'handle_challenge_' . $opt->{'handle-as'};
            return $self->_error("Module to handle challenges does not seem to support the challenge type of $opt->{'handle-as'}.") unless $opt->{'handler'}->can($method);
            my $rv = $self->_load_params($opt, 'handle-params');
            return $rv if $rv;
        } else {
            $opt->{'handle-params'} = { path => $opt->{'path'}, unlink => $opt->{'unlink'} };
        }

        if ($opt->{'complete-with'}) {
            eval {
                load $opt->{'complete-with'};
                $opt->{'complete-handler'} = $opt->{'complete-with'}->new();
            };
            return $self->_error("Cannot use the module to complete processing with.") if $@;
            return $self->_error("Module to complete processing with does not seem to support the required 'complete' method.") unless $opt->{'complete-handler'}->can('complete');
            my $rv = $self->_load_params($opt, 'complete-params');
            return $rv if $rv;
        } else {
            $opt->{'complete-params'} = { path => $opt->{'path'}, unlink => $opt->{'unlink'} };
        }
    }
    return;
}

sub encode_args {
    my @ARGVmod = ();
    my @vals = ();
    # Account for cmd-shell parameters splitting.
    foreach my $param (@ARGV) {
        if ($param=~/^-/) {
            if (@vals) {
                push @ARGVmod, join(" ", @vals);
                @vals = ();
            }
            if ($param=~/^(.+?)\s*=\s*(.*)$/) {
                push @ARGVmod, $1;
                push @vals, $2 if $2;
            } else {
                push @ARGVmod, $param;
            }
        } else {
            push @vals, $param;
        }
    }
    push @ARGVmod, join(" ", @vals) if @vals;
    @ARGV = @ARGVmod;
    eval {
        my $from;
        if ($^O eq 'MSWin32') {
            load 'Win32';
            if (defined &Win32::GetACP) {
                $from = "cp" . Win32::GetACP();
            } else {
                load 'Win32::API';
                Win32::API->Import('kernel32', 'int GetACP()');
                $from = "cp" . GetACP() if (defined &GetACP);
            }
            $from ||= 'cp1252';
        } else {
            load 'I18N::Langinfo';
            $from = I18N::Langinfo::langinfo(&I18N::Langinfo::CODESET) || 'UTF-8';
        }
        @ARGV = map { decode $from, $_ } @ARGV;
        autoload 'URI::_punycode';
    };
    return $@;
}

sub _register($self, $le, $opt) {
    return $self->_error("Could not load the resource directory: " . $le->error_details) if $le->directory;
    $self->debuglog("Registering the account key");
    return $self->_error($le->error_details) if $le->register;
    my $current_account_id = $le->registration_id || 'unknown';
    $self->debuglog($le->new_registration ? "The key has been successfully registered. ID: $current_account_id" : "The key is already registered. ID: $current_account_id");
    $self->debuglog("Make sure to check TOS at " . $le->tos) if ($le->tos_changed and $le->tos);
    $le->accept_tos();
    if (my $contacts = $le->contact_details) {
        $self->debuglog("Current contact details: " . join(", ", map { s/^\w+://; $_ } (ref $contacts eq 'ARRAY' ? @{$contacts} : ($contacts))));
    }
    return 0;
}

sub _puny($domain) {
    my @rv = ();
    for (split /\./, $domain) {
        my $enc = encode_punycode($_);
        push @rv, ($_ eq $enc) ? $_ : 'xn--' . $enc;
    }
    return join '.', @rv;
}

sub _path_mismatch($self, $le, $opt) {
    if ($opt->{'path'} and my $domains = $le->domains) {
        my @paths = grep {$_} split /\s*,\s*/, $opt->{'path'};
        if (@paths > 1) {
            return 1 unless @{$domains} == @paths;
            for (my $i = 0; $i <= $#paths; $i++) {
                $opt->{'multiroot'}->{$domains->[$i]} = $paths[$i];
            }
        }
    }
    return 0;
}

sub _load_params($self, $opt, $type) {
    return unless ($opt and $opt->{$type});
    if ($opt->{$type}!~/[\{\[\}\]]/) {
        $opt->{$type} = $self->_read($opt->{$type});
        return $self->_error("Could not read the file with '$type'.") unless $opt->{$type};
    }
    my $j = JSON->new->canonical()->allow_nonref();
    eval {
        $opt->{$type} = $j->decode($opt->{$type});
    };
    return ($@ or (ref $opt->{$type} ne 'HASH')) ?
        $self->_error("Could not decode '$type'. Please make sure you are providing a valid JSON document and {} are in place." . ($opt->{'debug'} ? $@ : '')) : 0;
}

sub _read($self, $file) {
    return unless (-e $file and -r _);
    my $fh = IO::File->new();
    $fh->open($file, '<:encoding(UTF-8)') or return;
    local $/;
    my $src = <$fh>;
    $fh->close;
    return $src;
}

sub _write($self, $file, $content) {
    return 1 unless ($file and $content);
    my $fh = IO::File->new($file, 'w');
    return 1 unless defined $fh;
    $fh->binmode;
    print $fh $content;
    $fh->close;
    return 0;
}

sub _error($self, $msg, $code) {
    return { msg => $msg, code => $code||255 };
}

sub process_challenge_dns($challenge, $params) {
    my $self = $params->{caller};
    my $value = encode_base64url(sha256("$challenge->{token}.$challenge->{fingerprint}"));
    my $tld = $challenge->{domain};
    my $basedomain = $self->{currentdomain}->{hostname};
    my $extension = $tld;
    $extension =~ s/$basedomain$//;
    $extension = '_acme-challenge.' . $extension;
    $extension =~ s/\.$//;

    if($self->{usedb}) {
        my $delsth = $self->{dbh}->prepare_cached("DELETE FROM nameserver_domain_entry WHERE domain_fqdn = ? and hostname = ?")
                or croak($self->{dbh}->errstr);
        my $inssth = $self->{dbh}->prepare_cached("INSERT INTO nameserver_domain_entry (domain_fqdn, hostname, record_type, textrecord, delete_after)
                                           VALUES (?, ?, 'TXT', ?, now() + interval '2 hours')")
                or croak($self->{dbh}->errstr);
        print STDERR "DNS RECORD FOR $extension . $basedomain with value $value\n";
        if(!$delsth->execute($basedomain, $extension) ||
           !$inssth->execute($basedomain, $extension, $value)) {
            croak("FAILED TO UPDATE DNS RECORD: " . $self->{dbh}->errstr);
        } else {
            $self->{dbh}->commit;
        }
    } else {
        my $data = $self->remoteCall('add', (basedomain => $basedomain, extension => $extension, value => $value));
        if($data->{error}) {
            $self->debuglog("FAILED TO SET REMOTE DNS!!!!");
            sleep(10);
            croak("Failed to set remote DNS");
        }
    }

    return 1;
}

sub process_verification_dns($results, $params) {
    my $self = $params->{caller};
    $self->debuglog("Processing the 'dns' verification for '$results->{domain}'");
    if ($results->{valid}) {
        $self->debuglog("Domain verification results for '$results->{domain}': success.");
    } else {
        $self->debuglog("Domain verification results for '$results->{domain}': error. " . $results->{'error'});
    }
    my $tld = $results->{domain};
    my $basedomain = $self->{currentdomain}->{hostname};
    my $extension = $tld;
    $extension =~ s/$basedomain$//;
    $extension = '_acme-challenge.' . $extension;
    $extension =~ s/\.$//;

    if($self->{usedb}) {
        my $delsth = $self->{dbh}->prepare_cached("DELETE FROM nameserver_domain_entry WHERE domain_fqdn = ? and hostname = ?")
                or croak($self->{dbh}->errstr);
        print STDERR "DELETING DNS RECORD FOR $extension . $basedomain\n";
        if(!$delsth->execute($basedomain, $extension)) {
            croak("FAILED TO UPDATE DNS RECORD: " . $self->{dbh}->errstr);
        } else {
            $self->{dbh}->commit;
        }
    } else {
        my $data = $self->remoteCall('add', (basedomain => $basedomain, extension => $extension));
        if($data->{error}) {
            $self->debuglog("FAILED TO REMOVE REMOTE DNS!!!!");
        }
    }
    $needrestart = 1;
    return 1;
}

sub remoteCall($self, $command, @options) {
    my $error = 0;

    my $xmlrpc = XML::RPC->new($self->{remotedns}->{url}, ("User-Agent" => "PageCamel LetsEncrypt/$VERSION"));
    $xmlrpc->credentials($self->{remotedns}->{user}, $self->{remotedns}->{pass});
    my $data;

    eval {
        local $SIG{ALRM} = sub {die "RPC Timeout"};
        alarm $self->{remotedns}->{timeout};
        $data = $xmlrpc->call($command, @options);
        alarm 0;
    };
    alarm 0;
    if($@) {
        print STDERR "ERROR: ", $@, "\n";
        die("RPC Timeout encountered!\n") if($@ eq "RPC Timeout");
        $error = 1;
    }

    if(!defined($data) || ref($data) ne 'HASH') {
        $data = {};
    }

    if(!defined($data->{status}) || $data->{status} ne '1') {
        $error = 1;
    }

    $data->{error} = $error;
    return $data;
}

1;
