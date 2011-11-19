package Hash::Registry::XS::cfunc;
use strict;
use warnings;
use XSLoader;
our $VERSION = '0.01';

XSLoader::load 'Hash::Registry', $VERSION;

use base qw(Exporter);

our @EXPORT = qw(
    HR_PL_add_actions
    HR_PL_del_action
    HR_PL_add_action_ptr
    HR_PL_add_action_str
    HRXSK_new
    HRXSK_kstring
    HRXSK_encap_new
    HRXSK_encap_kstring
    HRXSK_encap_weaken
    HRXSK_encap_link_value
);
1;