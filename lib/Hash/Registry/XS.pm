package Hash::Registry::XS::Key;
use strict;
use warnings;
use Hash::Registry::Common;
use Hash::Registry::XS::cfunc;

*new = \&HRXSK_new;
*kstring = \&HRXSK_kstring;
sub weaken_encapsulated { }
sub unlink_value { }
sub link_value {}


package Hash::Registry::XS::Key::Encapsulating;
use strict;
use warnings;
use Hash::Registry::XS::cfunc;

*new = \&HRXSK_encap_new;
*weaken_encapsulated = \&HRXSK_encap_weaken;
*link_value = \&HRXSK_encap_link_value;
*kstring = \&HRXSK_encap_kstring;
sub unlink_value { warn "This needs to be implmemented"; }

package Hash::Registry::XS;
use strict;
use warnings;
use base qw(Hash::Registry);
use Hash::Registry::XS::cfunc;
use Log::Fu;

sub new_key {
    my ($self,$scalar) = @_;
    if(!ref $scalar) {
        return HRXSK_new('Hash::Registry::XS::Key',
                     $scalar, $self->forward, $self->scalar_lookup);
    } else {
        return HRXSK_encap_new('Hash::Registry::XS::Key::Encapsulating',
                               $scalar, $self, $self->forward,
                               $self->scalar_lookup);
    }
}

sub dref_add_ptr {
    my ($self,$value,$hashref) = @_;
    HR_PL_add_action_ptr($value, $hashref);
}

sub dref_add_str {
    my ($self,$value,$hashref,$str) = @_;
    HR_PL_add_action_str($value,$hashref,$str);
}

sub dref_del_ptr {
    my ($self,$value,$hashref) = @_;
    HR_PL_del_action($value, $hashref);
}

1;