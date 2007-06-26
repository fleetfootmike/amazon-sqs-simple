#!/usr/bin/perl -w

use Amazon::SQS::Simple;
use CGI;

use strict;

my $AWSAccessKeyId  = '0QJGP26J6TDAM7FF06G2'; # rtip-scrum@amazon.com
my $SecretKey       = '3a5P6Sz4LDqUlidEHBdebpBPWx9Ck//Cifh6Bsnc';

my $cgi = new CGI;
my $sqs = new Amazon::SQS::Simple($AWSAccessKeyId, $SecretKey);

my $view = $cgi->param('view');

my %dispatch_table = (
    viewqueue => \&viewqueue,
);

my $func = $dispatch_table{$view} || \&home;

print $cgi->header,
      $cgi->start_html('PDQueue - the SQS Queue Viewer'),
      $cgi->h1('PDQueue'),
      ;

&$func;

print $cgi->end_html;

sub home {
    print $cgi->start_table({-border => 1});
    print $cgi->Tr(
        $cgi->th('Queue'),
        $cgi->th('Default visibility (s)'),
        $cgi->th('Approx # messages'),
    );
    
    my $queues = $sqs->ListQueues();
    if ($queues) {
        foreach my $q (@$queues) {
            my $attributes = $q->GetAttributes();
            
            print $cgi->Tr(
                $cgi->td($cgi->a({-href => "?view=viewqueue&q=" . $q->Endpoint()}, $q)),
                $cgi->td($attributes->{VisibilityTimeout}),
                $cgi->td($attributes->{ApproximateNumberOfMessages}),
            );
        }
    }
    print $cgi->end_table;
}

sub viewqueue {
    my $q = $sqs->GetQueue($cgi->param('q'));
    my $attributes = $q->GetAttributes();
    
    my $msg = $q->ReceiveMessage(VisibilityTimeout => 0);
    my $body = $msg->{MessageBody};
    $body =~ s/.{60}/$&\n/g;
    
    print $cgi->start_table({-border => 1});
    print $cgi->Tr(
        $cgi->td($cgi->b('Queue')),
        $cgi->td($q),
    );
    print $cgi->Tr(
        $cgi->td($cgi->b('Endpoint')),
        $cgi->td($q->Endpoint()),
    );
    print $cgi->Tr(
        $cgi->td($cgi->b('Default visibility (s)')),
        $cgi->td($attributes->{VisibilityTimeout}),
    );
    print $cgi->Tr(
        $cgi->td($cgi->b('Approx # messages')),
        $cgi->td($attributes->{ApproximateNumberOfMessages}),
    );
    print $cgi->Tr(
        $cgi->td($cgi->b('Next message ID')),
        $cgi->td($msg->{MessageId}),
    );
    print $cgi->Tr(
        $cgi->td($cgi->b('Next message size (bytes)')),
        $cgi->td(length($msg->{MessageBody})),
    );
    print $cgi->Tr(
        $cgi->td({-valign => 'top'}, $cgi->b('Next message body')),
        $cgi->td($cgi->pre($body)),
    );
    
    print $cgi->end_table;
}
