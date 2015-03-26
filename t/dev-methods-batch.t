#!perl  -T

use strict;
use warnings;
use Test::More tests => 50;
use Test::Warn;
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

my $queue_name  = "_test_queue_$$";

my $timeout     = 123;
my ($href, $responses, $ten_responses, $one_response, @received, $received);

my $q = $sqs->CreateQueue($queue_name);

$received = $q->ReceiveMessageBatch();
ok(!defined($received), 'ReceiveMessage called on empty queue returns undef');

my @ten_messages = ('A'..'J');
ok($responses = $q->SendMessageBatch(\@ten_messages), 'SendMessageBatch');
is(scalar(@$responses), 10, '10 response objects');

foreach my $response (@$responses){
	isa_ok($response, 'Amazon::SQS::Simple::SendResponse', "SendMessage returns Amazon::SQS::Simple::SendResponse object");
	is($response->VerifyReceipt, 1, 'Message receipt verified')
		or diag('VerifyReceipt failed');
}

my @eleven_messages = ('K'..'U');
warning_is { $ten_responses = $q->SendMessageBatch(\@eleven_messages) } "Batch messaging limited to 10 messages", "SendMessageBatch: Too many messages warning";
is(scalar(@$ten_responses), 10, '10 response objects from 11 batch messages');

# list context
ok(@received = $q->ReceiveMessageBatch(), 'ReceiveMessageBatch, list return of '. scalar @received .' messages');

while (my @more = $q->ReceiveMessageBatch() ){
	push @received, @more;
}

is(scalar(@received), 20, '20 messages received');
foreach my $msg (@received){
	isa_ok($msg, 'Amazon::SQS::Simple::Message', "ReceiveMessage returns Amazon::SQS::Simple::Message objects in list context");
}

my @five = splice(@received, 0, 5);
ok($q->DeleteMessageBatch(\@five), 'DeleteMessageBatch - five messages');

my @eleven = splice(@received, 0, 11);
warning_is { $q->DeleteMessageBatch(\@eleven) } "Batch deletion limited to 10 messages", "SendMessageBatch: Too many messages warning";

$q->Delete;
