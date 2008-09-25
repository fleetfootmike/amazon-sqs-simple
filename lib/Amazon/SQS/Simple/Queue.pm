package Amazon::SQS::Simple::Queue;

use strict;
use warnings;
use Amazon::SQS::Simple::Message;
use Amazon::SQS::Simple::SendResponse;

use base 'Amazon::SQS::Simple::Base';
use Amazon::SQS::Simple::Base; # for constants

sub Endpoint {
    my $self = shift;
    return $self->{Endpoint};
}

sub Delete {
    my $self = shift;
    my $force = shift; # from API 2007-05-01
    my $params = { Action => 'DeleteQueue' };
    $params->{ForceDeletion} = 'true' if $force && $self->_api_version() eq +SQS_VERSION_2007_05_01;
    
    my $href = $self->_dispatch($params);    
}

sub SendMessage {
    my ($self, $message, %params) = @_;
    
    $params{Action} = 'SendMessage';
    $params{MessageBody} = $message;
    
    my $href = $self->_dispatch(\%params);    

    if ($self->_api_version() eq +SQS_VERSION_2007_05_01) {
        return new Amazon::SQS::Simple::SendResponse(
            $href
        );
    }
    else {
        # default to most recent version
        return new Amazon::SQS::Simple::SendResponse(
            $href->{SendMessageResult}
        );
    }
}

sub ReceiveMessage {
    my ($self, %params) = @_;
    
    $params{Action} = 'ReceiveMessage';
    
    my $href = $self->_dispatch(\%params);

    my $msg = undef;

    if ($self->_api_version() eq +SQS_VERSION_2007_05_01) {
        if (defined $href->{Message}) {
            $msg = new Amazon::SQS::Simple::Message(
                $href->{Message},
                $self->_api_version()
            );
        }
    }
    else {
        # default to most recent version
        if (defined $href->{ReceiveMessageResult}{Message}) {
            $msg = new Amazon::SQS::Simple::Message(
                $href->{ReceiveMessageResult}{Message},
                $self->_api_version()
            );
        }
    }
    return $msg;
}

sub DeleteMessage {
    my ($self, $receipt_handle, %params) = @_;
    
    $params{Action} = 'DeleteMessage';
    if ($self->_api_version() eq +SQS_VERSION_2007_05_01) {
        $params{MessageId} = $receipt_handle;
    }
    else {
        # default to the current version
        $params{ReceiptHandle} = $receipt_handle;
    }
    
    my $href = $self->_dispatch(\%params);
}

sub GetAttributes {
    my ($self, %params) = @_;
    
    $params{Action}          = 'GetQueueAttributes';

    my %result;
    if ($self->_api_version() eq +SQS_VERSION_2007_05_01) {
        $params{Attribute} ||= 'All';
    
        my $href = $self->_dispatch(\%params, [ 'AttributedValue' ]);

        if ($href->{'AttributedValue'}) {
            foreach my $attr (@{$href->{'AttributedValue'}}) {
                $result{$attr->{Attribute}} = $attr->{Value};
            }
        }
    }
    else {
        # default to the current version
        $params{AttributeName} ||= 'All';
    
        my $href = $self->_dispatch(\%params, [ 'Attribute' ]);

        if ($href->{GetQueueAttributesResult}) {
            foreach my $attr (@{$href->{GetQueueAttributesResult}{Attribute}}) {
                $result{$attr->{Name}} = $attr->{Value};
            }
        }
    }
    
    return \%result;
}

sub SetAttribute {
    my ($self, $key, $value, %params) = @_;
    
    $params{Action}             = 'SetQueueAttributes';
    if ($self->_api_version() eq +SQS_VERSION_2007_05_01) {
        $params{Attribute} = $key;
        $params{Value}     = $value;
    }
    else {
        # default to the current version
        $params{'Attribute.Name'}   = $key;
        $params{'Attribute.Value'}  = $value;
    }
    
    my $href = $self->_dispatch(\%params);
}

1;

__END__

=head1 NAME

Amazon::SQS::Simple::Queue - OO API for representing queues from 
the Amazon Simple Queue Service.

=head1 SYNOPSIS

    use Amazon::SQS::Simple;

    my $access_key = 'foo'; # Your AWS Access Key ID
    my $secret_key = 'bar'; # Your AWS Secret Key

    my $sqs = new Amazon::SQS::Simple($access_key, $secret_key);

    my $q = $sqs->CreateQueue('queue_name');

    $q->SendMessage('Hello world!');

    my $msg = $q->ReceiveMessage();

    print $msg->MessageBody() # Hello world!

    $q->DeleteMessage($msg->MessageId());

=head1 INTRODUCTION

Don't instantiate this class directly. Objects of this class are returned
by various methods in C<Amazon::SQS::Simple>. See L<Amazon::SQS::Simple> for
more details.

=head1 METHODS

=over 2

=item B<Endpoint()>

Get the endpoint for the queue.

=item B<Delete([%opts])>

Deletes the queue. Any messages contained in the queue will be lost.

=item B<SendMessage($message, [%opts])>

Sends the message. The message can be up to 8KB in size and should be
plain text.

=item B<ReceiveMessage([%opts])>

Get the next message from the queue.

Returns an C<Amazon::SQS::Simple::Message> object. See 
L<Amazon::SQS::Simple::Message> for more details.

Options for ReceiveMessage:

=over 4

=item * NumberOfMessages => NUMBER

Number of messages to return

=back

=item B<DeleteMessage($message_id, [%opts])>

Delete the message with the specified message ID from the queue

=item B<GetAttributes([%opts])>

Get the attributes for the queue. Returns a reference to a hash
mapping attribute names to their values. Currently the following
attribute names are returned:

=over 4

=item * VisibilityTimeout

=item * ApproximateNumberOfMessages

=back

=item B<SetAttribute($attribute_name, $attribute_value, [%opts])>

Sets the value for a queue attribute. Currently the only valid
attribute name is C<VisibilityTimeout>.

=back

=head1 AUTHOR

Copyright 2007-2008 Simon Whitaker E<lt>swhitaker@cpan.orgE<gt>

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
