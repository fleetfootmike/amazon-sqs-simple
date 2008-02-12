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

Amazon::SQS::Simple::SendResponse - OO API for representing responses to
messages sent to the Amazon Simple Queue Service.

=head1 INTRODUCTION

Don't instantiate this class directly. Objects of this class are returned
by SendMessage in C<Amazon::SQS::Simple::Queue>. 
See L<Amazon::SQS::Simple::Queue> for more details.

=head1 METHODS

=over 2

=item B<MessageId()>

Get the message unique identifier

=item B<MD5OfMessageBody()>

Get the MD5 checksum of the message body you sent

=back

=head1 AUTHOR

Copyright 2007 Simon Whitaker E<lt>swhitaker@cpan.orgE<gt>

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
