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

sub dump {
    my ($self,$hrd) = @_;
    $hrd->iprint("ENCAP: %s", $hrd->fmt_ptr($self->HRXSK_encap_getencap));
}

package Hash::Registry::XS::Attribute;
use strict;
use warnings;
use Hash::Registry::XS::cfunc;

*unlink_value   = \&HRXSATTR_unlink_value;
*get_hash       = \&HRXSATTR_get_hash;
*kstring        = \&HRXSATTR_kstring;

@Hash::Registry::XS::Attribute::Encapsulating::ISA
    = qw(Hash::Registry::XS::Attribute);

package Hash::Registry::XS;
use strict;
use warnings;
use base qw(Hash::Registry);
use Hash::Registry::XS::cfunc;
use Log::Fu;

#These two lines completely override the perl store/fetch code and utilize
#pure C! - double the speed

*store = *store_sk  = \&HRA_store_sk;
*fetch = *fetch_sk  = \&HRA_fetch_sk;

*store_a            = \&HRA_store_a;
*fetch_a            = \&HRA_fetch_a;
*dissoc_a           = \&HRA_dissoc_a;
*unlink_a           = \&HRA_unlink_a;
*attr_get           = \&HRA_attr_get;

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
    HR_PL_del_action_container($value, $hashref);
}


1;

__END__

=head1 NAME

Hash::Registry::XS - XS/C implementation of the H::R API

=head2 DESCRIPTION

No user serviceable parts inside.

This backend currently handles store, fetch, and back-delete operations entirely
in C, making it significantly fast.

Attributes are yet to be implemented