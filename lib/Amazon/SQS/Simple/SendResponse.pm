package Amazon::SQS::Simple::SendResponse;

sub new {
    my ($class, $msg) = @_;
    return bless ($msg, $class);
}

sub MessageId {
    my $self = shift;
    return $self->{MessageId};
}

sub MD5OfMessageBody {
    my $self = shift;
    return $self->{MD5OfMessageBody};
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

=back

=head1 AUTHOR

Copyright 2007 Simon Whitaker E<lt>swhitaker@cpan.orgE<gt>

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
