package Amazon::SQS::Simple::SendResponse;

use strict;
use warnings;

use Carp qw(carp);

sub new {
    my ($class, $msg) = @_;
    if (exists $msg->{SendMessageBatchResultEntry} or exists $msg->{BatchResultErrorEntry}) {
        $msg->{SendMessageBatchResultEntry} ||= [];
        $msg->{BatchResultErrorEntry}       ||= [];
        $msg->{BatchResultSuccessIds}         = [];
        $msg->{BatchResultErrorIds}           = [];
        foreach my $res (sort { $a->{Id} cmp $b->{Id} }
                         grep { defined $_            }
                         @{$msg->{SendMessageBatchResultEntry}}) {
            push @{$msg->{BatchResultSuccessIds}}, $res->{Id};
            $res->{Status} = 1;
        }
        foreach my $err (sort { $a->{Id} cmp $b->{Id} }
                         grep { defined $_            }
                         @{$msg->{BatchResultErrorEntry}}) {
            push @{$msg->{BatchResultErrorIds}}, $err->{Id};
            $err->{Status} = 0;
        }
        foreach my $key (qw(MessageId MD5OfMessageBody Id SenderFault Code Message Status)) {
            $msg->{$key} = [
                            map  { $_->{$key}            }
                            sort { $a->{Id} cmp $b->{Id} }
                            grep { defined $_            }
                            (@{$msg->{SendMessageBatchResultEntry}}, @{$msg->{BatchResultErrorEntry}})
                           ];
        }
        delete $msg->{SendMessageBatchResultEntry};
        delete $msg->{BatchResultErrorEntry};
    }
    return bless ($msg, $class);
}

sub is_batch {
    my $self = shift;
    return 1 if exists $self->{BatchResultSuccessIds} or exists $self->{BatchResultErrorIds};
    return 0;
}

sub is_success {
    my $self = shift;
    if ($self->is_batch()) {
        return 0 if @{$self->{BatchResultErrorIds}};
        return 1;
    } else {
        # Todo, this depends on the object never being instantiated on http
        # failure.  Solution is for _dispatch to return the HTTP response
        # object rather than href, and then pass HTTP response to the
        # constructor in this package.  In that case, other methods such as
        # Code could also be made to work for non-batch requests.
        return 1;
    }
}

sub MessageId {
    my $self = shift;
    return $self->{MessageId};
}

sub MD5OfMessageBody {
    my $self = shift;
    return $self->{MD5OfMessageBody};
}

sub Id {
    my $self = shift;
    my $subset = shift;
    if (defined $subset) {
        carp "argument to 'Id' must be empty, 'All', Error', or 'Success'" unless $subset =~ m{^(?:All|Error|Success)$};
    }
    if ($self->is_batch()) {
        if ($subset eq 'Error') {
            return $self->{BatchResultErrorIds};
        } elsif ($subset eq 'Success') {
            return $self->{BatchResultSuccessIds};
        } else {
            return $self->{Id};
        }
    } else {
        carp "method 'Id' is only available for batch requests";
        return undef;
    }
}

sub Code {
    my $self = shift;
    if ($self->is_batch()) {
        return $self->{Code};
    } else {
        carp "method 'Code' is only available for batch requests";
        return undef;
    }
}

sub Message {
    my $self = shift;
    if ($self->is_batch()) {
        return $self->{Message};
    } else {
        carp "method 'Message' is only available for batch requests";
        return undef;
    }
}

sub SenderFault {
    my $self = shift;
    if ($self->is_batch()) {
        return $self->{SenderFault};
    } else {
        carp "method 'SenderFault' is only available for batch requests";
        return undef;
    }
}

sub Status {
    my $self = shift;
    if ($self->is_batch()) {
        return $self->{Status};
    } else {
        carp "method 'Status' is only available for batch requests";
        return undef;
    }
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

Get the unique identifier of the message.  For batch SendMessage responses,
return an anonymous array of unique identifiers.  When a sub-request of a
batch operation has failed, the corresponding array element will be
C<undef>.

=item B<MD5OfMessageBody()>

Get the MD5 checksum of the message body you sent.  For batch SendMessage
responses, return an anonymous array of MD5 checksums.  When a sub-request
of a batch operation has failed, the corresponding array element will be
C<undef>.

=item B<Id([ 'All' | 'Success' | 'Error' ])>

Batch requests only.

Get the identifier for each portion of a batch request.  Returns an
anonymous array of identifiers.  Each value is always defined, even for
sub-requests that failed.  The values are always in ascending lexicographic
sort order reflecting the order in which the sub-requests were sent.

If the SendMessage request was not a batch operation, C<undef> is returned.

Optionally, the single argument 'All', 'Success', or 'Error' may be given.
'All' is the default.  'Success' causes only Ids from successful sub-requests
to be returned.  'Error' causes only Ids from failed sub-requests to be
returned.

=item B<Code()>

Batch requests only.

Get the error code for each sub-request. Returns an anonymous array of error
codes.  The values will be C<undef> for successful sub-requests.

=item B<Message()>

Batch requests only.

Get the descriptive error message for each sub-request.  Returns an
anonymous array of error messages.  The values will be C<undef> for
successful sub-requests.

=item B<SenderFault()>

Batch requests only.

Returns an anonymous array of boolean values indicating whether an error on
a sub-request was the sender's fault. The values will be C<undef> for
successful sub-requests.

=item B<Status()>

Batch requests only.

Get the success status for each sub-request.  Returns an anonymous array of
boolean values.

=item B<is_batch()>

Report whether the SendMessage request that generated this response
object was a batch operation.

=item B<is_success()>

Report whether the SendMessage request that generated this response object
was successful.  For batch requests this will return true only if all
sub-requests were successful.

=back

=head1 AUTHOR

Copyright 2007-2008 Simon Whitaker E<lt>swhitaker@cpan.orgE<gt>

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
