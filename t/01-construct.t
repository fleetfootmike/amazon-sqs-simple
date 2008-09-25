#!perl -T

use Test::More tests => 4;
use Amazon::SQS::Simple;

eval {
    my $obj = new Amazon::SQS::Simple();
};

ok($@, "should get a constructor exception when no AWS keys exist");
my $error = $@;
chomp($error);
like($error,
     qr/missing.*aws.*key/i,
     "should have a good error message (got: \"$error\")");

eval {
    my $obj = new Amazon::SQS::Simple('fake access', 'fake secret',
                                      Version => "bogus version");
};

ok($@, "should get a constructor exception when a bad version is specified");
$error = $@;
chomp($error);
like($error,
     qr/invalid.*version.* valid.*are/i,
     "should have a good error message (got: \"$error\")");

