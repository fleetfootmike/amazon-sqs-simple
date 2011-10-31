#!perl -T

use strict;
use warnings;
use Test::More tests => 34;
use Digest::MD5 qw(md5_hex);

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

my $lists = $sqs->ListQueues();
my $iteration = 1;
while (!defined($lists) && $iteration < 4) {
    sleep 2;
    $lists = $sqs->ListQueues();
    $iteration++;
}
ok((grep { $_->Endpoint() eq $q->Endpoint() } @$lists), 'ListQueues returns the queue we just created');

my $url = $sqs->GetQueueUrl($queue_name);
ok (($url =~ m{^$q->{Endpoint}$}), 'GetQueueUrl returns the stored Endpoint');

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
    ok($response->MD5OfMessageBody eq md5_hex($msg), 'Got back correct MD5 checksum for message')
        or diag("Looking for " . md5_hex($msg) . ", got " . $response->MD5OfMessageBody);
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

my $alt_sqs = new Amazon::SQS::Simple('AKIAJU363N3TSON4J23A','6vO9pOmw4L4v4WrDfJQWlEdJkaadojD6ArHEvkCX');
my $alt_q   = $alt_sqs->GetQueue($q->Endpoint);
eval { my $alt_msg = $alt_q->ReceiveMessage };
ok($@, "Attempting to pop queue from different user fails");

my $alt_aws_account_num = '306667659257'; # account number for simonwhitaker@me.com account
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

#################################################
#### Deleting messages

eval { $q->DeleteMessage($received_msg->ReceiptHandle); };
ok(!$@, 'DeleteMessage on ReceiptHandle of received message') or diag($@);

#################################################
#### Deleting a queue

eval { $q->Delete(); };
ok(!$@, 'Delete on non-empty queue') or diag($@);
