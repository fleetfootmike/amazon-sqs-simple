package Amazon::SQS::Simple::Queue;

use strict;
use warnings;
use Amazon::SQS::Simple::Message;
use Amazon::SQS::Simple::SendResponse;
use Carp qw( croak carp );

use base 'Amazon::SQS::Simple::Base';
use Amazon::SQS::Simple::Base; # for constants

use overload '""' => \&_to_string;

sub Endpoint {
    my $self = shift;
    return $self->{Endpoint};
}

sub Delete {
    my $self = shift;
    my $params = { Action => 'DeleteQueue' };
    
    my $href = $self->_dispatch($params);    
}

sub SendMessage {
    my ($self, $message, %params) = @_;
    
    $params{Action} = 'SendMessage';
    $params{MessageBody} = $message;
    
    my $href = $self->_dispatch(\%params);    

    # default to most recent version
    return new Amazon::SQS::Simple::SendResponse(
        $href->{SendMessageResult}
    );
}

sub ReceiveMessage {
    my ($self, %params) = @_;
    
    $params{Action} = 'ReceiveMessage';
    
    my $href = $self->_dispatch(\%params, [qw(Message)]);

    my @messages = ();

    # default to most recent version
    if (defined $href->{ReceiveMessageResult}{Message}) {
        foreach (@{$href->{ReceiveMessageResult}{Message}}) {
            push @messages, new Amazon::SQS::Simple::Message(
                $_,
                $self->_api_version()
            );
        }
    }
    
    if (@messages > 1 || wantarray) {
        return @messages;
    } elsif (@messages) {
        return $messages[0];
    } else {
        return undef;
    }
}

sub DeleteMessage {
    my ($self, $receipt_handle, %params) = @_;
    
    $params{Action} = 'DeleteMessage';
    $params{ReceiptHandle} = $receipt_handle;
    
    my $href = $self->_dispatch(\%params);
}

sub ChangeMessageVisibility {
    my ($self, $receipt_handle, $timeout, %params) = @_;
    
    if ($self->_api_version eq +SQS_VERSION_2008_01_01) {
        carp "ChangeMessageVisibility not supported in this API version";
    }
    else {
        if (!defined($timeout) || $timeout =~ /\D/ || $timeout < 0 || $timeout > 43200) {
            croak "timeout must be specified and in range 0..43200";
        }

        $params{Action}             = 'ChangeMessageVisibility';
        $params{ReceiptHandle}      = $receipt_handle;
        $params{VisibilityTimeout}  = $timeout;

        my $href = $self->_dispatch(\%params);
    }
}

our %valid_permission_actions = map { $_ => 1 } qw(* SendMessage ReceiveMessage DeleteMessage ChangeMessageVisibility GetQueueAttributes);

sub AddPermission {
    my ($self, $label, $account_actions, %params) = @_;
    
    if ($self->_api_version eq +SQS_VERSION_2008_01_01) {
        carp "AddPermission not supported in this API version";
    }
    else {
        $params{Action} = 'AddPermission';
        $params{Label}  = $label;
        my $i = 1;
        foreach my $account_id (keys %$account_actions) {
            $account_id =~ /^\d{12}$/ or croak "Account IDs passed to AddPermission should be 12 digit AWS account numbers, no hyphens";
            my $actions = $account_actions->{$account_id};
            my @actions;
            if (UNIVERSAL::isa($actions, 'ARRAY')) {
                @actions = @$actions;
            } else {
                @actions = ($actions);
            }
            foreach my $action (@actions) {
                exists $valid_permission_actions{$action} 
                    or croak "Action passed to AddPermission must be one of " 
                     . join(', ', sort keys %valid_permission_actions);
            
                $params{"AWSAccountId.$i"} = $account_id;
                $params{"ActionName.$i"}   = $action;
                $i++;
            }
        }
        my $href = $self->_dispatch(\%params);
    }
}

sub RemovePermission {
    my ($self, $label, %params) = @_;
    
    if ($self->_api_version eq +SQS_VERSION_2008_01_01) {
        carp "RemovePermission not supported in this API version";
    }
    else {
        $params{Action} = 'RemovePermission';
        $params{Label}  = $label;
        my $href = $self->_dispatch(\%params);
    }
}

sub GetAttributes {
    my ($self, %params) = @_;
    
    $params{Action} = 'GetQueueAttributes';

    my %result;
    # default to the current version
    $params{AttributeName} ||= 'All';

    my $href = $self->_dispatch(\%params, [ 'Attribute' ]);

    if ($href->{GetQueueAttributesResult}) {
        foreach my $attr (@{$href->{GetQueueAttributesResult}{Attribute}}) {
            $result{$attr->{Name}} = $attr->{Value};
        }
    }
    return \%result;
}

sub SetAttribute {
    my ($self, $key, $value, %params) = @_;
    
    $params{Action}             = 'SetQueueAttributes';
    $params{'Attribute.Name'}   = $key;
    $params{'Attribute.Value'}  = $value;
    
    my $href = $self->_dispatch(\%params);
}

sub _to_string {
    my $self = shift;
    return $self->Endpoint();
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

If MaxNumberOfMessages is greater than 1, the method returns
an array of C<Amazon::SQS::Simple::Message> objects.

Options for ReceiveMessage:

=over 4

=item * MaxNumberOfMessages => NUMBER

Maximum number of messages to return. Value should be an integer between 1
and 10 inclusive. Default is 1. 

=back

=item B<DeleteMessage($receipt_handle, [%opts])>

Delete the message with the specified receipt handle from the queue

=item B<ChangeMessageVisibility($receipt_handle, $timeout, [%opts])>

NOT SUPPORTED IN APIs EARLIER THAN 2009-01-01

Changes the visibility of the message with the specified receipt handle to
C<$timeout> seconds. C<$timeout> must be in the range 0..43200.

=item B<AddPermission($label, $account_actions, [%opts])>

NOT SUPPORTED IN APIs EARLIER THAN 2009-01-01

Sets a permissions policy with the specified label. C<$account_actions>
is a reference to a hash mapping 12-digit AWS account numbers to the action(s)
you want to permit for those account IDs. The hash value for each key can 
be a string (e.g. "ReceiveMessage") or a reference to an array of strings 
(e.g. ["ReceiveMessage", "DeleteMessage"])

=item B<RemovePermission($label, [%opts])>

NOT SUPPORTED IN APIs EARLIER THAN 2009-01-01

Removes the permissions policy with the specified label.

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
