use strict;
use Test::More;

plan skip_all => 'Author tests. Set TEST_HTTP2=1 to run.' unless $ENV{TEST_HTTP2};

use_ok $_ for qw(
  PageCamel::Protocol::HTTP2
);

done_testing;

