package Amazon::SQS::Simple;

use Carp qw( croak );
use Digest::HMAC_SHA1;
use LWP::UserAgent;
use MIME::Base64;
use Amazon::SQS::Simple::Queue;
use URI::Escape;
use XML::Simple;

use base qw(Exporter);

use constant DEFAULT_SQS_VERSION => '2007-05-01';
use constant BASE_ENDPOINT       => 'http://queue.amazonaws.com';
use constant MAX_GET_MSG_SIZE    => 4096; # Messages larger than this size will be sent
                                          # using a POST request. This feature requires
                                          # SQS_VERSION 2007-05-01 or later.
                                       
use overload '""' => \&_to_string;

our $VERSION   = '0.1';
our @EXPORT_OK = qw( timestamp );

sub new {
    my $class = shift;
    my $access_key = shift;
    my $secret_key = shift;
    
    my $self = {
        AWSAccessKeyId   => $access_key,
        SecretKey        => $secret_key,
        Endpoint         => +BASE_ENDPOINT,
        SignatureVersion => 1,
        _Version         => +DEFAULT_SQS_VERSION,
        @_,
    };
    if (!$self->{AWSAccessKeyId} || !$self->{SecretKey}) {
        croak "Missing AWSAccessKey or SecretKey";
    }
    return bless($self, $class);
}

sub _to_string {
    my $self = shift;
    return $self->Endpoint();
}

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
    
    if ($href->{QueueUrl}) {
        return Amazon::SQS::Simple::Queue->new(
            %$self,
            Endpoint => $href->{QueueUrl},
        );
    }
    else {
        croak("Failed to create a queue: " . $response->status_line);
    }
}

sub ListQueues {
    my ($self, %params) = @_;
    
    $params{Action} = 'ListQueues';
        
    my $href = $self->_dispatch(\%params, ['QueueUrl']);
    
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

# Autoload accessors for object member variables
sub AUTOLOAD {
    my ($self, $value) = @_;
    
    (my $method = $AUTOLOAD) =~ s/.*://;
    
    return unless defined $self->{$method};
    
    if (defined $value) {
        $self->{$method} = $value;
        return $self;
    }
    else {
        return $self->{$method};
    }
}

# Explicitly define DESTROY so that it doesn't get autoloaded
sub DESTROY {}

sub _dispatch {
    my $self         = shift;
    my $params       = shift || {};
    my $force_array  = shift || [];
    my $post_request = 0;
    my $msg; # only used for POST requests
    
    $params = {
        AWSAccessKeyId      => $self->{AWSAccessKeyId},
        Version             => $self->{_Version},
        %$params
    };

    if (!$params->{Timestamp} && !$params->{Expires}) {
        $params->{Timestamp} = timestamp();
    }
    
    if ($params->{MessageBody} && length($params->{MessageBody}) > +MAX_GET_MSG_SIZE) {
        $msg = $params->{MessageBody};
        delete($params->{MessageBody});
        $post_request = 1;
    }

    my $url      = $self->_get_signed_url($params);
    my $ua       = LWP::UserAgent->new();
    my $response;

    $self->_debug_log($url);

    if ($post_request) {
        $response = $ua->post(
            $url, 
            'Content-type' => 'text/plain', 
            'Content'      => $msg
        );
    }
    else {
        $response = $ua->get($url);
    }
    
    if ($response->is_success) {
        $self->_debug_log($response->content);
        my $href = XMLin($response->content, ForceArray => $force_array);
        return $href;
    }
    else {
        my $msg;
        eval {
            my $href = XMLin($response->content);
            $msg = $href->{Errors}{Error}{Message};
        };
        my $error = "ERROR: On calling $params->{Action}: " . $response->status_line;
        $error .= " ($msg)" if $msg;
        $error .= "\n";
        die $error;
    }
}

sub timestamp {
    my $t    = shift || time;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($t);
    return sprintf("%4i-%02i-%02iT%02i:%02i:%02iZ",
        ($year + 1900),
        ($mon + 1),
        $mday,
        $hour,
        $min,
        $sec
    );
}

sub _debug_log {
    my ($self, $msg) = @_;
    return unless $self->{_Debug};
    chomp($msg);
    print {$self->{_Debug}} $msg . "\n\n";
}

sub _get_signed_url {
    my ($self, $params) = @_;
    my $sig = '';
    
    if ($self->{SignatureVersion} == 1) {
        $params->{SignatureVersion} = $self->{SignatureVersion};
    
        for my $key( sort { uc $a cmp uc $b } keys %$params ) {
            if (defined $params->{$key}) {
                $sig = $sig . $key . $params->{$key};
            }
        }
    }
    else {
        $sig = $params->{Action} . $params->{Timestamp};
    }

    my $hmac = Digest::HMAC_SHA1->new($self->{SecretKey})->add($sig);
    
    # Need to escape + characters in signature
    # see http://docs.amazonwebservices.com/AWSSimpleQueueService/2006-04-01/Query_QueryAuth.html
    $params->{Signature}   = uri_escape(encode_base64($hmac->digest, ''));
    $params->{MessageBody} = uri_escape($params->{MessageBody}) if $params->{MessageBody};
    
    my $url = $self->{Endpoint} . '/?' . join('&', map { $_ . '=' . $params->{$_} } keys %$params);
    
    return $url;
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
    print $msg->{MessageBody} # Hello world!

    # Delete the message
    $q->DeleteMessage($msg->{MessageId});

    # Delete the queue
    $q->Delete();

=head1 INTRODUCTION

Amazon::SQS::Simple is an OO API for the Amazon Simple Queue
Service.

=head1 CONSTRUCTOR

=over 2

=item new($access_key, $secret_key, [%opts])

Constructs a new Amazon::SQS::Simple object

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

=over 2

=item DefaultVisibilityTimeout => SECONDS

Set the default visibility timeout for this queue

=back

=item ListQueues([%opts])

Gets a list of all your current queues. Returns an array of 
C<Amazon::SQS::Simple::Queue> objects. (See L<Amazon::SQS::Simple::Queue> for details.)

Options for ListQueues:

=over 2

=item QueueNamePrefix => STRING

Only those queues whose name begins with the specified string are returned.

=back

=back

=head1 FUNCTIONS

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

=head1 AUTHOR

Copyright 2007 Simon Whitaker E<lt>swhitaker@cpan.orgE<gt>

=cut

