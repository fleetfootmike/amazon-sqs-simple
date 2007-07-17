#!perl -T

use strict;
use warnings;
use Test::More tests => 18;

BEGIN {
    use_ok('Amazon::SQS::Simple');
}

my $sqs = new Amazon::SQS::Simple($ENV{AWS_ACCESS_KEY}, $ENV{AWS_SECRET_KEY});

isa_ok($sqs, 'Amazon::SQS::Simple', "[$$] Amazon::SQS::Simple object created successfully");

my $queue_name = "_test_queue_$$";
my $msg_small  = "Some random message"; # small message, will be sent using GET
my $msg_large  = "x" x (1024*16);       # 16K message, will be sent using POST

my $q = $sqs->CreateQueue($queue_name);
ok(
    $q 
 && $q->Endpoint()
 && $q->Endpoint() =~ /$queue_name$/
 , "CreateQueue returned a queue (name was $queue_name)"
);

my $q2 = $sqs->GetQueue($q->Endpoint());

is_deeply($q, $q2, 'GetQueue returns the queue we just created');

my $lists = $sqs->ListQueues();
ok(
    (grep { $_->Endpoint() eq $q->Endpoint() } @$lists)
    , 'ListQueues returns the queue we just created'
);

my $timeout = 123;

eval {
    $q->SetAttribute('VisibilityTimeout', $timeout);
};
ok(!$@, 'SetAttribute');

my $href;

# Have a few at GetAttributes, sometimes takes a while for SetAttributes
# method to be processed
my $i = 0;
do {
    sleep 2 if $i++;
    $href = $q->GetAttributes();
} while ($href->{VisibilityTimeout} != $timeout && $i < 5);

ok(
    $href->{VisibilityTimeout} == $timeout
    , "GetAttributes"
) or diag("Failed after $i attempts, sent $timeout, got back $href->{VisibilityTimeout}");

my $msg_id = $q->SendMessage($msg_small);
ok ($msg_id, 'SendMessage (small message)');

my $msg = $q->PeekMessage($msg_id);
ok(
    UNIVERSAL::isa($msg, 'Amazon::SQS::Simple::Message')
    , 'PeekMessage returns Amazon::SQS::Simple::Message object'
);
ok(
    $msg->MessageBody() eq $msg_small
    && $msg->MessageId() eq $msg_id
    , 'PeekMessage got right message back'
);

$msg_id = $q->SendMessage($msg_large);
ok ($msg_id, 'SendMessage (large message)');

$msg = $q->PeekMessage($msg_id);
ok(
    $msg->MessageBody() eq $msg_large
    && $msg->MessageId() eq $msg_id
    , 'PeekMessage got right message back'
);

eval {
    $q->ChangeMessageVisibility($msg_id, 321);
};
ok(!$@, 'ChangeMessageVisibility');

eval {
    $q->DeleteMessage($msg_id);
};
ok(!$@, 'DeleteMessage');

$msg = $q->ReceiveMessage();
ok(
    UNIVERSAL::isa($msg, 'Amazon::SQS::Simple::Message')
    , 'ReceiveMessage returns Amazon::SQS::Simple::Message object'
);
ok(
    $msg->MessageBody() eq $msg_small
    , 'ReceiveMessage returned one of the messages we wrote'
);

eval {
    $q->Delete();
};
ok($@, 'Delete on non-empty queue throws error');

eval {
    $q->Delete(1);
};
ok(!$@, 'Delete (force = true) on non-empty queue succeeds');

