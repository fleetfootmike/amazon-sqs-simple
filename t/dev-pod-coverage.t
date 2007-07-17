#!perl -T

use Test::More tests => 3;
eval "use Test::Pod::Coverage 1.04";
plan skip_all => "Test::Pod::Coverage 1.04 required for testing POD coverage" if $@;

# ignore subs starting with an underscore
my $trustme = { trustme => [ qr/^_/ ] };
pod_coverage_ok('Amazon::SQS::Simple', $trustme);
pod_coverage_ok('Amazon::SQS::Simple::Message', {trustme => [ qr/^new$/ ]});
pod_coverage_ok('Amazon::SQS::Simple::Queue', $trustme);
