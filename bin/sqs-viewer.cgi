#!/usr/bin/perl -w

use Amazon::SQS::Simple;
use CGI;

use strict;

my $AWSAccessKeyId  = '0QJGP26J6TDAM7FF06G2'; # rtip-scrum@amazon.com
my $SecretKey       = '3a5P6Sz4LDqUlidEHBdebpBPWx9Ck//Cifh6Bsnc';

my $cgi = new CGI;
my $sqs = new Amazon::SQS::Simple( 
    AWSAccessKeyId  => $AWSAccessKeyId, 
    SecretKey       => $SecretKey,
);

my $view = $cgi->param('view');

print $cgi->header,
      $cgi->start_html,
      $cgi->h1('PDQueue'),
      ;

if ($view && $view eq '?') {
    
}
else {
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
                $cgi->td($q),
                $cgi->td($attributes->{VisibilityTimeout}),
                $cgi->td($attributes->{ApproximateNumberOfMessages}),
            );
        }
    }
    print $cgi->end_table;
}

print $cgi->end_html;

