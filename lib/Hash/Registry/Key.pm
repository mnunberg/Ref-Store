package Hash::Registry::Key;
use strict;
use warnings;
use Scalar::Util qw(weaken);
use Hash::Registry::Common;

#This is an attribute,

sub weaken_encapsulated {
    if(ref $_[0]->[HR_KFLD_REFSCALAR]) {
        weaken $_[0]->[HR_KFLD_REFSCALAR];
    }
}

sub kstring {
    $_[0]->[HR_KFLD_STRSCALAR];
}
1;