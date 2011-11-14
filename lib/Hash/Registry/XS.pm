package Hash::Registry::XS::cfunc;
use strict;
use warnings;
use File::Slurp qw(read_file);
use Dir::Self;
use base qw(Exporter);

my $CBLOB;
BEGIN {
    my $base_path = "/home/mordy/src/Hash-Registry/";
    my @filenames = qw(
        hreg.h
        hreg.c
        hr_hrimpl.c
        hr_pl.c
    );
    foreach my $file (@filenames) {
        $CBLOB .= sprintf("\n/* FILE: %s */\n", $file);
        $CBLOB .= read_file("$base_path/$file");
    }
    $CBLOB =~ s/^#include.+hreg\.h[">\s+]$//mgi;
}


use Inline
    C => Config =>
    NAME => 'hreg',
    CLEAN_AFTER_BUILD => 0,
    DIRECTORY   => './inline_build',
    #FORCE_BUILD => 1,
    BUILD_NOISY => 1
;
use Inline C => $CBLOB;

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

{
    no strict 'refs';
    my $cls = 'Hash::Registry::XS::Key';
    *{$cls.'::weaken_encapsulated'} = sub { };
    *{$cls.'::kstring'} = \&HRXSK_kstring;
    *{$cls.'::link_value'} = sub { };
    
    $cls .= '::Encapsulating';
    *{$cls.'::weaken_encapsulated'} = \&HRXSK_encap_weaken;
    *{$cls.'::kstring'} = \&HRXSK_encap_kstring;
    *{$cls.'::link_value'} = \&HRXSK_encap_link_value;
}

package Hash::Registry::XS::Key;
use strict;
use warnings;
use Scalar::Util qw(refaddr weaken);
use Devel::Peek;
use Data::Hexdumper qw(hexdump);
use Internals qw(SetRefCount GetRefCount);
use Hash::Registry::Common;
Hash::Registry::XS::cfunc->import();
use Log::Fu;

*new = \&HRXSK_new;
*kstring = \&HRXSK_kstring;

sub weaken_encapsulated { }
sub unlink_value { }


package Hash::Registry::XS;
use Scalar::Util qw(refaddr weaken);
use strict;
use warnings;
use base qw(Hash::Registry);
Hash::Registry::XS::cfunc->import();
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