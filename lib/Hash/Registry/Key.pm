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

sub unlink_value {
    #Pass, we don't need to do anything.
    #The key object is destroyed and magic is invoked
    #on the remaining scalar and forward entries
}

sub link_value {
    #Nothing here, either
}

package Hash::Registry::Key::Encapsulating;
use strict;
use warnings;
use Scalar::Util qw(weaken);
use Hash::Registry::Common;
use base qw(Hash::Registry::Key);

sub DESTROY {
    my $self = shift;
}

1;