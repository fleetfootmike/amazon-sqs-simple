#!perl -T

use strict;
use warnings;
use Test::More tests => 42;
use Digest::MD5 qw(md5_hex);
use Encode;

BEGIN { use_ok('Amazon::SQS::Simple'); }

#################################################
#### Creating an Amazon::SQS::Simple object

my $sqs = new Amazon::SQS::Simple(
    $ENV{AWS_ACCESS_KEY}, 
    $ENV{AWS_SECRET_KEY},
    Timeout => 20,
    # _Debug => \*STDERR,
);

eval {
    my $str = "$sqs";
};
ok(!$@, "Interpolating Amazon::SQS::Simple object in string context");

ok($sqs->_api_version eq $Amazon::SQS::Simple::Base::DEFAULT_SQS_VERSION,
    "Constructor should default to the default API version");

isa_ok($sqs, 'Amazon::SQS::Simple', "[$$] Amazon::SQS::Simple object created successfully");

my $queue_name  = "_test_queue_$$";

my %messages    = (
    GET  => "x " x 8,
    POST => "x " x (1024 * 4),
);

my $timeout     = 123;
my ($href, $response);

#################################################
#### Creating, retrieving and listing queues

my $orig_lists = $sqs->ListQueues();
my $orig_count = 0;
   $orig_count = scalar @$orig_lists if defined $orig_lists;

my $q = $sqs->CreateQueue($queue_name);
ok(
    $q 
 && $q->Endpoint()
 && $q->Endpoint() =~ /$queue_name$/
 , "CreateQueue returned a queue (name was $queue_name)"
);

eval {
    my $str = "$q";
};
ok(!$@, "Interpolating Amazon::SQS::Simple::Queue object in string context");

my $q2 = $sqs->GetQueue($q->Endpoint());

is_deeply($q, $q2, 'GetQueue returns the queue we just created');

sleep 5;
my $lists = $sqs->ListQueues();
my $iteration = 1;
while ((!defined($lists) or (scalar @$lists == $orig_count)) && $iteration < 60) {
    sleep 2;
    $lists = $sqs->ListQueues();
    $iteration++;
}
ok((grep { $_->Endpoint() eq $q->Endpoint() } @$lists), 'ListQueues returns the queue we just created');

#################################################
#### Setting and getting list attributes

eval {
    $q->SetAttribute('VisibilityTimeout', $timeout);
};
ok(!$@, 'SetAttribute');

# Have a few goes at GetAttributes, sometimes takes a while for SetAttributes
# method to be processed
$iteration = 0;
do {
    sleep 10 if $iteration++;
    $href = $q->GetAttributes();
} while ((!$href->{VisibilityTimeout} || $href->{VisibilityTimeout} != $timeout) && $iteration < 4);

ok(
    $href->{VisibilityTimeout} && $href->{VisibilityTimeout} == $timeout
    , "GetAttributes"
) or diag("Failed after $iteration attempts, sent $timeout, got back " . ($href->{VisibilityTimeout} ? $href->{VisibilityTimeout} : 'undef'));


#################################################
#### Sending and receiving messages

$response = $q->ReceiveMessage();
ok(!defined($response), 'ReceiveMessage called on empty queue returns undef');

foreach my $msg_type (keys %messages) {
    my $msg = $messages{$msg_type};
    $response = $q->SendMessage($msg);
    ok(UNIVERSAL::isa($response, 'Amazon::SQS::Simple::SendResponse'), "SendMessage returns Amazon::SQS::Simple::SendResponse object ($msg_type)");
    
    eval {
        my $str = "$response";
    };
    ok(!$@, "Interpolating Amazon::SQS::Simple::SendResponse object in string context");
    
    ok($response->MessageId, 'Got MessageId when sending message');
    ok($response->MD5OfMessageBody eq md5_hex(Encode::encode_utf8($msg)), 'Got back correct MD5 checksum for message')
        or diag("Looking for " . md5_hex(Encode::encode_utf8($msg)) . ", got " . $response->MD5OfMessageBody);
}

