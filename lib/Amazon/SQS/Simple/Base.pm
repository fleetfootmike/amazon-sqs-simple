package Amazon::SQS::Simple::Base;

use strict;
use warnings;
use Carp qw( croak carp );
use Digest::HMAC_SHA1;
use LWP::UserAgent;
use MIME::Base64;
use URI::Escape;
use XML::Simple;

use base qw(Exporter);

use constant { 
    SQS_VERSION_2012_11_05 => '2012-11-05',
    SQS_VERSION_2009_02_01 => '2009-02-01',
    SQS_VERSION_2008_01_01 => '2008-01-01',
    BASE_ENDPOINT          => 'http://queue.amazonaws.com',
    DEF_MAX_GET_MSG_SIZE   => 4096, # Messages larger than this size will use a POST request.
};
                                       
our $DEFAULT_SQS_VERSION = SQS_VERSION_2012_11_05;
our @EXPORT = qw(SQS_VERSION_2012_11_05 SQS_VERSION_2009_02_01 SQS_VERSION_2008_01_01);

sub new {
    my $class      = shift;
    my $access_key = shift;
    my $secret_key = shift;
    
    my $self = {
        AWSAccessKeyId   => $access_key,
        SecretKey        => $secret_key,
        Endpoint         => BASE_ENDPOINT,
        SignatureVersion => 1,
        Version          => $DEFAULT_SQS_VERSION,
        @_,
    };

    if (!$self->{AWSAccessKeyId} || !$self->{SecretKey}) {
        croak "Missing AWSAccessKey or SecretKey";
    }

    # validate the Version, warn if it's not one we recognise
    my @valid_versions = ( SQS_VERSION_2012_11_05, SQS_VERSION_2008_01_01, SQS_VERSION_2009_02_01 );
    if (!grep {$self->{Version} eq $_} @valid_versions) {
        carp "Warning: " 
           . $self->{Version} 
           . " might not be a valid version. Recognised versions are " 
           . join(', ', @valid_versions);
    }

    $self = bless($self, $class);
    $self->_debug_log("Version is set to $self->{Version}");
    return $self;
}

sub _api_version {
    my $self = shift;
    return $self->{Version};
}

sub _dispatch {
    my $self         = shift;
    my $params       = shift || {};
    my $force_array  = shift || [];
    my $ua           = LWP::UserAgent->new();
    my $url          = $self->{Endpoint};
    my $response;
    my $post_body;
    
    if ($self->{Timeout}) {
        $ua->timeout($self->{Timeout});
    }

    $ua->env_proxy;
    
    $params = {
        AWSAccessKeyId      => $self->{AWSAccessKeyId},
        Version             => $self->{Version},
        %$params
    };

    if (!$params->{Timestamp} && !$params->{Expires}) {
        $params->{Timestamp} = _timestamp();
    }
    
    my $post_request = $self->_get_or_post($params);    
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
        my $href = XMLin($response->content, ForceArray => $force_array, KeyAttr => {});
        return $href;
    }
    else {
        my $msg;
        eval {
            my $href = XMLin($response->content);
            $msg = $href->{Error}{Message};
        };
        
        my $error = "ERROR: On calling $params->{Action}: " . $response->status_line;
        $error .= " ($msg)" if $msg;
        croak $error;
    }
}

sub _get_or_post {
    my ($self, $params) = @_;
    
    my $msg_size = 0;
    
    # a single message
    if ($params->{MessageBody}) {
        $msg_size = length($params->{MessageBody});
    }
    # a batch message
    elsif ($params->{"SendMessageBatchRequestEntry.1.MessageBody"}) {
        foreach my $i (1..10){
            last unless $msg_size += length($params->{"SendMessageBatchRequestEntry.$i.MessageBody"});
        }
    }
    return $msg_size > $self->_max_get_msg_size ? 1 : 0;
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
    $params->{Signature} = uri_escape(encode_base64($hmac->digest, ''));
    
    # Likewise, need to escape + characters in MessageBody and ReceiptHandle
    _escape_param($params, 'MessageBody', 'SendMessageBatchRequestEntry.n.MessageBody');
    _escape_param($params, 'ReceiptHandle', 'DeleteMessageBatchRequestEntry.n.ReceiptHandle');
    
    my $query = join('&', map { $_ . '=' . $params->{$_} } keys %$params);
    return $query;
}

sub _escape_param {
    my $params  = shift;
    my $single  = shift;
    my $multi_n = shift;
    
    if ($params->{$single}){
        $params->{$single} = uri_escape($params->{$single});
    }
    else {
        foreach my $i (1..10){
            my $multi = $multi_n;
            $multi =~ s/\.n\./\.$i\./;
            if ($params->{$multi}){
                $params->{$multi} = uri_escape($params->{$multi});
            }
            else {
                last;
            }
        }        
    }   
}

sub _max_get_msg_size {
    my $self = shift;
    # a user-defined cut-off
    if (defined $self->{MAX_GET_MSG_SIZE}){
        return $self->{MAX_GET_MSG_SIZE};
    }
    # the default cut-off
    else {
        return DEF_MAX_GET_MSG_SIZE;
    }
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

Copyright 2007-2008 Simon Whitaker E<lt>swhitaker@cpan.orgE<gt>

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

