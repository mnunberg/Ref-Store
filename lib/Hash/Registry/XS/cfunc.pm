package Hash::Registry::XS::cfunc;
use strict;
use warnings;
use XSLoader;
our $VERSION = '0.01';

XSLoader::load 'Hash::Registry', $VERSION;

use base qw(Exporter);

our @EXPORT = qw(
    HR_PL_add_action_ptr
    HR_PL_add_action_str
    
    HR_PL_del_action_container
    HR_PL_del_action_str
    HR_PL_del_action_ptr
    
    HRXSK_new
    HRXSK_kstring
    HRXSK_encap_new
    HRXSK_encap_kstring
    HRXSK_encap_weaken
    HRXSK_encap_link_value
    HRXSK_encap_getencap
    
	HRA_store_sk
	HRA_fetch_sk
    
    HRA_store_a
    HRA_fetch_a
    HRA_dissoc_a
    HRA_unlink_a
    HRA_attr_get
    
    HRXSATTR_unlink_value
    HRXSATTR_get_hash
    HRXSATTR_kstring
);
1;
