package Amazon::SQS::Simple::Queue;

use base 'Amazon::SQS::Simple';

sub Delete {
    my $self = shift;
    my $force = shift;
    my $params = { Action => 'DeleteQueue' };
    $params->{ForceDeletion} = 'true' if $force;
    
    my $href = $self->_dispatch($params);    
}

sub SendMessage {
    my ($self, $message, %params) = @_;
    
    $params{Action} = 'SendMessage';
    $params{MessageBody} = $message;
    
    my $href = $self->_dispatch(\%params);    
    
    return $href->{MessageId};
}

sub ChangeMessageVisibility {
    my ($self, $message_id, $timeout, %params) = @_;
    
    $params{Action} = 'ChangeMessageVisibility';
    $params{MessageId} = $message_id;
    $params{VisibilityTimeout} = $timeout;
    
    my $href = $self->_dispatch(\%params);    
}

sub ReceiveMessage {
    my ($self, %params) = @_;
    
    $params{Action} = 'ReceiveMessage';
    
    my $href = $self->_dispatch(\%params);

    # return value will be single hashref, or ref array of
    # hashrefs if NumberOfMessages was set and > 1
    # Hashref has keys MessageBody and MessageId
    return $href->{Message};
}

sub DeleteMessage {
    my ($self, $message_id, %params) = @_;
    
    $params{Action} = 'DeleteMessage';
    $params{MessageId} = $message_id;
    
    my $href = $self->_dispatch(\%params);
}

sub PeekMessage {
    my ($self, $message_id, %params) = @_;
    
    $params{Action} = 'PeekMessage';
    $params{MessageId} = $message_id;
    
    my $href = $self->_dispatch(\%params);
    
    return $href->{Message};
}

sub GetAttributes {
    my ($self, %params) = @_;
    
    $params{Action} = 'GetQueueAttributes';
    $params{Attribute} ||= 'All';
    
    my $href = $self->_dispatch(\%params, [ 'AttributedValue' ]);
        
    my %result;
    if ($href->{'AttributedValue'}) {
        foreach my $attr (@{$href->{'AttributedValue'}}) {
            $result{$attr->{Attribute}} = $attr->{Value};
        }
    }
    return \%result;
}

sub SetAttribute {
    my ($self, $key, $value, %params) = @_;
    
    $params{Action}    = 'SetQueueAttributes';
    $params{Attribute} = $key;
    $params{Value}     = $value;
    
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

    print $msg->{MessageBody} # Hello world!

    $q->DeleteMessage($msg->{MessageId});

=head1 INTRODUCTION

Don't instantiate this class directly. Objects of this class are returned
by various methods in C<Amazon::SQS::Simple>. See L<Amazon::SQS::Simple> for
more details.

=head1 METHODS

=over 2

=item Delete($force, [%opts])

Deletes the queue. If C<$force> is true, deletes the queue even if it
still contains messages.

=item SendMessage($message, [%opts])

Sends the message. The message can be up to 256KB in size and should be
plain text.

=item ChangeMessageVisibility($message_id, $timeout, [%opts])

Sets the timeout visibility of the message with the specified message ID
to the specified timeout, in seconds.

Note that the timeout counts from the time the method is called. So if
retrieved a message 30 seconds ago that had a timeout of 600 seconds, and
call ChangeMessageVisility with a new timeout of 300s, the visibility will
timeout in 300s.


=item ReceiveMessage([%opts])

Get the next message from the queue.

=item DeleteMessage($message_id, [%opts])

Delete the message with the specified message ID from the queue

=item PeekMessage($message_id, [%opts])

Fetch the message with the specified message ID. Unlike C<ReceiveMessage>
this doesn't affect the visibility of the message.

=item GetAttributes([%opts])

Get the attributes for the queue. Returns a reference to a hash
mapping attribute names to their values. Currently the following
attribute names are returned:

=over

=item *

VisibilityTimeout

=item *

ApproximateNumberOfMessages

=back

=item SetAttribute($attribute_name, $attribute_value, [%opts])

Sets the value for a queue attribute. Currently the only valid
attribute name is C<VisibilityTimeout>.

=back

=head1 AUTHOR

Copyright 2007 Simon Whitaker E<lt>swhitaker@cpan.orgE<gt>

=cut

