package SQS::Simple::Queue;

use base 'SQS::Simple';

sub DeleteQueue {
    my $self = shift;
    my $params = { Action => 'DeleteQueue' };
    
    my $href = $self->dispatch($params);    
}

sub SendMessage {
    my ($self, $message, $params) = @_;
    
    $params->{Action} = 'SendMessage';
    $params->{MessageBody} = $message;
    
    my $href = $self->dispatch($params);    
    
    return $href->{MessageId};
}

sub ReceiveMessage {
    my ($self, $params) = @_;
    
    $params->{Action} = 'ReceiveMessage';
    
    my $href = $self->dispatch($params);

    # return value will be single hashref, or ref array of
    # hashrefs if NumberOfMessages was set and > 1
    return $href->{Message};
}

sub DeleteMessage {
    my ($self, $message_id, $params) = @_;
    
    $params->{Action} = 'DeleteMessage';
    $params->{MessageId} = $message_id;
    
    my $href = $self->dispatch($params);
}

sub PeekMessage {
    my ($self, $message_id, $params) = @_;
    
    $params->{Action} = 'PeekMessage';
    $params->{MessageId} = $message_id;
    
    my $href = $self->dispatch($params);
    
    return $href->{Message};
}

sub GetAttributes {
    my ($self, $params) = @_;
    
    $params->{Action} = 'GetQueueAttributes';
    $params->{Attribute} ||= 'All';
    
    my $href = $self->dispatch($params, [ 'AttributedValue' ]);
        
    my %result;
    if ($href->{'AttributedValue'}) {
        foreach my $attr (@{$href->{'AttributedValue'}}) {
            $result{$attr->{Attribute}} = $attr->{Value};
        }
    }
    return \%result;
}

sub SetAttribute {
    my ($self, $key, $value, $params) = @_;
    
    $params->{Action}    = 'SetQueueAttributes';
    $params->{Attribute} = $key;
    $params->{Value}     = $value;
    
    my $href = $self->dispatch($params);
}

1;
