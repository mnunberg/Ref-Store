use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Hash::Registry',
    AUTHOR              => q{M. Nunberg, <mnunberg@haskalah.org>},
    VERSION_FROM        => 'lib/Hash/Registry.pm',
    ABSTRACT_FROM       => 'lib/Hash/Registry.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Hash-Registry-*' },
);
