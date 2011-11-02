#!perl -T

use strict;
use warnings;
use Test::More tests => 47;
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
my $msg_retain  = 456;
my ($href, $response);

#################################################
#### Creating, retrieving and listing queues

my $orig_lists = $sqs->ListQueues();
my $orig_count = 0;
   $orig_count = scalar @$orig_lists if defined $orig_lists;

my $q = $sqs->CreateQueue($queue_name, VisibilityTimeout => $timeout, MessageRetentionPeriod => $msg_retain);

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

my $url = $sqs->GetQueueUrl($queue_name);
ok (($url =~ m{^$q->{Endpoint}$}), 'GetQueueUrl returns the stored Endpoint');

#################################################
#### Setting and getting list attributes

$href = $q->GetAttributes();
ok(($href->{VisibilityTimeout} == $timeout and $href->{MessageRetentionPeriod} == $msg_retain), 'CreateQueue set multiple attributes');
$href = undef;

$timeout++;
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

# test delayed messages first, because it is convenient to have an empty queue
my $delay = 60;
$response = $q->SendMessage($messages{GET}, DelaySeconds => $delay);
ok($response->MessageId, 'Got MessageId when sending delayed message');
sleep int($delay / 2);
my $received_msg = $q->ReceiveMessage();
ok(!defined($received_msg), 'Delayed message should be unavailable halfway through the delay period');
sleep int($delay / 2) + 15;
$received_msg = $q->ReceiveMessage();
ok((defined $received_msg and $received_msg->MessageBody eq $messages{GET}), 'Delayed message became available after the delay period');

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

$received_msg = $q->ReceiveMessage(Attributes => 'All');
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
ok(($received_msg->SenderId =~ m{^[\d\.]+$}), 'ReceiveMessage returned attributes');

for (1..10) {
    $q->SendMessage($_);
}

my @messages = $q->ReceiveMessage(MaxNumberOfMessages => 10);

ok(UNIVERSAL::isa($messages[0], 'Amazon::SQS::Simple::Message')
 , 'Calling ReceiveMessage with MaxNumberOfMessages returns array of Amazon::SQS::Simple::Message objects');

my @list = qw(one two three);
my %list = map { $_ => 1 } @list;
$response = $q->SendMessage(\@list);
ok($response->is_success(), 'Batch SendMessage is successful');
ok($response->is_batch(), 'SendResponse is_batch method returns true for a batch request');

my $received_multi;
$iteration++;
while (!defined($received_multi) && $iteration < 4) {
    sleep 2;
    $received_multi = $q->ReceiveMessage();
    $iteration++;
}
while (defined $received_multi) {
    my $body = $received_multi->MessageBody;
    delete $list{$body} if exists $list{$body};
    last unless %list;
} continue {
    $received_multi = $q->ReceiveMessage();
}
ok(!(scalar keys %list), 'All messages from batch SendMessage were received');

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
#### Batch operations on ReceiptHandles

my $batch_size = 3;
my @batch_handles;
for (1 .. $batch_size) {
    sleep 2;
    my $msg = eval { $q->ReceiveMessage() };
    redo unless defined $msg;
    push @batch_handles, $msg->ReceiptHandle();
}

eval { $response = $q->ChangeMessageVisibility(\@batch_handles, 10) };
ok(scalar @{$response->{ChangeMessageVisibilityBatchResult}{ChangeMessageVisibilityBatchResultEntry}} == $batch_size, 'All messages from batch ChangeMessageVisibility were updated');

# todo, check the individual visibility values
eval { $response = $q->ChangeMessageVisibility([ [ $batch_handles[0], 10 ], [ $batch_handles[1], 20 ] ], 30) };
ok(scalar @{$response->{ChangeMessageVisibilityBatchResult}{ChangeMessageVisibilityBatchResultEntry}} == 2, 'Alternate invocation form for batch ChangeMessageVisibility');

# todo, this test works, but hide carp output
# push @batch_handles, "nonexistent_handle";
# eval { $response = $q->ChangeMessageVisibility(\@batch_handles, 30) };
# ok((scalar @{$response->{ChangeMessageVisibilityBatchResult}{ChangeMessageVisibilityBatchResultEntry}} == $batch_size and
#     scalar @{$response->{ChangeMessageVisibilityBatchResult}{BatchResultErrorEntry}} == 1),
#    'Error caught correctly on batch ChangeMessageVisibility');
# pop @batch_handles;

eval { $response = $q->DeleteMessage(\@batch_handles) };
ok(scalar @{$response->{DeleteMessageBatchResult}{DeleteMessageBatchResultEntry}} == $batch_size, 'All messages from batch DeleteMessage were removed');

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
