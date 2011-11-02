package Amazon::SQS::Simple;

use strict;
use warnings;

use Carp qw( croak carp );
use Amazon::SQS::Simple::Base; # for constants
use Amazon::SQS::Simple::Queue;
use base qw(Exporter Amazon::SQS::Simple::Base);

our $VERSION   = '1.06';
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

    if ($self->_api_version eq +SQS_VERSION_2011_10_01) {
        if (exists $params{DevaultVisibilityTimeout}) {
            $params{VisibilityTimeout} = $params{DefaultVisibilityTimeout};
            delete $params{DefaultVisibilityTimeout};
        }
        my $i = 1;
        foreach my $name (keys %params) {
            my $value = $params{$name};
            delete $params{$name};
            $params{"Attribute.$i.Name"}=$name;
            $params{"Attribute.$i.Value"}=$value;
        } continue {
            $i++;
        }
    } else {
        if (exists $params{VisibilityTimeout}) {
            $params{DevaultVisibilityTimeout} = $params{VisibilityTimeout};
            delete $params{VisibilityTimeout};
        }
    }
    
    $params{Action}    = 'CreateQueue';
    $params{QueueName} = $queue_name;
        
    my $href = $self->_dispatch(\%params);
    
    if ($href->{CreateQueueResult}{QueueUrl}) {
        return Amazon::SQS::Simple::Queue->new(
            %$self,
            Endpoint  => $href->{CreateQueueResult}{QueueUrl},
            QueueName => $queue_name,
        );
    }
}

sub ListQueues {
    my ($self, %params) = @_;
    
    $params{Action} = 'ListQueues';
        
    my $href = $self->_dispatch(\%params, ['QueueUrl']);
    
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

sub GetQueueUrl {
    my ($self,$queue_name, %params) = @_;

    if ($self->_api_version ne +SQS_VERSION_2011_10_01) {
        carp "GetQueueUrl not supported in this API version";
    }

    $params{Action}     = 'GetQueueUrl';
    $params{QueueName}  = $queue_name;

    my $href = $self->_dispatch(\%params);
    return $href->{GetQueueUrlResult}{QueueUrl};
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
2011-10-01 of the SQS API.

Earlier API versions may or may not work.  

=head1 CONSTRUCTOR

=over 2

=item new($access_key, $secret_key, [%opts])

Constructs a new Amazon::SQS::Simple object

C<$access_key> is your Amazon Web Services access key. C<$secret_key> is your Amazon Web
Services secret key. If you don't have either of these credentials, visit
L<http://aws.amazon.com/>.

Options for new:

=over 4

=item Timeout => SECONDS

Set the HTTP user agent's timeout (default is 180 seconds)

=item Version => VERSION_STRING

Specifies the SQS API version you wish to use. E.g.:

 my $sqs = new Amazon::SQS::Simple($access_key, $secret_key, Version => '2008-01-01');

=back

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

=item VisibilityTimeout => SECONDS

The default visibility timeout for this queue.  This option was known as
C<DefaultVisibilityTimeout> prior to API version 2011-10-01.  Both variants
are accepted as synonyms.

=item Policy => JSON-STRING

The formal description of the permissions for a resource. For more
information about Policy, see Basic Policy Structure in the Amazon SQS
Developer Guide.  NOT SUPPORTED IN APIs EARLIER THAN 2011-10-01.

=item MaximumMessageSize => BYTES

How many bytes a message may comprise.  NOT SUPPORTED IN APIs EARLIER THAN
2011-10-01.

=item MessageRetentionPeriod => SECONDS

How long the queue retains a message.  NOT SUPPORTED IN APIs EARLIER THAN
2011-10-01.

=item DelaySeconds => SECONDS

How long to delay each new message before it becomes available to
ReceiveMessage.   NOT SUPPORTED IN APIs EARLIER THAN 2011-10-01.

=back

=item ListQueues([%opts])

Gets a list of all your current queues. Returns an array of 
C<Amazon::SQS::Simple::Queue> objects. (See L<Amazon::SQS::Simple::Queue> for details.)

Options for ListQueues:

=over 4

=item QueueNamePrefix => STRING

Only those queues whose name begins with the specified string are returned.

=back

=item GetQueueUrl($queue_name, [%opts])

Gets the Uniform Resource Locater (URL) of a queue. Returns a scalar value,
C<undef> on failure.

If an C<Amazon::SQS::Simple::Queue> object has been created, the URL for
that queue is available from the C<Endpoint> method.  The C<Endpoint> method
call is preferred where possible because it does not require an HTTP
request. (See L<Amazon::SQS::Simple::Queue> for details.)

Options for CreateQueue:

=over 4

=item QueueOwnerAWSAccountId => STRING

Access a queue belonging to another AWS account, if that queue's owner has
granted the necessary permissions.

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