my $received_msg = $q->ReceiveMessage();
$iteration = 1;

while (!defined($received_msg) && $iteration < 4) {
    sleep 2;
    $received_msg = $q->ReceiveMessage();
    $iteration++;
}

eval {
    my $str = "$received_msg";
};
ok(!$@, "Interpolating Amazon::SQS::Simple::Message object in string context");

ok(UNIVERSAL::isa($received_msg, 'Amazon::SQS::Simple::Message'), 'ReceiveMessage returns Amazon::SQS::Simple::Message object');
ok((grep {$_ eq $received_msg->MessageBody} values %messages), 'ReceiveMessage returned one of the messages we wrote');

foreach my $international (
                           # may fail if "use encoding 'utf8'" or other trickery is in effect
                           Encode::decode("iso-8859-1",  "L\xE1szl\xF3 S\xF3lyom"),

                           # certain to work
                           Encode::decode("iso-8859-1",  pack "C*", qw/76 225 115 122 108 243 32 83 243 108 121 111 109/),

                           # utf8 data which is not marked as such is tricky
                           Encode::decode('utf8',        "L\xC3\xA1szl\xC3\xB3 S\xC3\xB3lyom"),

                           Encode::decode("iso-8859-15", "\xBCUF"),
                          ) {
    my $response = eval {$q->SendMessage($international)};
    ok(!$@ && UNIVERSAL::isa($response, 'Amazon::SQS::Simple::SendResponse'), "SendMessage works with UTF-8 messages");
}

SKIP: {
    skip '\N{U+xxxx} escapes require Perl 5.12 or above', 2 unless $] >= 5.012;
    foreach my $international (
                               "I\N{U+00f1}t\N{U+00eb}rn\N{U+00e2}ti\N{U+00f4}n\N{U+00e0}liz\N{U+00e6}ti\N{U+00f8}n",
                               "\N{U+01cf}\N{U+00f1}\N{U+04ad}\N{U+00eb}\N{U+0550}\N{U+014b}\N{U+00e2}\N{U+0165}\N{U+1e2f}\N{U+1e4f}\N{U+1e4b}\N{U+03b1}\N{U+0142}\N{U+0457}\N{U+017c}\N{U+00e6}\N{U+0167}\N{U+00ed}\N{U+00f8}\N{U+1e45}",
                              ) {
        my $response = eval {$q->SendMessage($international)};
        ok(!$@ && UNIVERSAL::isa($response, 'Amazon::SQS::Simple::SendResponse'), "SendMessage works with UTF-8 messages");
    }
};

TODO: {
    local $TODO = "characters outside the Basic Multilingual Plane fail, contrary to Amazon docs";
    foreach my $international (
                               "emoji         |\N{U+1f320}|",      # shooting star
                               "cjk ideograph |\N{U+22222}|",
                              ) {
        my $response = eval {$q->SendMessage($international)};
        ok(!$@ && UNIVERSAL::isa($response, 'Amazon::SQS::Simple::SendResponse'), "SendMessage works with UTF8 messages outside the BMP");
    }
};

for (1..10) {
    $q->SendMessage($_);
}

my @messages = $q->ReceiveMessage(MaxNumberOfMessages => 10);

ok(UNIVERSAL::isa($messages[0], 'Amazon::SQS::Simple::Message')
 , 'Calling ReceiveMessage with MaxNumberOfMessages returns array of Amazon::SQS::Simple::Message objects');

#################################################
#### Changing message visibility

eval { $q->ChangeMessageVisibility($received_msg->ReceiptHandle, 120); };
ok(!$@, 'ChangeMessageVisibility on ReceiptHandle of received message') or diag($@);

eval { $q->ChangeMessageVisibility($received_msg->ReceiptHandle); };
ok($@, 'ChangeMessageVisibility with no timeout is fatal');

