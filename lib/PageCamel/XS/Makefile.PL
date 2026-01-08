use v5.38;
use ExtUtils::MakeMaker;
use Config;

# Load HTTP/3 configuration from parent Makefile.PL
our ($HTTP3_ENABLED, @HTTP3_INCS, @HTTP3_LIBS);
my $config_file = './http3_config.pl';
if (-f $config_file) {
    do $config_file or die "Cannot load $config_file: $@";
} else {
    warn "HTTP/3 configuration file not found.\n";
    warn "Creating stub Makefile (HTTP/3 XS modules will not be built).\n";

    # Create a stub Makefile that does nothing
    WriteMakefile(
        NAME     => 'PageCamel::XS',
        SKIP     => [qw(all static dynamic test)],
        clean    => { FILES => '' },
    );
    exit 0;
}

unless ($HTTP3_ENABLED) {
    warn "HTTP/3 is not enabled. Creating stub Makefile.\n";
    WriteMakefile(
        NAME     => 'PageCamel::XS',
        SKIP     => [qw(all static dynamic test)],
        clean    => { FILES => '' },
    );
    exit 0;
}

# Build include and library paths
my $inc = join(' ', @HTTP3_INCS);
my $libs = join(' ', @HTTP3_LIBS);

print "Building PageCamel::XS QUIC/HTTP3 modules\n";
print "  Include flags: $inc\n";
print "  Library flags: $libs\n";

# For multiple XS files, we need XSMULTI or separate builds
# Using the standard approach with multiple XS files

# Point to parent's blib directory (from lib/PageCamel/XS -> project root)
my $parent_blib = '../../..';

WriteMakefile(
    NAME              => 'PageCamel::XS::NGTCP2',
    VERSION_FROM      => 'NGTCP2.pm',
    ABSTRACT          => 'XS bindings for ngtcp2 QUIC library',
    AUTHOR            => 'PageCamel Framework',
    LICENSE           => 'mit',
    MIN_PERL_VERSION  => '5.038',
    PREREQ_PM         => {},
    LIBS              => [$libs],
    INC               => "-I. $inc",
    TYPEMAPS          => ['typemap'],
    XS                => {
        'NGTCP2.xs' => 'NGTCP2.c',
    },
    OBJECT            => 'NGTCP2$(OBJ_EXT)',
    CCFLAGS           => "$Config{ccflags}",
    clean             => { FILES => 'NGTCP2.c NGTCP2$(OBJ_EXT) *.bs' },
    # Install to parent's blib
    INST_LIB          => "$parent_blib/blib/lib",
    INST_ARCHLIB      => "$parent_blib/blib/arch",
);

# Custom postamble to build NGHTTP3 module separately
sub MY::postamble {
    my $libs_escaped = $libs;
    my $inc_escaped = $inc;

    return <<"MAKE_FRAG";

# NGHTTP3 module
NGHTTP3_XS = NGHTTP3.xs
NGHTTP3_C = NGHTTP3.c
NGHTTP3_O = NGHTTP3\$(OBJ_EXT)
NGHTTP3_INST_DIR = ../../../blib/arch/auto/PageCamel/XS/NGHTTP3

all :: pm_to_blib \$(INST_DYNAMIC) nghttp3_module

nghttp3_module: \$(NGHTTP3_O)
	\@\$(MKPATH) \$(NGHTTP3_INST_DIR)
	\$(LD) -o \$(NGHTTP3_INST_DIR)/NGHTTP3.\$(DLEXT) \\
		\$(LDDLFLAGS) \$(NGHTTP3_O) \\
		$libs_escaped \\
		\$(PERL_ARCHIVE) \$(LDLOADLIBS) \$(EXPORT_LIST)
	\$(CHMOD) \$(PERM_RWX) \$(NGHTTP3_INST_DIR)/NGHTTP3.\$(DLEXT)

\$(NGHTTP3_C): \$(NGHTTP3_XS) typemap
	\$(XSUBPPRUN) \$(XSPROTOARG) \$(XSUBPPARGS) \$(XSUBPP_EXTRA_ARGS) \\
		\$(NGHTTP3_XS) > \$(NGHTTP3_C)

\$(NGHTTP3_O): \$(NGHTTP3_C)
	\$(CCCMD) \$(CCCDLFLAGS) "-I\$(PERL_INC)" \$(PASTHRU_DEFINE) \$(DEFINE) \\
		$inc_escaped \\
		\$(NGHTTP3_C)

clean ::
	-\$(RM_F) \$(NGHTTP3_C) \$(NGHTTP3_O)
	-\$(RM_RF) \$(NGHTTP3_INST_DIR)

MAKE_FRAG
}

# Also need to install NGHTTP3.pm
sub MY::install {
    my $inherited = shift->SUPER::install(@_);

    # Add NGHTTP3 installation
    $inherited .= <<'INSTALL_FRAG';

# Install NGHTTP3 module files
install :: install_nghttp3

install_nghttp3:
	$(NOECHO) $(MKPATH) $(DESTINSTALLPRIVLIB)/PageCamel/XS/NGHTTP3
	$(NOECHO) $(CP) NGHTTP3.pm $(DESTINSTALLPRIVLIB)/PageCamel/XS/
	$(NOECHO) $(CP) NGHTTP3/*.pm $(DESTINSTALLPRIVLIB)/PageCamel/XS/NGHTTP3/

INSTALL_FRAG

    return $inherited;
}
