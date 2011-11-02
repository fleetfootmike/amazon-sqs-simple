package Amazon::SQS::Simple::Message;

use strict;
use warnings;

use Amazon::SQS::Simple::Base; # for constants

sub new {
    my $class = shift;
    my $msg = shift;
    my $version = shift || $Amazon::SQS::Simple::Base::DEFAULT_SQS_VERSION;
    $msg->{Version} = $version;
    if (ref $msg->{Attribute} eq 'ARRAY') {
        foreach my $att (@{$msg->{Attribute}}) {
            $msg->{$att->{Name}}=$att->{Value};
        }
        delete $msg->{Attribute};
    }
    return bless ($msg, $class);
}

sub MessageBody {
    my $self = shift;
    return $self->{Body};
}

sub MD5OfBody {
    my $self = shift;
    return $self->{MD5OfBody};
}

sub MessageId {
    my $self = shift;
    return $self->{MessageId};
}

sub ReceiptHandle {
    my $self = shift;
    return $self->{ReceiptHandle};
}

sub SenderId {
    my $self = shift;
    return $self->{SenderId};
}

sub SentTimestamp {
    my $self = shift;
    return $self->{SentTimestamp};
}

sub ApproximateReceiveCount {
    my $self = shift;
    return $self->{ApproximateReceiveCount};
}

sub ApproximateFirstReceiveTimestamp {
    my $self = shift;
    return $self->{ApproximateFirstReceiveTimestamp};
}

1;

__END__

=head1 NAME

Amazon::SQS::Simple::Message - OO API for representing messages from 
the Amazon Simple Queue Service.

=head1 INTRODUCTION

Don't instantiate this class directly. Objects of this class are returned
by various methods in C<Amazon::SQS::Simple::Queue>. 
See L<Amazon::SQS::Simple::Queue> for more details.

=head1 METHODS

=over 2

=item B<MessageBody()>

Get the message body.

=item B<MessageId()>

Get the message unique identifier

=item B<MD5OfBody()>

Get the MD5 checksum of the message body

=item B<ReceiptHandle()>

Get the receipt handle for the message (used as an argument to DeleteMessage)

=item B<SenderId()>

Get the AWS account number (if this attribute was requested in
ReceiveMessage)

=item B<SentTimestamp()>

Get the time when the message was sent (if this attribute was requested in
ReceiveMessage)

=item B<ApproximateReceiveCount()>

Get the number of times a message has been received but not deleted (if this
attribute was requested in ReceiveMessage)

=item B<ApproximateFirstReceiveTimestamp()>

Get the time when the message was first received (if this attribute was
requested in ReceiveMessage)

=back

=head1 AUTHOR

Copyright 2007-2008 Simon Whitaker E<lt>swhitaker@cpan.orgE<gt>

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