#################################################
#### Adding and removing permissions

SKIP: {

    # these environment variables may hold information about a separate account through which to test permissions
    skip "ALT_AWS_ACCESS_KEY environment variable is not defined",  6 unless exists $ENV{ALT_AWS_ACCESS_KEY};
    skip "ALT_AWS_SECRET_KEY environment variable is not defined",  6 unless exists $ENV{ALT_AWS_SECRET_KEY};
    skip "ALT_AWS_ACCOUNT_NUM environment variable is not defined", 6 unless exists $ENV{ALT_AWS_ACCOUNT_NUM};

    my $alt_sqs = new Amazon::SQS::Simple($ENV{ALT_AWS_ACCESS_KEY}, $ENV{ALT_AWS_SECRET_KEY});
    my $alt_q   = $alt_sqs->GetQueue($q->Endpoint);
    eval { my $alt_msg = $alt_q->ReceiveMessage };
    ok($@, "Attempting to pop queue from different user fails");

    my $alt_aws_account_num = $ENV{ALT_AWS_ACCOUNT_NUM}; # this number can be found in the endpoint
    eval { $q->AddPermission('SimonTest', {$alt_aws_account_num => 'ReceiveMessage'})};
    ok(!$@, "AddPermission for account $alt_aws_account_num") or diag($@);

    # wait until we've seen the policy appear in the queue attributes twice in a row
    my $policy_applied = 0;
    my $tries = 0;
    while ($policy_applied < 2 && $tries < 10) {
        my $attr = $q->GetAttributes;
        if (exists $attr->{Policy}) { $policy_applied++ } else { $policy_applied = 0 }
        sleep(5) if $policy_applied < 2 && $tries < 10;
    }

    eval { my $alt_msg = $alt_q->ReceiveMessage };
    ok(!$@, "Attempting to pop queue from user with ReceiveMessage permissions succeeds") or diag($@);

    eval { $q->AddPermission('SimonTest2', {$alt_aws_account_num => 'FooBar'})};
    ok($@, "AddPermission for account $alt_aws_account_num with bad ActionName is fatal");

    eval { $q->RemovePermission('SimonTest')};
    ok(!$@, "RemovePermission for account $alt_aws_account_num") or diag($@);

    my $policy_removed = 0;
    $tries = 0;
    while ($policy_removed < 2 && $tries < 10) {
        my $attr = $q->GetAttributes;
        if ($attr->{Policy} && $attr->{Policy} !~ /$alt_aws_account_num/) { 
            $policy_removed++;
        } else { 
            $policy_removed = 0;
        }
        sleep(5) if $policy_removed < 2 && $tries < 10;
    }

    eval { my $alt_msg = $alt_q->ReceiveMessage };
    ok($@, "Attempting to pop queue from different user once permissions revoked fails");

}

#################################################
#### Deleting messages

eval { $q->DeleteMessage($received_msg->ReceiptHandle); };
ok(!$@, 'DeleteMessage on ReceiptHandle of received message') or diag($@);

#################################################
#### Deleting a queue

eval { $q->Delete(); };
ok(!$@, 'Delete on non-empty queue') or diag($@);

#################################################
#### Version 1 signatures

$sqs = new Amazon::SQS::Simple(
    $ENV{AWS_ACCESS_KEY},
    $ENV{AWS_SECRET_KEY},
    Timeout => 20,
    SignatureVersion => 1,
    # _Debug => \*STDERR,
);

isa_ok($sqs, 'Amazon::SQS::Simple', "[$$] Amazon::SQS::Simple object created successfully with SignatureVersion 1");

$queue_name  = "_test_queue_v1_$$";

$q = $sqs->CreateQueue($queue_name);
ok(
    $q
 && $q->Endpoint()
 && $q->Endpoint() =~ m{/$queue_name$}
 , "CreateQueue returned a queue with SignatureVersion 1 (name was $queue_name)"
);
