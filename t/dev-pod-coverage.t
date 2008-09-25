#!perl -T

use Test::More;
eval "use Test::Pod::Coverage 1.04";
if ($@) {
    plan skip_all => "Test::Pod::Coverage 1.04 required for testing POD coverage";
}
else {
    plan tests => 4;
}

# ignore subs starting with an underscore
my $trustme = { trustme => [ qr/^_/ ] };
pod_coverage_ok('Amazon::SQS::Simple', $trustme);
pod_coverage_ok('Amazon::SQS::Simple::Message', {trustme => [ qr/^new$/ ]});
pod_coverage_ok('Amazon::SQS::Simple::Queue', $trustme);
pod_coverage_ok('Amazon::SQS::Simple::SendResponse', {trustme => [ qr/^new$/ ]});
