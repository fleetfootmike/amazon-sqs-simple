package Amazon::SQS::Simple::Base;

use strict;
use warnings;
use Carp qw( croak carp );
use Digest::HMAC_SHA1;
use Digest::SHA qw(hmac_sha256 sha256);
use Furl;
use MIME::Base64;
use URI::Escape;
use XML::Simple;
use Encode qw(encode);

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
our $URI_SAFE_CHARACTERS = '^A-Za-z0-9-_.~'; # defined by AWS, same as URI::Escape defaults

sub new {
    my $class      = shift;
    my $access_key = shift;
    my $secret_key = shift;
    
    my $self = {
        AWSAccessKeyId   => $access_key,
        SecretKey        => $secret_key,
        Endpoint         => +BASE_ENDPOINT,
        SignatureVersion => 2,
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
    my $ua           = Furl->new();
    my $url          = $self->{Endpoint};
    my $response;
    my $post_body;
    my $post_request = 0;

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
    
    if ($params->{MessageBody} && length($params->{MessageBody}) > $self->_max_get_msg_size) {
        $post_request = 1;
    }

    my ($query, @auth_headers) = $self->_get_signed_query($params, $post_request);

    $self->_debug_log($query);

	my $try;
	foreach $try (1..3) {	
	    if ($post_request) {
	        $response = $ua->post(
	            $url,
                [
	                'Content-Type' => 'application/x-www-form-urlencoded;charset=utf-8',
	                @auth_headers,
                ],
	            $query,
	        );
	    }
	    else {
	        $response = $ua->get(
                "$url/?$query",
                [
                    "Content-Type" => "text/plain;charset=utf-8",
                    @auth_headers,
                ],
            );
	    }
        
		# $response isa Furl::Response
		
	    if ($response->is_success) {
	        $self->_debug_log($response->content);
	        my $href = XMLin($response->content, ForceArray => $force_array, KeyAttr => {});
	        return $href;
	    }
	
		# advice from internal AWS support - most client libraries try 3 times in the face
		# of 500 errors, so ours should too
		
		next if ($response->code == 500);
     }

	 # if we fall out of the loop, then we have either a non-500 error or a persistent 500.
	
     my $msg;
     eval {
         my $href = XMLin($response->content);
         $msg = $href->{Error}{Message};
     };
 
     my $error = "ERROR [try $try]: On calling $params->{Action}: " . $response->status_line;
     $error .= " ($msg)" if $msg;
     croak $error;
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
    my ($self, $params, $post_request) = @_;

    my $version = $params->{SignatureVersion};
       $version = $self->{SignatureVersion} unless defined $version;
    my @auth_headers;

    if ($version == 0 and defined $version) {
        $params = $self->_sign_query_v0($params);
    } elsif ($version == 1) {
        $params = $self->_sign_query_v1($params);
    } elsif ($version == 2) {
        $params = $self->_sign_query_v2($params, $post_request);
    } elsif ($version == 3) {
        ($params, @auth_headers) = $self->_sign_query_v3($params, $post_request);
    } else {
        croak "unrecognized SignatureVersion: $version";
    }

    $params = $self->_escape_params($params);

    my $query = join('&', map { $_ . '=' . $params->{$_} } keys %$params);
    return ($query, @auth_headers);
}

sub _sign_query_v0 {
    my ($self, $params) = @_;

    carp "Signature version 0 is deprecated";

    my $to_sign = $params->{Action} . $params->{Timestamp};
    $params->{SignatureVersion} = 0;
    my $hmac = Digest::HMAC_SHA1->new($self->{SecretKey})->add($to_sign);
    $params->{Signature} = encode_base64($hmac->digest, '');

    return $params;
}

sub _sign_query_v1 {
    my ($self, $params) = @_;
    my $to_sign = '';
    
    $params->{SignatureVersion} = 1;
    
    for my $key( sort { uc $a cmp uc $b } keys %$params ) {
        if (defined $params->{$key}) {
            $to_sign = $to_sign . $key . $params->{$key};
        }
    }

    my $hmac = Digest::HMAC_SHA1->new($self->{SecretKey})->add($to_sign);
    $params->{Signature} = encode_base64($hmac->digest, '');

    return $params;
}

sub _sign_query_v2 {
    my ($self, $params, $post_request) = @_;

    $params->{SignatureVersion} = 2;
    $params->{SignatureMethod} = 'HmacSHA256';

    my $to_sign;
    for my $key( sort keys %$params ) {
        $to_sign .= '&' if $to_sign;
        my $key_octets   = encode('utf-8-strict', $key);
        my $value_octets = encode('utf-8-strict', $params->{$key});
        $to_sign .= uri_escape($key_octets, $URI_SAFE_CHARACTERS) . '=' . uri_escape($value_octets, $URI_SAFE_CHARACTERS);
    }

    my $verb = "GET";
       $verb = "POST" if $post_request;
    my $host = lc URI->new($self->{Endpoint})->host;
    my $path = '/';
    if ($self->{Endpoint} =~ m{^https?://[^/]*(/.*)$}) {
        $path = "$1";
        $path .= '/' unless $post_request; # why is this not in the spec?
    }

    $to_sign = "$verb\n$host\n$path\n$to_sign";
    $params->{Signature} = encode_base64(hmac_sha256($to_sign, $self->{SecretKey}),'');
    return $params;
}

sub _sign_query_v3 {

    croak "Signature version 3 is not yet supported";

    # this is an untested draft based on V3 signatures in SES
    # SQS apparently does not yet support this

    # my ($self, $params, $post_request) = @_;
    #
    # my @auth_headers;
    # require Date::Format;
    # my $date = Date::Format::time2str('%a, %d %b %Y %X %z', time() + 5);   # or must this be GM time?
    #
    # if ($self->{Endpoint} =~ m{^https://}) {
    #     my $to_sign = $date;
    #     my $signature = encode_base64(hmac_sha256($to_sign, $self->{SecretKey}),'');
    #     @auth_headers = ('Date', $date,
    #                      'X-Amzn-Authorization', "AWS3-HTTPS AWSAccessKeyId=$self->{AWSAccessKeyId},Algorithm=HmacSHA256,Signature=$signature");
    # } else {
    #     my $query;
    #     for my $key ( sort keys %$params ) {
    #         $query .= '&' if $query;
    #         my $key_octets   = encode('utf-8-strict', $key);
    #         my $value_octets = encode('utf-8-strict', $params->{$key});
    #         $query .= uri_escape($key_octets, $URI_SAFE_CHARACTERS) . '=' . uri_escape($value_octets, $URI_SAFE_CHARACTERS);
    #     }
    #     my $verb = "GET";
    #     $verb = "POST" if $post_request;
    #     my $host = lc URI->new($self->{Endpoint})->host;
    #     my $path = '/';
    #     if ($self->{Endpoint} =~ m{^https?://[^/]*(/.*)$}) {
    #         $path = "$1";
    #         $path .= '/' unless $post_request; # why is this not in the spec?
    #     }
    #     my $to_sign = "$verb\n$path\n$query\nhost:$host\ndate:$date\n";
    #     my $signature = encode_base64(hmac_sha256(sha256($to_sign), $self->{SecretKey}),'');   # yes, it hashes twice in the reference code
    #     @auth_headers = ('Date', $date,
    #                      'Host', $host,
    #                      'X-Amzn-Authorization', "AWS3 AWSAccessKeyId=$self->{AWSAccessKeyId},Algorithm=HmacSHA256,Signature=$signature,SignedHeaders=Date;Host'");
    # }
    #
    # return $params, @auth_headers;

}

sub _escape_params {
    my ($self, $params) = @_;

    # Need to escape + characters in signature
    # see http://docs.amazonwebservices.com/AWSSimpleQueueService/2006-04-01/Query_QueryAuth.html

    # Likewise, need to escape + characters in ReceiptHandle
    # Many characters are possible in MessageBody:
    #    #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]
    # probably should encode all keys and values for consistency and future-proofing
    my $to_escape = qr{^(?:Signature|MessageBody|ReceiptHandle)|\.\d+\.(?:MessageBody|ReceiptHandle)$};
    foreach my $key (keys %$params) {
        next unless $key =~ m/$to_escape/;
        next unless exists $params->{$key};
        my $octets = encode('utf-8-strict', $params->{$key});
        $params->{$key} = uri_escape($octets, $URI_SAFE_CHARACTERS);
    }
    return $params;
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
Copyright 2013 Mike (no relation) Whitaker E<lt>penfold@cpan.orgE<gt>

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

