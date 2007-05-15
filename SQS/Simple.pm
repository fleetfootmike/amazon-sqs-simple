package SQS::Simple;

use Digest::HMAC_SHA1;
use Exporter;
use LWP::UserAgent;
use MIME::Base64;
use SQS::Simple::Queue;
use XML::Simple;

use constant SQS_VERSION => '2006-04-01';
use constant ENDPOINT    => 'http://queue.amazonaws.com';

our EXPORT_OK = qw( timestamp );

sub new {
    my $class = shift;
    my $self = {
        Endpoint => +ENDPOINT,
        SignatureVersion => 1,
        @_,
    };
    return bless($self, $class);
}

sub AUTOLOAD {
    my ($self, %params) = @_;
    
    # action is the method name minus its package qualifier
    (my $action = $AUTOLOAD) =~ s/^.*://;
    
    %params = (
        Action              => $action,
        AWSAccessKeyId      => $self->{AWSAccessKeyId},
        Version             => +SQS_VERSION,
        %params
    );
    if (!$params{Timestamp} && !$params{Expires}) {
        $params{Timestamp} = timestamp();
    }

    my $url      = $self->_get_signed_url(\%params);
    $url         =~ s/\s//g;
    
    my $ua       = LWP::UserAgent->new();
    my $response = $ua->get($url);
    
    if ($response->is_success) {
        my $href = XMLin($response->content);
    
        if ($action eq 'CreateQueue') {
            if ($href->{QueueUrl}) {
                return SQS::Simple::Queue->new(
                    AWSAccessKeyId  => $self->{AWSAccessKeyId}, 
                    SecretKey       => $self->{SecretKey},
                    Endpoint        => $href->{QueueUrl},
                );
            }
            else {
                die "Failed to create a queue: " . $response->status_line;
            }
        }
        else {
            return $href;
        }
    }
    else {
        die "On calling $AUTOLOAD\n$url\nERROR: " . $response->status_line;
    }
}

# Define DESTROY explicitly so it doesn't get autoloaded
sub DESTROY {}

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
     
    $params->{Signature} = encode_base64($hmac->digest);
    my $url = $self->{Endpoint} . '/?' . join('&', map { $_ . '=' . $params->{$_} } keys %$params);
    return $url;
}

1;
