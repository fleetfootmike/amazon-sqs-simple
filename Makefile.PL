use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Amazon::SQS::Simple',
    AUTHOR              => 'Simon Whitaker <sw@netcetera.org>',
    VERSION_FROM        => 'lib/Amazon/SQS/Simple.pm',
    ABSTRACT_FROM       => 'lib/Amazon/SQS/Simple.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More'        => 0,
        'Digest::HMAC_SHA1' => 0,
        'Digest::SHA'       => 0,
        'LWP::UserAgent'    => 0,
        'MIME::Base64'      => 0,
        'URI::Escape'       => 0,
        'XML::Simple'       => 0,
        'Data::UUID'        => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Amazon-SQS-Simple-*' },
);
