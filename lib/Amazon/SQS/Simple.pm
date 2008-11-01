package Amazon::SQS::Simple;

use strict;
use warnings;

use Carp qw( croak );
use Amazon::SQS::Simple::Base; # for constants
use Amazon::SQS::Simple::Queue;
use base qw(Exporter Amazon::SQS::Simple::Base);

our $VERSION   = '1.01';
our @EXPORT_OK = qw( timestamp );

sub GetQueue {
    my ($self, $queue_endpoint) = @_;
    return new Amazon::SQS::Simple::Queue(
        %$self,
        Endpoint => $queue_endpoint,
    );
}

sub CreateQueue {
    my ($self, $queue_name, %params) = @_;
    
    $params{Action}    = 'CreateQueue';
    $params{QueueName} = $queue_name;
        
    my $href = $self->_dispatch(\%params);
    
    if ($self->_api_version() eq +SQS_VERSION_2007_05_01) {
        if ($href->{QueueUrl}) {
            return Amazon::SQS::Simple::Queue->new(
                %$self,
                Endpoint => $href->{QueueUrl},
            );
        }
    }
    else {
        # default to the most recent version
        if ($href->{CreateQueueResult}{QueueUrl}) {
            return Amazon::SQS::Simple::Queue->new(
                %$self,
                Endpoint => $href->{CreateQueueResult}{QueueUrl},
            );
        }
    }
    
}

sub ListQueues {
    my ($self, %params) = @_;
    
    $params{Action} = 'ListQueues';
        
    my $href = $self->_dispatch(\%params, ['QueueUrl']);
    
    if ($self->_api_version() eq +SQS_VERSION_2007_05_01) {
        if ($href->{QueueUrl}) {
            my @result = map {
                new Amazon::SQS::Simple::Queue(
                    %$self,
                    Endpoint => $_,
                )        
            } @{$href->{QueueUrl}};
            return \@result;
        }
        else {
            return undef;
        }
    }
    else {
        # default to the current version
        if ($href->{ListQueuesResult}{QueueUrl}) {
            my @result = map {
                new Amazon::SQS::Simple::Queue(
                    %$self,
                    Endpoint => $_,
                )        
            } @{$href->{ListQueuesResult}{QueueUrl}};

            return \@result;
        }
        else {
            return undef;
        }
    }
}

sub timestamp {
    return Amazon::SQS::Simple::Base::_timestamp(@_);
}

1;

__END__

=head1 NAME

Amazon::SQS::Simple - OO API for accessing the Amazon Simple Queue 
Service

=head1 SYNOPSIS

    use Amazon::SQS::Simple;

    my $access_key = 'foo'; # Your AWS Access Key ID
    my $secret_key = 'bar'; # Your AWS Secret Key
    
    # Create an SQS object
    my $sqs = new Amazon::SQS::Simple($access_key, $secret_key);

    # Create a new queue
    my $q = $sqs->CreateQueue('queue_name');

    # Send a message
    $q->SendMessage('Hello world!');

    # Retrieve a message
    my $msg = $q->ReceiveMessage();
    print $msg->MessageBody() # Hello world!

    # Delete the message
    $q->DeleteMessage($msg->ReceiptHandle());

    # Delete the queue
    $q->Delete();

=head1 INTRODUCTION

Amazon::SQS::Simple is an OO API for the Amazon Simple Queue Service.

=head1 IMPORTANT

This version of Amazon::SQS::Simple defaults to work against version
2008-01-01 of the SQS API.

Earlier API versions may or may not work.  

Actions dropped in recent versions will be dropped.  Sometimes
compatiblity among the Actions is not possible, e.g. Delete in
2007-05-01 takes a MessageId and in 2008-01-01 takes a ReceiptHandle.
We change the request parameters based on the SQS API version, it is
up to the caller to pass the correct value.

Bear in mind that earlier SQS versions are slated for deprecation -
see aws.amazon.com for details.

=head1 CONSTRUCTOR

=over 2

=item new($access_key, $secret_key)

Constructs a new Amazon::SQS::Simple object

C<$access_key> is your Amazon Web Services access key. C<$secret_key> is your Amazon Web
Services secret key. If you don't have either of these credentials, visit
L<http://aws.amazon.com/>.

You may specify an optional named argument for the version of the SQS
API you wish to use.  This allows loading older data.  E.g.:

 my $sqs = new Amazon::SQS::Simple($access_key, $secret_key, Version => '2007-05-01');

This is not guaranteed to work for all older versions.  See IMPORTANT above.

=back

=head1 METHODS

=over 2

=item GetQueue($queue_endpoint)

Gets the queue with the given endpoint. Returns a 
C<Amazon::SQS::Simple::Queue> object. (See L<Amazon::SQS::Simple::Queue> for details.)

=item CreateQueue($queue_name, [%opts])

Creates a new queue with the given name. Returns a 
C<Amazon::SQS::Simple::Queue> object. (See L<Amazon::SQS::Simple::Queue> for details.)

Options for CreateQueue:

=over 4

=item DefaultVisibilityTimeout => SECONDS

Set the default visibility timeout for this queue

=back

=item ListQueues([%opts])

Gets a list of all your current queues. Returns an array of 
C<Amazon::SQS::Simple::Queue> objects. (See L<Amazon::SQS::Simple::Queue> for details.)

Options for ListQueues:

=over 4

=item QueueNamePrefix => STRING

Only those queues whose name begins with the specified string are returned.

=back

=back

=head1 FUNCTIONS

No functions are exported by default; if you want to use them, export them in your use 
line:

    use Amazon::SQS::Simple qw( timestamp );

=over 2

=item timestamp($seconds)

Takes a time in seconds since the epoch and returns a formatted timestamp suitable for
using in a Timestamp or Expires optional method parameter.

=back

=head1 STANDARD OPTIONS

The following options can be supplied with any of the listed methods.

=over 2

=item AWSAccessKeyId => STRING

The AWS Access Key Id to use with the method call. If not provided, Amazon::SQS::Simple uses
the value passed to the constructor.

=item SecretKey => STRING

The Secret Key to use with the method call. If not provided, Amazon::SQS::Simple uses
the value passed to the constructor.

=item Timestamp => TIMESTAMP

All methods are automatically given a timestamp of the time at which they are called,
but you can override this value if you need to. The value for this key should be a
timestamp as returned by the Amazon::SQS::Simple::timestamp() function.

You generally do not need to supply this option.

=item Expires => TIMESTAMP

All methods are automatically given a timestamp of the time at which they are called.
You can alternatively set an expiry time by providing an Expires option. The value
for this key should be a timestamp as returned by the C<Amazon::SQS::Simple::timestamp()>
function.

You generally do not need to supply this option.

=back

=head1 ACKNOWLEDGEMENTS

Bill Alford wrote the code to support basic functionality of older API versions
in release 0.9.

=head1 AUTHOR

Copyright 2007-2008 Simon Whitaker E<lt>swhitaker@cpan.orgE<gt>

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

