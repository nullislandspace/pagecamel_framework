use v5.38;
use ExtUtils::MakeMaker;
use Config;
use File::Find;

# Build PM hash excluding any nested blib directories
my %pm;
find(sub {
    return unless -f $_;
    return if $File::Find::dir =~ m{/blib/};  # Skip nested blib directories
    my $file = $File::Find::name;
    return unless $file =~ /\.(pm|pl|json|md|tt)$/;
    (my $inst = $file) =~ s{^lib/}{blib/lib/};
    $pm{$file} = $inst;
}, 'lib');

# HTTP/3 support detection - automatically enabled if libraries are available
my $http3Enabled = 0;
my @http3Libs = ();
my @http3Incs = ();

print "Checking for HTTP/3 library support...\n";

# Check for ngtcp2 via pkg-config
my $ngtcp2Cflags = `pkg-config --cflags libngtcp2 2>/dev/null`;
my $ngtcp2Libs = `pkg-config --libs libngtcp2 2>/dev/null`;
# Try GnuTLS crypto first, then fall back to quictls/OpenSSL
my $ngtcp2CryptoCflags = `pkg-config --cflags libngtcp2_crypto_gnutls 2>/dev/null`;
my $ngtcp2CryptoLibs = `pkg-config --libs libngtcp2_crypto_gnutls 2>/dev/null`;
my $usingGnutls = 1;

# Check for nghttp3 via pkg-config
my $nghttp3Cflags = `pkg-config --cflags libnghttp3 2>/dev/null`;
my $nghttp3Libs = `pkg-config --libs libnghttp3 2>/dev/null`;

# Chomp all values first
chomp($ngtcp2Cflags) if(defined($ngtcp2Cflags));
chomp($ngtcp2Libs) if(defined($ngtcp2Libs));
chomp($ngtcp2CryptoCflags) if(defined($ngtcp2CryptoCflags));
chomp($ngtcp2CryptoLibs) if(defined($ngtcp2CryptoLibs));
chomp($nghttp3Cflags) if(defined($nghttp3Cflags));
chomp($nghttp3Libs) if(defined($nghttp3Libs));

# Check if we have the required libraries (must be defined and non-empty)
if(defined($ngtcp2Libs) && length($ngtcp2Libs) &&
   defined($nghttp3Libs) && length($nghttp3Libs)) {

    print "  Found ngtcp2: $ngtcp2Libs\n";
    print "  Found nghttp3: $nghttp3Libs\n";

    push @http3Incs, split(/\s+/, "$ngtcp2Cflags $ngtcp2CryptoCflags $nghttp3Cflags");
    push @http3Libs, split(/\s+/, "$ngtcp2Libs $ngtcp2CryptoLibs $nghttp3Libs");

    # Also need GnuTLS
    my $gnutlsCflags = `pkg-config --cflags gnutls 2>/dev/null`;
    my $gnutlsLibs = `pkg-config --libs gnutls 2>/dev/null`;
    chomp($gnutlsCflags) if(defined($gnutlsCflags));
    chomp($gnutlsLibs) if(defined($gnutlsLibs));

    if(defined($gnutlsLibs) && length($gnutlsLibs)) {
        push @http3Incs, split(/\s+/, $gnutlsCflags);
        push @http3Libs, split(/\s+/, $gnutlsLibs);
    }

    $http3Enabled = 1;
    print "HTTP/3 support enabled (using GnuTLS).\n";
} else {
    print "HTTP/3 libraries (ngtcp2/nghttp3) not found.\n";
    print "Install libngtcp2-dev and libnghttp3-dev to enable HTTP/3 support.\n";
}

# Remove duplicates from includes and libs
my %seenInc;
@http3Incs = grep { !$seenInc{$_}++ } @http3Incs;
my %seenLib;
@http3Libs = grep { !$seenLib{$_}++ } @http3Libs;

