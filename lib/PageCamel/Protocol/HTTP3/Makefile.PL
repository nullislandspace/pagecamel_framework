use ExtUtils::MakeMaker;
use Config;

# Load HTTP/3 configuration from parent Makefile.PL
our ($HTTP3_ENABLED, @HTTP3_INCS, @HTTP3_LIBS);
my $config_file = './http3_config.pl';
if (-f $config_file) {
    do $config_file or die "Cannot load $config_file: $@";
} else {
    warn "HTTP/3 configuration file not found.\n";
    warn "Creating stub Makefile (HTTP/3 module will not be built).\n";

    # Create a stub Makefile that does nothing
    WriteMakefile(
        NAME     => 'PageCamel::Protocol::HTTP3',
        SKIP     => [qw(all static dynamic test)],
        clean    => { FILES => '' },
    );
    exit 0;
}

unless ($HTTP3_ENABLED) {
    warn "HTTP/3 is not enabled. Creating stub Makefile.\n";
    WriteMakefile(
        NAME     => 'PageCamel::Protocol::HTTP3',
        SKIP     => [qw(all static dynamic test)],
        clean    => { FILES => '' },
    );
    exit 0;
}

# Build include and library paths
my $inc = join(' ', @HTTP3_INCS);
my $libs = join(' ', @HTTP3_LIBS);

print "Building PageCamel::Protocol::HTTP3 unified module\n";
print "  Include flags: $inc\n";
print "  Library flags: $libs\n";

# Point to parent's blib directory (from lib/PageCamel/Protocol/HTTP3 -> project root)
my $parent_blib = '../../../..';

# List of C source files to compile
my @c_sources = qw(
    src/h3_buffer.c
    src/h3_tls.c
    src/h3_callbacks.c
    src/h3_connection.c
    src/h3_packet.c
    src/h3_api.c
);

# Build object list
my @objects = map { my $o = $_; $o =~ s/\.c$/\$(OBJ_EXT)/; $o } @c_sources;
push @objects, 'HTTP3$(OBJ_EXT)';  # XS-generated object

# Custom postamble for building C library objects
sub MY::postamble {
    my $inc_escaped = $inc;

    my $rules = '';

    # Add compile rules for each C source file
    for my $src (@c_sources) {
        (my $obj = $src) =~ s/\.c$/\$(OBJ_EXT)/;
        $rules .= <<"MAKE_FRAG";

$obj: $src src/h3_api.h src/h3_internal.h src/h3_buffer.h src/h3_tls.h src/h3_packet.h
	\$(CCCMD) \$(CCCDLFLAGS) "-I\$(PERL_INC)" \$(PASTHRU_DEFINE) \$(DEFINE) \\
		-Isrc $inc_escaped \\
		-c $src -o $obj

MAKE_FRAG
    }

    return $rules;
}

WriteMakefile(
    NAME              => 'PageCamel::Protocol::HTTP3',
    VERSION_FROM      => 'HTTP3.pm',
    ABSTRACT          => 'Unified HTTP/3 library with ngtcp2/nghttp3 C-to-C wiring',
    AUTHOR            => 'PageCamel Framework',
    LICENSE           => 'mit',
    MIN_PERL_VERSION  => '5.038',
    PREREQ_PM         => {},
    LIBS              => [$libs],
    INC               => "-I. -Isrc $inc",
    TYPEMAPS          => ['typemap'],
    XS                => {
        'HTTP3.xs' => 'HTTP3.c',
    },
    OBJECT            => join(' ', @objects),
    CCFLAGS           => "$Config{ccflags} -std=c11",
    clean             => { FILES => 'HTTP3.c src/*.o *.o *.bs' },
    # Install to parent's blib
    INST_LIB          => "$parent_blib/blib/lib",
    INST_ARCHLIB      => "$parent_blib/blib/arch",
);
