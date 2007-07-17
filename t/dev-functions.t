#!perl -T

use strict;
use warnings;
use Test::More tests => 2;

BEGIN {
    use_ok('Amazon::SQS::Simple', qw( timestamp ));
}

my $timestamp  = timestamp('0');

ok(
    $timestamp 
    && $timestamp eq '1970-01-01T00:00:00Z'
    , 'timestamp'
);