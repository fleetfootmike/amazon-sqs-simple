#!perl -T

use strict;
use warnings;
use Test::More tests => 23;
use Digest::MD5 qw(md5_hex);

BEGIN { use_ok('Amazon::SQS::Simple'); }

my $sqs = new Amazon::SQS::Simple(
    $ENV{AWS_ACCESS_KEY}, 
    $ENV{AWS_SECRET_KEY},
    # _Debug => \*STDERR,
);

eval {
    my $str = "$sqs";
};
ok(!$@, "Interpolating Amazon::SQS::Simple object in string context");

isa_ok($sqs, 'Amazon::SQS::Simple', "[$$] Amazon::SQS::Simple object created successfully");

my $queue_name  = "_test_queue_$$";

my %messages    = (
    GET  => "x " x 8,
    POST => "x " x (1024 * 4),
);

my $timeout     = 123;
my ($href, $response);

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

eval {
    $q->SetAttribute('VisibilityTimeout', $timeout);
};
ok(!$@, 'SetAttribute');

$response = $q->ReceiveMessage();
ok(!defined($response), 'ReceiveMessage called on empty queue returns undef');

sleep 5;

my $lists = $sqs->ListQueues();
ok((grep { $_->Endpoint() eq $q->Endpoint() } @$lists), 'ListQueues returns the queue we just created');

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

sleep 5;

my $received_msg = $q->ReceiveMessage();

eval {
    my $str = "$received_msg";
};
ok(!$@, "Interpolating Amazon::SQS::Simple::Message object in string context");

ok(UNIVERSAL::isa($received_msg, 'Amazon::SQS::Simple::Message'), 'ReceiveMessage returns Amazon::SQS::Simple::Message object');
ok((grep {$_ eq $received_msg->MessageBody} values %messages), 'ReceiveMessage returned one of the messages we wrote');

# Have a few goes at GetAttributes, sometimes takes a while for SetAttributes
# method to be processed
my $i = 0;
do {
    sleep 10 if $i++;
    $href = $q->GetAttributes();
} while ((!$href->{VisibilityTimeout} || $href->{VisibilityTimeout} != $timeout) && $i < 20);

ok(
    $href->{VisibilityTimeout} && $href->{VisibilityTimeout} == $timeout
    , "GetAttributes"
) or diag("Failed after $i attempts, sent $timeout, got back " . ($href->{VisibilityTimeout} ? $href->{VisibilityTimeout} : 'undef'));


# 2007-05-01 uses the MessageId, 2008-01-01 uses the ReceiptHandle
eval { $q->DeleteMessage($received_msg->ReceiptHandle); };
ok(!$@, 'DeleteMessage on ReceiptHandle of received message') or diag($@);

eval { $q->Delete(); };
ok(!$@, 'Delete on non-empty queue') or diag($@);
