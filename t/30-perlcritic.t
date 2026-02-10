use strict;
use warnings;
use File::Spec;
use File::Find;
use Test::More;

eval "use Test::Pod::Coverage 1.04";
plan skip_all => "Test::Pod::Coverage 1.04 required for testing POD coverage" if $@;

use Data::Dumper;
use English qw(-no_match_vars);

if ( not $ENV{TEST_CRITIC} ) {
    my $msg = 'Perl::Critic test.  Set $ENV{TEST_CRITIC} to a true value to run.';
    plan( skip_all => $msg );
}

eval { require Test::Perl::Critic; };

if ( $EVAL_ERROR ) {
   my $msg = 'Test::Perl::Critic required to criticise code';
   plan( skip_all => $msg );
}

my @fnames;
find(sub {
    return if !-f $_;
    return if $_ !~ /\.pm$/;
    my $fname = $File::Find::name;
    return if($fname =~ /Net\/Server/);
    return if($fname =~ /LetsEncrypt/);
    return if($fname =~ /WSockFrame/);
    return if($fname =~ /\/blib\//);
    push @fnames, $fname;
}, 'lib/');

plan(tests => scalar @fnames);

my $rcfile = File::Spec->catfile( 't', 'perlcriticrc' );
Test::Perl::Critic->import( -profile => $rcfile, -verbose => "[%p] %m at line %l, column %c.  (Severity: %s)\n   %e\n");
foreach my $fname (sort @fnames) {
    #diag "** $fname";
    critic_ok($fname);
}
