use strict;
use warnings;
use Test::More;

BEGIN {
    plan skip_all => 'Author tests. Set TEST_HTTP2=1 to run.' unless $ENV{TEST_HTTP2};
}

BEGIN {
    use_ok( 'PageCamel::Protocol::HTTP2::Trace', qw(tracer bin2hex) );
}

subtest 'bin2hex' => sub {
    is bin2hex("ABCDEFGHIJKLMNOPQR"),
      "4142 4344 4546 4748 494a 4b4c 4d4e 4f50\n5152 ";
};

done_testing;

