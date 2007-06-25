package Amazon::SQS::Simple;

use Carp qw( croak );
use Digest::HMAC_SHA1;
use LWP::UserAgent;
use MIME::Base64;
use Amazon::SQS::Simple::Queue;
use URI::Escape;
use XML::Simple;

use base qw(Exporter);

use constant SQS_VERSION      => '2007-05-01';
use constant BASE_ENDPOINT    => 'http://queue.amazonaws.com';
use constant MAX_GET_MSG_SIZE => 4096; # Messages larger than this size will be sent
                                       # using a POST request. This feature requires
                                       # SQS_VERSION 2007-05-01 or later.
                                       
use overload '""' => \&to_string;

our $VERSION   = '0.1';
our @EXPORT_OK = qw( timestamp );

sub new {
    my $class = shift;
    my $self = {
        Endpoint => +BASE_ENDPOINT,
        SignatureVersion => 1,
        @_,
    };
    if (!$self->{AWSAccessKeyId} || !$self->{SecretKey}) {
        croak "Missing AWSAccessKey or SecretKey";
    }
    return bless($self, $class);
}

sub to_string {
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
    my ($self, $queue_name, $params) = @_;
    
    $params->{Action}    = 'CreateQueue';
    $params->{QueueName} = $queue_name;
        
    my $href = $self->dispatch($params);
    
    if ($href->{QueueUrl}) {
        return Amazon::SQS::Simple::Queue->new(
            %$self,
            Endpoint => $href->{QueueUrl},
        );
    }
    else {
        die "Failed to create a queue: " . $response->status_line;
    }
}

sub ListQueues {
    my ($self, $queue_name, $params) = @_;
    
    $params->{Action} = 'ListQueues';
        
    my $href = $self->dispatch($params, ['QueueUrl']);
    
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

sub dispatch {
    my $self         = shift;
    my $params       = shift || {};
    my $force_array  = shift || [];
    my $post_request = 0;
    my $msg; # only used for POST requests
    
    $params = {
        AWSAccessKeyId      => $self->{AWSAccessKeyId},
        Version             => +SQS_VERSION,
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