# Build parameters
my %mmParams = (
    NAME              => 'PageCamel::Framework',
    VERSION_FROM      => 'lib/PageCamel/Framework.pm',
    PREREQ_PM         => {
        'AHA' => 0.6, # AVM Home Automation (Fritz!Box)
        'AnyEvent' => 0,
        'Archive::Zip' => 0,
        'Array::Contains' => 3.1,
        'Carp' => 0,
        'CGI' => 0,
        'Config' => 0,
        'CPAN::Mini::Inject' => 0,
        'Crypt::Digest::SHA256' => 0,
        'Crypt::LE' => 0,
        'Crypt::OpenSSL::RSA' => 0.99,
        'CSS::Minifier::XS' => 0,
        'Data::Dumper' => 0,
        'Data::Entropy::Algorithms' => 0,
        'Data::Printer' => 0,
        'Date::Manip' => 0,
        'Date::Simple' => 0,
        'DBD::Pg' => 0,
        'DBI' => 0,
        'Device::SerialPort' => 0,
        'Digest' => 0,
        'Digest::Bcrypt' => 0,
        'Digest::MD5' => 0,
        'Digest::SHA1' => 0,
        'Email::MIME' => 0,
        'Email::Simple' => 0,
        'Encode' => 0,
        'English' => 0,
        'Errno' => 0,
        'Fatal' => 0,
        'Fcntl' => 0,
        'fields' => 0,
        'File::Basename' => 0,
        'File::Binary' => 0,
        'File::Copy' => 0,
        'FileHandle' => 0,
        'File::Spec' => 0,
        'File::stat' => 0,
        'File::Temp' => 0,
        'File::Type' => 0,
        'GD' => 0,
        'GD::Graph' => 0,
        'GD::Simple' => 0,
        'HTML::Entities' => 0,
        'HTML::TableExtract' => 0,
        'HTTP::BrowserDetect' => 0,
        'HTTP::Date' => 0,
        'Image::Imlib2' => 2.04,
        'Image::PNG::QRCode' => 0,
        'IO::Compress::Gzip' => 0,
        'IO::File' => 0,
        'IO::Handle' => 0,
        'IO::Socket' => 0,
        'IO::Socket::INET' => 0,
        'IO::Socket::INET6' => 0,
        'IO::Socket::IP' => 0,
        'IO::Pty::Easy' => 0,
        'JavaScript::Embedded' => '2.7.2',
        'JavaScript::Minifier' => 0,
        'JSON::RPC::Legacy::Client' => 0,
        'JSON::XS' => 0,
        'Lingua::EN::Numbers::Ordinate' => 0,
        'LWP' => 0,
        'LWP::Protocol::https' => 0,
        'Mail::Sendmail' => 0,
        'MD5' => 0,
        'MIME::Base64' => 0,
        'MIME::QuotedPrint' => 0,
        'Minecraft::NBTReader' => 0,
        'Minecraft::RCON' => 0,
        'Module::Load' => 0,
        'Module::Load::Conditional' => 0,
        'Net::Clacks::Client' => 35,
        'Net::CUPS2' => 0,
        'Net::DNS' => 0,
        'Net::DNS::Packet' => 0,
        'Net::DNS::Resolver' => 0,
        'Net::DNS::Resolver::Recurse' => 0,
        'Net::FTP' => 0,
        'Net::LibIDN' => 0,
        'Net::Ping' => 0,
        'Net::Ping::External' => 0,
        'Net::Server' => 0,
        'Net::SNMP' => 0,
        'Net::Syslogd' => 0,
        'Net::VNC' => 0,
        'Net::Whois::Parser' => 0,
        'Net::Whois::Raw' => 0,
        'Number::Bytes::Human' => 0,
        'PDF::Report' => 0,
        'Perl::Tidy' => 0,
        'Pg::hstore' => 0,
        'POSIX' => 0,
        'RADIUS::Dictionary' => 0,
        'RADIUS::Packet' => 0,
        'Readonly' => 0,
        'Scalar::Util' => 0,
        'Socket' => 0,
        'Socket6' => 0,
        'String::CRC32' => 0,
        'Sys::Hostname' => 0,
        'Sys::Load' => 0,
        'Sys::SigAction' => 0,
        'Template' => 0,
        'Template::Exception' => 0,
        'Template::Plugin' => 0,
        'Text::Aspell' => 0,
        'Time::HiRes' => 0,
        'Time::localtime' => 0,
        'URI' => 0,
        'URI::Encode' => 0,
        'URI::_punycode' => 0,
        'vars' => 0,
        'WWW::Mechanize' => 0,
        'WWW::Mechanize::GZip' => 0,
        'XML::RPC' => 2.1,
        'XML::Simple' => 0,
        'YAML::Syck' => 0,
        "forks" => 0,
    },
    ABSTRACT_FROM     => 'lib/PageCamel/Framework.pm',
    AUTHOR            => 'Rene Schickbauer <pagecamel@cavac.at>',
    LICENSE           => 'artistic_2',
    MIN_PERL_VERSION  => '5.038',
    PM                => \%pm,  # Explicit PM hash excluding nested blib directories
);

# Add XS compilation if HTTP/3 is enabled
if($http3Enabled) {
    # Point to unified HTTP/3 module directory
    $mmParams{DIR} = ['lib/PageCamel/Protocol/HTTP3'];

    # Write the HTTP/3 configuration for the HTTP3 subdirectory
    open my $fh, '>', 'lib/PageCamel/Protocol/HTTP3/http3_config.pl' or die "Cannot write http3_config.pl: $!";
    print $fh "# Auto-generated HTTP/3 configuration\n";
    print $fh "our \$HTTP3_ENABLED = 1;\n";
    print $fh "our \@HTTP3_INCS = qw(" . join(' ', @http3Incs) . ");\n";
    print $fh "our \@HTTP3_LIBS = qw(" . join(' ', @http3Libs) . ");\n";
    print $fh "1;\n";
    close $fh;
    print "Wrote HTTP/3 configuration to lib/PageCamel/Protocol/HTTP3/http3_config.pl\n";
}

# Custom targets - must be defined before WriteMakefile()
sub MY::postamble {
    return <<'MAKE_FRAG';

# Clean up nested blib directories that can cause build issues
clean ::
	-rm -rf lib/PageCamel/blib lib/PageCamel/Protocol/HTTP3/blib

# HTTP/3 specific targets
http3-check:
	@echo "Checking HTTP/3 library availability..."
	@pkg-config --exists libngtcp2 && echo "ngtcp2: found" || echo "ngtcp2: NOT FOUND"
	@pkg-config --exists libnghttp3 && echo "nghttp3: found" || echo "nghttp3: NOT FOUND"
	@pkg-config --exists openssl && echo "openssl: found" || echo "openssl: NOT FOUND"

http3-info:
	@echo "HTTP/3 Build Information:"
	@echo "========================="
	@if [ -f lib/PageCamel/Protocol/HTTP3/http3_config.pl ]; then \
		echo "HTTP/3 support: ENABLED"; \
		cat lib/PageCamel/Protocol/HTTP3/http3_config.pl; \
	else \
		echo "HTTP/3 support: DISABLED"; \
		echo "Install libngtcp2-dev and libnghttp3-dev to enable."; \
	fi

MAKE_FRAG
}

WriteMakefile(%mmParams);
