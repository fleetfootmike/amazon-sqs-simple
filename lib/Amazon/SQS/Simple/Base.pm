package Amazon::SQS::Simple::Base;

use Carp qw( croak carp );
use Digest::HMAC_SHA1;
use LWP::UserAgent;
use MIME::Base64;
use URI::Escape;
use XML::Simple;

use base qw(Exporter);

use constant DEFAULT_SQS_VERSION => '2008-01-01';
use constant BASE_ENDPOINT       => 'http://queue.amazonaws.com';
use constant MAX_GET_MSG_SIZE    => 4096; # Messages larger than this size will be sent
                                          # using a POST request. This feature requires
                                          # SQS_VERSION 2007-05-01 or later.
                                       
use overload '""' => \&_to_string;

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

sub _dispatch {
    my $self         = shift;
    my $params       = shift || {};
    my $force_array  = shift || [];
    my $post_request = 0;
    my $ua           = LWP::UserAgent->new();
    my $url          = $self->{Endpoint};
    my $response;
    my $post_body;
    
    $params = {
        AWSAccessKeyId      => $self->{AWSAccessKeyId},
        Version             => $self->{_Version},
        %$params
    };

    if (!$params->{Timestamp} && !$params->{Expires}) {
        $params->{Timestamp} = _timestamp();
    }
    
    if ($params->{MessageBody} && length($params->{MessageBody}) > +MAX_GET_MSG_SIZE) {
        $post_request = 1;
    }

    my $query = $self->_get_signed_query($params);

    $self->_debug_log($query);

    if ($post_request) {
        $response = $ua->post(
            $url, 
            'Content-type' => 'application/x-www-form-urlencoded', 
            'Content'      => $query
        );
    }
    else {
        $response = $ua->get("$url/?$query");
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
        croak $error;
    }
}

sub _debug_log {
    my ($self, $msg) = @_;
    return unless $self->{_Debug};
    chomp($msg);
    print {$self->{_Debug}} $msg . "\n\n";
}

sub _get_signed_query {
    my ($self, $params) = @_;
    my $sig = '';
    
    if ($self->{SignatureVersion} == 1) {
        $params->{SignatureVersion} = $self->{SignatureVersion};
    
        for my $key( sort { uc $a cmp uc $b } keys %$params ) {
            if (defined $params->{$key}) {
                $sig = $sig . $key . $params->{$key};
            }
        }
    } else {
        $sig = $params->{Action} . $params->{Timestamp};
    }

    my $hmac = Digest::HMAC_SHA1->new($self->{SecretKey})->add($sig);
    
    # Need to escape + characters in signature
    # see http://docs.amazonwebservices.com/AWSSimpleQueueService/2006-04-01/Query_QueryAuth.html
    $params->{Signature}     = uri_escape(encode_base64($hmac->digest, ''));
    $params->{MessageBody}   = uri_escape($params->{MessageBody}) if $params->{MessageBody};
    
    # Likewise, need to escape + characters in ReceiptHandle
    $params->{ReceiptHandle} = uri_escape($params->{ReceiptHandle}) if $params->{ReceiptHandle};
    
    my $query = join('&', map { $_ . '=' . $params->{$_} } keys %$params);
    return $query;
}

sub _timestamp {
    my $t = shift;
    if (!defined $t) {
        $t = time;
    }
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

1;

__END__

=head1 NAME

Amazon::SQS::Simple::Base - No user-serviceable parts included

=head1 AUTHOR

Copyright 2007 Simon Whitaker E<lt>swhitaker@cpan.orgE<gt>

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

