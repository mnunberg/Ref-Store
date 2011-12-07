package Ref::Store::Common;
use strict;
use warnings;
use base qw(Exporter);
use Carp qw(carp confess);
our @EXPORT;

my @logfuncs;

$SIG{__DIE__} = \&confess;

BEGIN {
    @logfuncs = map { $_, $_ . 'f' } map { 'log_' . $_ }
        qw(warn crit info debug err);
}

use Module::Stubber
    'Log::Fu' => [ { level => "debug" } ],
    will_use => { map { $_ => \&carp } @logfuncs };

use Constant::Generate [qw(
    HR_KFLD_STRSCALAR
    HR_KFLD_REFSCALAR
    HR_KFLD_TABLEREF
    HR_KFLD_AVAILABLE
)], export => 1;

use Constant::Generate [qw(
    HR_REVERSE_KEYS
    HR_REVERSE_ATTRS
)], export => 1;

BEGIN {
    if(!$Module::Stubber::Status{'Log::Fu'}) {
        push @EXPORT, @logfuncs;
    }
}

1;