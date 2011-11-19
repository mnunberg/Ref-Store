use strict;
use warnings;
use ExtUtils::MakeMaker;

my $XSFILE = 'Registry.xs';
my $HDR = 'hreg.h';
my @modules = qw(hr_pl hr_hrimpl hreg);
my $modstring = join(".o ", @modules) . ".o";

my $GENERATED_FILES = "*.o Registry.* INLINE.h";

WriteMakefile(
    NAME                => 'Hash::Registry',
    AUTHOR              => q{M. Nunberg, <mnunberg@haskalah.org>},
    VERSION_FROM        => 'lib/Hash/Registry.pm',
    ABSTRACT_FROM       => 'lib/Hash/Registry.pm',
    CONFIGURE_REQUIRES  => { 'InlineX::C2XS' => 0 },
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'Variable::Magic' => 0.43,
        'Task::Weaken'  => 0,
        
    },
    OBJECT             => join(".o ", @modules) . ".o Registry.o",
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Hash-Registry-* '. $GENERATED_FILES },
);



sub MY::postamble {
    my $self = shift;
    my $perl = $self->{PERLRUN} ? '$(PERLRUN)' : '$(PERL)';
    my $package_name = 'Hash::Registry::XS::cfunc';
    my $module_name = 'Hash::Registry';
    #c2xs($module_name, $package_name, ".", { SRC_LOCATION => $HDR, AUTOWRAP => 1});
    return "$XSFILE: $HDR $modstring\n\t$perl genxs.pl $HDR $module_name $package_name"
}