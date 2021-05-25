# PAGECAMEL  (C) 2008-2020 Rene Schickbauer
# Developed under Artistic license
package PageCamel::CMDLine::LetsEncrypt;
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
use IO::File;
use JSON::MaybeXS;
use Module::Load;
use Encode 'decode';
use Digest::SHA 'sha256';
use MIME::Base64 'encode_base64url';
use Crypt::LE ':errors', ':keys';
use URI::_punycode;

use PageCamel::Helpers::ConfigLoader;
use PageCamel::Helpers::Logo;
use PageCamel::Helpers::DateStrings;
use XML::RPC;
#use Getopt::Long;

use DBI;
use Sys::Hostname;

my $_self;

sub new {
    my ($proto, $configfile, $isDebugging, $isVerbose) = @_;
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

    $_self = $self;

    return $self;
}

my $needrestart;

sub run {
    my ($self) = @_;

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

sub debuglog {
    my ($self, @args) = @_;

    #return unless($self->{isDebugging});

    my $printarg = join(' ## ', @args);
    print STDERR $printarg, "\n";
    return;
}
sub work {
    my ($self, $opt) = @_;
    my $rv = $self->parse_options($opt);
    return $rv if $rv;
    # Set the default protocol version to 2 unless it is set explicitly or custom server/directory is set (in which case auto-sense is used).
    $opt->{'api'} = 2 unless (defined $opt->{'api'} or $opt->{'server'} or $opt->{'directory'});
    my $le = Crypt::LE->new(
	autodir => 0,
	dir => $opt->{'directory'},
	server => $opt->{'server'},
	live => $opt->{'live'},
	version => $opt->{'api'}||0,
	debug => $opt->{'debug'},
	logger => $opt->{'logger'},
    );

    if (-r $opt->{'key'}) {
        $self->debuglog("Loading an account key from $opt->{'key'}");
        $le->load_account_key($opt->{'key'}) == OK or return $self->_error("Could not load an account key: " . $le->error_details, 'ACCOUNT_KEY_LOAD');
    } else {
        $self->debuglog("Generating a new account key");
        $le->generate_account_key == OK or return $self->_error("Could not generate an account key: " . $le->error_details, 'ACCOUNT_KEY_GENERATE');
        $self->debuglog("Saving generated account key into $opt->{'key'}");
        return $self->_error("Failed to save an account key file", 'ACCOUNT_KEY_SAVE') if $self->_write($opt->{'key'}, $le->account_key);
    }

    if ($opt->{'update-contacts'}) {
        # Register.
        my $reg = $self->_register($le, $opt);
        return $reg if $reg;
        my @contacts = (lc($opt->{'update-contacts'}) eq 'none') ? () : grep { $_ } split /\s*\,\s*/, $opt->{'update-contacts'};
        my @rejected = ();
        foreach (@contacts) {
            /^(\w+:)?(.+)$/;
            # NB: tel is not supported by LE at the moment.
            my ($prefix, $data) = (lc($1||''), $2);
            push @rejected, $_ unless ($data=~/^[^\@]+\@[^\.]+\.[^\.]+/ and (!$prefix or ($prefix eq 'mailto:')));
        }
        return $self->_error("Unknown format for the contacts: " . join(", ", @rejected), 'CONTACTS_FORMAT') if @rejected;
        return $self->_error("Could not update contact details: " . $le->error_details, 'CONTACTS_UPDATE') if $le->update_contacts(\@contacts);
        $self->debuglog("Contact details have been updated.");
        return;
    }

    if ($opt->{'revoke'}) {
        my $crt = $self->_read($opt->{'crt'});
        return $self->_error("Could not read the certificate file.", 'CERTIFICATE_FILE_READ') unless $crt;
        # Take the first certificate in file, disregard the issuer's one.
        $crt=~s/^(.*?-+\s*END CERTIFICATE\s*-+).*/$1/s;

        # Register.
        my $reg = $self->_register($le, $opt);
        return $reg if $reg;
        my $rv = $le->revoke_certificate(\$crt);
        if ($rv == OK) {
            $self->debuglog("Certificate has been revoked.");
        } elsif ($rv == ALREADY_DONE) {
            $self->debuglog("Certificate has been ALREADY revoked.");
        } else {
            return $self->_error("Problem with revoking certificate: " . $le->error_details, 'CERTIFICATE_REVOKE');
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
        $le->load_csr($opt->{'csr'}, $opt->{'domains'}) == OK or return $self->_error("Could not load a CSR: " . $le->error_details, 'CSR_LOAD');
        return $self->_error("For multi-webroot path usage, the amount of paths given should match the amount of domain names listed.", 'WEBROOT_MISMATCH') if _path_mismatch($le, $opt);
        # Load existing CSR key if specified, even if we have CSR (for example for PFX export).
        if ($opt->{'csr-key'} and -e $opt->{'csr-key'}) {
            return $self->_error("Could not load existing CSR key from $opt->{'csr-key'} - " . $le->error_details, 'CSR_KEY_LOAD') if $le->load_csr_key($opt->{'csr-key'});
        }
    } else {
        $self->debuglog("Generating a new CSR for domains $opt->{'domains'}");
        if (-e $opt->{'csr-key'}) {
             # Allow using pre-existing key when generating CSR
             return $self->_error("Could not load existing CSR key from $opt->{'csr-key'} - " . $le->error_details, 'CSR_KEY_LOAD') if $le->load_csr_key($opt->{'csr-key'});
             $self->debuglog("New CSR will be based on '$opt->{'csr-key'}' key");
        } else {
             $self->debuglog("New CSR will be based on a generated key");
        }
        my ($type, $attr) = $opt->{'curve'} ? (KEY_ECC, $opt->{'curve'}) : (KEY_RSA, $opt->{'legacy'} ? 2048 : 4096);
        $le->generate_csr($opt->{'domains'}, $type, $attr) == OK or return $self->_error("Could not generate a CSR: " . $le->error_details, 'CSR_GENERATE');
        $self->debuglog("Saving a new CSR into $opt->{'csr'}");
        return "Failed to save a CSR" if $self->_write($opt->{'csr'}, $le->csr);
        unless (-e $opt->{'csr-key'}) {
            $self->debuglog("Saving a new CSR key into $opt->{'csr-key'}");
            return $self->_error("Failed to save a CSR key", 'CSR_SAVE') if $self->_write($opt->{'csr-key'}, $le->csr_key);
        }
        return $self->_error("For multi-webroot path usage, the amount of paths given should match the amount of domain names listed.", 'WEBROOT_MISMATCH') if _path_mismatch($le, $opt);
    }

    return if $opt->{'generate-only'};

    if ($opt->{'renew'}) {
        if ($opt->{'crt'} and -r $opt->{'crt'}) {
            $self->debuglog("Checking certificate for expiration (local file).");
            $opt->{'expires'} = $le->check_expiration($opt->{'crt'});
            $self->debuglog("Problem checking existing certificate file.") unless (defined $opt->{'expires'});
        }
        unless (defined $opt->{'expires'}) {
            $self->debuglog("Checking certificate for expiration (website connection).");
            if ($opt->{'renew-check'}) {
                $self->debuglog("Checking $opt->{'renew-check'}");
                $opt->{'expires'} = $le->check_expiration("https://$opt->{'renew-check'}/");
            } else {
                my %seen;
                # Check wildcards last, try www for those unless already seen.
                foreach my $e (sort { $b cmp $a } @{$le->domains}) {
                   my $domain = $e=~/^\*\.(.+)$/ ? "www.$1" : $e;
                   next if $seen{$domain}++;
                   $self->debuglog("Checking $domain");
                   $opt->{'expires'} = $le->check_expiration("https://$domain/");
                   last if (defined $opt->{'expires'});
               }
            }
        }
        return $self->_error("Could not get the certificate expiration value, cannot renew.", 'EXPIRATION_GET') unless (defined $opt->{'expires'});
        if ($opt->{'expires'} > $opt->{'renew'}) {
            # A bit specific case - this is not an error technically but some might want an error code.
            # So the message is displayed on "info" level to prevent getting through "quiet" mode, but an error can still be set.
            $self->debuglog("Too early for renewal, certificate expires in $opt->{'expires'} days.");
            return $self->_error("", 'EXPIRATION_EARLY');
        }
        $self->debuglog("Expiration threshold set at $opt->{'renew'} days, the certificate " . ($opt->{'expires'} < 0 ? "has already expired" : "expires in $opt->{'expires'} days") . " - will be renewing.");
    }
    
    if ($opt->{'email'}) {
        return $self->_error($le->error_details, 'EMAIL_SET') if $le->set_account_email($opt->{'email'});
    }

    # Register.
    my $reg = $self->_register($le, $opt);
    return $reg if $reg;

    # Build a copy of the parameters from the command line and added during the runtime, reduced to plain vars and hashrefs.
    my %callback_data = map { $_ => $opt->{$_} } grep { ! ref $opt->{$_} or ref $opt->{$_} eq 'HASH' } keys %{$opt};

    # We might not need to re-verify, verification holds for a while. NB: Only do that for the standard LE servers.
    my $new_crt_status = ($opt->{'server'} or $opt->{'directory'}) ? AUTH_ERROR : $le->request_certificate();
    unless ($new_crt_status) {
        $self->debuglog("Received domain certificate, no validation required at this time.");
    } else {
        # If it's not an auth problem, but blacklisted domains for example - stop.
        return $self->_error("Error requesting certificate: " . $le->error_details, 'CERTIFICATE_GET') if $new_crt_status != AUTH_ERROR;
        # Handle DNS internally along with HTTP
        my ($challenge_handler, $verification_handler) = ($opt->{'handler'}, $opt->{'handler'});
        if (!$opt->{'handler'}) {
            if ($opt->{'handle-as'}) {
                return $self->_error("Only 'http' and 'dns' can be handled internally, use external modules for other verification types.", 'VERIFICATION_METHOD') unless $opt->{'handle-as'}=~/^(http|dns)$/i;
                if (lc($1) eq 'dns') {
                    ($challenge_handler, $verification_handler) = (\&process_challenge_dns, \&process_verification_dns);
                }
            }
        }

        return $self->_error($le->error_details, 'CHALLENGE_REQUEST') if $le->request_challenge();
        return $self->_error($le->error_details, 'CHALLENGE_ACCEPT') if $le->accept_challenge($challenge_handler || \&process_challenge, \%callback_data, $opt->{'handle-as'});

        # If delayed mode is requested, exit early with the same code as for the issuance.
        return { code => $opt->{'issue-code'}||0 } if $opt->{'delayed'};

        # Refresh nonce in case of a long delay between the challenge and the verification step.
        return $self->_error($le->error_details, 'NONCE_REFRESH') unless $le->new_nonce();
        return $self->_error($le->error_details, 'CHALLENGE_VERIFY') if $le->verify_challenge($verification_handler || \&process_verification, \%callback_data, $opt->{'handle-as'});
    }
    unless ($le->certificate) {
        $self->debuglog("Requesting domain certificate.");
        return $self->_error($le->error_details, 'CERTIFICATE_REQUEST') if $le->request_certificate();
    }

    my ($certificate, $issuer, $saved);

    if ($opt->{'alternative'}) {
        $self->debuglog("Requesting alternative certificates.");
        return $opt->{'logger'}->error($le->error_details, 'CERTIFICATE_REQUEST') if $le->request_alternatives();
        if (my $alternative = $le->alternative_certificate($opt->{'alternative'} - 1)) {
            ($certificate, $issuer) = @{$alternative};
        } else {
            return $self->_error("There is no alternative certificate #$opt->{'alternative'}.", 'CERTIFICATE_REQUEST');
        }
    } else {
        $self->debuglog("Requesting issuer's certificate.");
        $certificate = $le->certificate;
        if ($le->request_issuer_certificate()) {
            $opt->{'logger'}->error("Could not download an issuer's certificate, " . ($le->issuer_url ? "try to download manually from " . $le->issuer_url : "the URL has not been provided."));
            $self->debuglog("Will be saving the domain certificate alone, not the full chain.");
            return $self->_error("Failed to save the domain certificate file", 'CERTIFICATE_SAVE') if $self->_write($opt->{'crt'}, $certificate);
            $saved = 1;
        } else {
            $issuer = $le->issuer;
        }
    }

    unless ($saved) {
        unless ($opt->{'legacy'}) {
            $self->debuglog("Saving the full certificate chain to $opt->{'crt'}.");
            return $self->_error("Failed to save the domain certificate file", 'CERTIFICATE_SAVE') if $self->_write($opt->{'crt'}, $certificate . "\n" . $issuer . "\n");
        } else {
            $self->debuglog("Saving the domain certificate to $opt->{'crt'}.");
            return $self->_error("Failed to save the domain certificate file", 'CERTIFICATE_SAVE') if $self->_write($opt->{'crt'}, $certificate);
            $opt->{'crt'}=~s/\.[^\.]+$//;
            $opt->{'crt'}.='.ca';
            $self->debuglog("Saving the issuer's certificate to $opt->{'crt'}.");
            $opt->{'logger'}->error("Failed to save the issuer's certificate", 'CERTIFICATE_SAVE') if $self->_write($opt->{'crt'}, $issuer);
        }
    }
    if ($opt->{'export-pfx'}) {
        # Note: At this point the certificate is already issued, but with pfx export option active we will return an error if export has failed, to avoid triggering
        # the 'success' batch processing IIS users might have set up on issuance and export.
        if ($issuer) {
            my $target_pfx = $opt->{'crt'};
            $target_pfx=~s/\.[^\.]*$//;
            $self->debuglog("Exporting certificate to $target_pfx.pfx.");
            return $self->_error("Error exporting pfx: " . $le->error_details, 'CERTIFICATE_EXPORT') if $le->export_pfx("$target_pfx.pfx", $opt->{'export-pfx'}, $certificate, $le->csr_key, $issuer, $opt->{'tag-pfx'});
        } else {
            return $self->_error("Issuer's certificate is not available, skipping pfx export to avoid creating an invalid pfx.", 'CERTIFICATE_EXPORT_ISSUER');
        }
    }
    if ($opt->{'complete-handler'}) {
        my $data = {
            # Note, certificate here is just a domain certificate, issuer is passed separately - so handler could merge those or use them separately as well.
            certificate => $le->certificate, certificate_file => $opt->{'crt'}, key_file => $opt->{'csr-key'}, issuer => $le->issuer, alternatives => $le->alternative_certificates(),
            domains => $le->domains, logger => $opt->{'logger'},
        };
        my $rv;
        eval {
            $rv = $opt->{'complete-handler'}->complete($data, \%callback_data);
        };
        if ($@ or !$rv) {
            return $self->_error("Completion handler " . ($@ ? "thrown an error: $@" : "did not return a true value"), 'COMPLETION_HANDLER');
        }
    }

    $self->debuglog("===> NOTE: You have been using the test server for this certificate. To issue a valid trusted certificate add --live option.") unless $opt->{'live'};
    $self->debuglog("The job is done, enjoy your certificate!\n");
    return { code => $opt->{'issue-code'}||0 };
}

sub parse_options {
    my ($self, $opt) = @_;
    my $args = @ARGV;

    #GetOptions ($opt, 'key=s', 'csr=s', 'csr-key=s', 'domains=s', 'path=s', 'crt=s', 'email=s', 'curve=s', 'server=s', 'directory=s', 'api=i', 'config=s', 'renew=i', 'renew-check=s','issue-code=i',
    #    'handle-with=s', 'handle-as=s', 'handle-params=s', 'complete-with=s', 'complete-params=s', 'log-config=s', 'update-contacts=s', 'export-pfx=s', 'tag-pfx=s',
    #    'alternative=i', 'generate-missing', 'generate-only', 'revoke', 'legacy', 'unlink', 'delayed', 'live', 'quiet', 'debug+', 'help') ||
    #    return $self->_error("Use --help to see the usage examples.", 'PARAMETERS_PARSE');

    if ($opt->{'config'}) {
        return $self->_error("Configuration file '$opt->{'config'}' is not readable", 'PARAMETERS_PARSE') unless -r $opt->{'config'};
        my $rv = $self->parse_config($opt);
        return $self->_error("Configuration file error: $rv" , 'PARAMETERS_PARSE') if $rv;
    }

    $self->debuglog("[ Crypt::LE client v$VERSION started. ]");
    my $custom_server;

    foreach my $url_type (qw<server directory>) {
        if ($opt->{$url_type}) {
            return $self->_error("Unsupported protocol for the custom $url_type URL: $1.", 'CUSTOM_' . uc($url_type) . '_URL') if ($opt->{$url_type}=~s~^(.*?)://~~ and uc($1) ne 'HTTPS');
            my $server = $opt->{$url_type}; # For logging.
            $self->debuglog("Remember to URL-escape special characters if you are using $url_type URL with basic auth credentials.") if $server=~s~[^@/]*@~~;
            $self->debuglog("Custom $url_type URL 'https://$server' is used.");
            $self->debuglog("Note: '$url_type' setting takes over the 'server' one.") if $custom_server;
            $custom_server = 1;
        }
    }
    $self->debuglog("Note: 'live' option is ignored.") if ($opt->{'live'} and $custom_server);

    if ($opt->{'renew-check'}) {
        $self->_error("Unsupported protocol for the renew check URL: $1.", 'RENEW_CHECK_URL') if ($opt->{'renew-check'}=~s~^(.*?)://~~ and uc($1) ne 'HTTPS');
    }

    return $self->_error("Incorrect parameters - need account key file name specified.", 'ACCOUNT_KEY_FILENAME_REQUIRED') unless $opt->{'key'};
    if (-e $opt->{'key'}) {
        return $self->_error("Account key file is not readable.", 'ACCOUNT_KEY_NOT_READABLE') unless (-r $opt->{'key'});
    } else {
        return $self->_error("Account key file is missing and the option to generate missing files is not used.", 'ACCOUNT_KEY_MISSING') unless $opt->{'generate-missing'};
    }

    unless ($opt->{'crt'} or $opt->{'generate-only'} or $opt->{'update-contacts'}) {
        return $self->_error("Please specify a file name for the certificate.", 'CERTIFICATE_FILENAME_REQUIRED');
    }

    if ($opt->{'export-pfx'}) {
        if ($opt->{'crt'} and $opt->{'crt'}=~/\.pfx$/i) {
            return $self->_error("Please ensure that the extension of the certificate filename is different from '.pfx' to be able to additionally export the certificate in pfx form.", 'CERTIFICATE_BAD_FILENAME_EXTENSION');
        }
        unless ($opt->{'csr-key'} and (-r $opt->{'csr-key'} or ($opt->{'generate-missing'} and ! -e $opt->{'csr'}))) {
            return $self->_error("Need either existing csr-key specified or having CSR file generated (via 'generate-missing') for PFX export to work", 'NEED_CSR_KEY_FOR_EXPORT');
        }
    } elsif ($opt->{'tag-pfx'}) {
        $self->debuglog("Option 'tag-pfx' makes no sense without 'export-pfx' - ignoring.");
    }

    if ($opt->{'revoke'}) {
        return $self->_error("Need a certificate file for revoke to work.", 'NEED_CERTIFICATE_FOR_REVOKE') unless ($opt->{'crt'} and -r $opt->{'crt'});
        return $self->_error("Need an account key - revoke assumes you had a registered account when got the certificate.", 'NEED_ACCOUNT_KEY_FOR_REVOKE') unless (-r $opt->{'key'});
    } elsif (!$opt->{'update-contacts'}) {
        return $self->_error("Incorrect parameters - need CSR file name specified.", 'CSR_FILENAME_REQUIRED') unless $opt->{'csr'};
        if (-e $opt->{'csr'}) {
            return $self->_error("CSR file is not readable.", 'CSR_NOT_READABLE') unless (-r $opt->{'csr'});
        } else {
            return $self->_error("CSR file is missing and the option to generate missing files is not used.", 'CSR_MISSING') unless $opt->{'generate-missing'};
            return $self->_error("CSR file is missing and CSR-key file name is not specified.", 'CSR_MISSING') unless $opt->{'csr-key'};
            return $self->_error("Domain list should be provided to generate a CSR.", 'DOMAINS_REQUIRED') unless ($opt->{'domains'} and $opt->{'domains'}!~/^[\s\,]*$/);
        }

        if ($opt->{'path'}) {
            my @non_writable = ();
            foreach my $path (grep { $_ } split /\s*,\s*/, $opt->{'path'}) {
                push @non_writable, $path unless (-d $path and -w _);
            }
            return $self->_error("Path to save challenge files into should be a writable directory for: " . join(', ', @non_writable), 'CHALLENGE_DIRECTORY_NOT_WRITABLE') if @non_writable;
        } elsif ($opt->{'unlink'}) {
            return $self->_error("Unlink option will have no effect without --path.", 'UNLINK_WITHOUT_PATH');
        }

        $opt->{'handle-as'} = $opt->{'handle-as'} ? lc($opt->{'handle-as'}) : 'http';

        if ($opt->{'handle-with'}) {
            my $error = $self->_load_mod($opt, 'handle-with', 'handler');
            return $self->_error("Cannot use the module to handle challenges with - $error", 'CHALLENGE_MODULE_UNAVAILABLE') if $error;
            my $method = 'handle_challenge_' . $opt->{'handle-as'};
            return $self->_error("Module to handle challenges does not seem to support the challenge type of $opt->{'handle-as'}.", 'CHALLENGE_MODULE_UNSUPPORTED') unless $opt->{'handler'}->can($method);
            my $rv = $self->_load_params($opt, 'handle-params');
            return $rv if $rv;
        }

        if ($opt->{'complete-with'}) {
            my $error = $self->_load_mod($opt, 'complete-with', 'complete-handler');
            return $self->_error("Cannot use the module to complete processing with - $error.", 'COMPLETION_MODULE_UNAVAILABLE') if $error;
            return $self->_error("Module to complete processing with does not seem to support the required 'complete' method.", 'COMPLETION_MODULE_UNSUPPORTED') unless $opt->{'complete-handler'}->can('complete');
            my $rv = $self->_load_params($opt, 'complete-params');
            return $rv if $rv;
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

sub parse_config {
    my ($self, $opt) = @_;
    unless ($opt) {
        return sub {
            return { code => 1, msg => shift }
        }
    }
    if (my $config = $self->_read($opt->{'config'})) {
        # INI-like, simplified.
        my ($cl, $section) = (0, '');
        my $sections = {
            errors => {
                # NB: Early renewal stop is not considered an error by default.
                EXPIRATION_EARLY => 0,
            },
        };
        for (split /\r?\n/, $config) {
            $cl++;
            next if /^\s*(?:;|#)/;
            if (/^\[\s*(\w*)\s*\]$/) {
                $section = $1;
                return "Invalid section at line $cl." unless ($section and $sections->{$section});
            } else {
                return "Invalid line $cl - outside of section." unless $section;
                return "Invalid line $cl - not a key/value." unless /^\s*(\w+)\s*=\s*([^"'\;\#].*)$/;
                my ($key, $val) = ($1, $2);
                $val=~s/\s*(?:;|#).*$//;
                $sections->{$section}->{$key} = $val;
            }
        }
        # Process errors section.
        my $debug = $opt->{'debug'};
        my $errors = delete $sections->{'errors'};
        $opt->{'error'} = sub {
            my ($msg, $code) = @_;
            if ($code and $code!~/^\d+$/) {
                # Unless associated with 0 exit value, in debug mode
                # prefix the message with a passed down code.
                unless (!$debug or (defined $errors->{$code} and !$errors->{$code})) {
                    $msg = "[ $code ] " . ($msg || '');
                }
                $code = $errors->{$code};
            }
            return { msg => $msg, code => $code };
        };
        return;
    } else {
        return "Could not read config file.";
    }
}

sub _register {
    my ($self, $le, $opt) = @_;
    return $self->_error("Could not load the resource directory: " . $le->error_details, 'RESOURCE_DIRECTORY_LOAD') if $le->directory;
    $self->debuglog("Registering the account key");
    return $self->_error($le->error_details, 'REGISTRATION') if $le->register;
    my $current_account_id = $le->registration_id || 'unknown';
    $self->debuglog($le->new_registration ? "The key has been successfully registered. ID: $current_account_id" : "The key is already registered. ID: $current_account_id");
    $self->debuglog("Make sure to check TOS at " . $le->tos) if ($le->tos_changed and $le->tos);
    $le->accept_tos();
    if (my $contacts = $le->contact_details) {
        $self->debuglog("Current contact details: " . join(", ", map { s/^\w+://; $_ } (ref $contacts eq 'ARRAY' ? @{$contacts} : ($contacts))));
    }
    return 0;
}

sub _puny {
    my $domain = shift;
    my @rv = ();
    for (split /\./, $domain) {
        my $enc = encode_punycode($_);
        push @rv, ($_ eq $enc) ? $_ : 'xn--' . $enc;
    }
    return join '.', @rv;
}

sub _path_mismatch {
    my ($le, $opt) = @_;
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

sub _load_mod {
    my ($self, $opt, $type, $handler) = @_;
    return unless ($opt and $opt->{$type});
    eval {
        my $mod = $opt->{$type};
        if ($mod=~/(\w+)\.pm$/i) {
            $mod = $1;
            $opt->{$type} = "./$opt->{$type}" unless $opt->{$type}=~/^(\w+:|\.*[\/\\])/;
        }
        load $opt->{$type};
        $opt->{$handler} = $mod->new();
    };
    if (my $rv = $@) {
        $rv=~s/(?: in) \@INC .*$//s; $rv=~s/Compilation failed[^\n]+$//s;
        return $rv || 'error';
    }
    return undef;
}

sub _load_params {
    my ($self, $opt, $type) = @_;
    return unless ($opt and $opt->{$type});
    if ($opt->{$type}!~/[\{\[\}\]]/) {
        $opt->{$type} = $self->_read($opt->{$type});
        return $self->_error("Could not read the file with '$type'.", 'FILE_READ') unless $opt->{$type};
    }
    my $j = JSON->new->canonical()->allow_nonref();
    eval {
        $opt->{$type} = $j->decode($opt->{$type});
    };
    return ($@ or (ref $opt->{$type} ne 'HASH')) ?
        $self->_error("Could not decode '$type'. Please make sure you are providing a valid JSON document and {} are in place." . ($opt->{'debug'} ? $@ : ''), 'JSON_DECODE') : 0;
}

sub _read {
    my ($self, $file) = @_;
    return unless (-e $file and -r _);
    my $fh = IO::File->new();
    $fh->open($file, '<:encoding(UTF-8)') or return;
    local $/;
    my $src = <$fh>;
    $fh->close;
    return $src;
}

sub _write {
    my ($self, $file, $content) = @_;
    return 1 unless ($file and $content);
    my $fh = IO::File->new($file, 'w');
    return 1 unless defined $fh;
    $fh->binmode;
    print $fh $content;
    $fh->close;
    return 0;
}

sub _error {
    my ($self, $msg, $code) = @_;
    return { msg => $msg, code => $code||255 };
}

sub process_challenge_dns {
    my ($challenge, $params) = @_; # $self gets passed as parameter in callback
    my $self = $_self;
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

sub process_verification_dns {
    my ($results, $params) = @_; # $self gets passed as parameter in callback
    my $self = $_self;
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

sub remoteCall {
    my ($self, $command, @options) = @_;
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
