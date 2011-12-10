package Ref::Store::Common;
use strict;
use warnings;
use base qw(Exporter);
use Carp qw(carp confess);
our (@EXPORT,%EXPORT_TAGS,@EXPORT_OK);

my @logfuncs;

$SIG{__DIE__} = \&confess;

BEGIN {
    @logfuncs = map { $_, $_ . 'f' } map { 'log_' . $_ }
        qw(warn crit info debug err);
}

use Module::Stubber
    'Log::Fu' => [ { level => "debug" } ],
    will_use => { map { $_ => \&carp } @logfuncs };

#Keep these in sync with hrdefs.h HR_HKEY_LOOKUP_
use Constant::Generate [qw(
    HR_TIDX_NULL
    HR_TIDX_SLOOKUP
    HR_TIDX_FLOOKUP
    HR_TIDX_RLOOKUP
    HR_TIDX_KEYTYPES
    HR_TIDX_ALOOKUP
    HR_TIDX_KEYFUNC
    HR_TIDX_UNKEYFUNC
    HR_TIDX_FLAGS
    HR_TIDX_PRIVDATA
)], export => 1;

use Constant::Generate [qw(
    HR_KFLD_STRSCALAR
    HR_KFLD_REFSCALAR
    HR_KFLD_TABLEREF
    HR_KFLD_ATTRHASH
    HR_KFLD_AVAILABLE
)], export => 1;

use Constant::Generate [qw(
    HR_REVERSE_KEYS
    HR_REVERSE_ATTRS
)], export => 1;

use Constant::Generate [qw(
    DUPIDX_RLOOKUP
    DUPIDX_FLOOKUP
    DUPIDX_ALOOKUP
    DUPIDX_SLOOKUP
)], -tag => 'pp_constants' => -export_ok => 1;

BEGIN {
    if(!$Module::Stubber::Status{'Log::Fu'}) {
        push @EXPORT, @logfuncs;
    }
}

1;