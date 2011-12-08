package Ref::Store::PP::Key;
use strict;
use warnings;
use Scalar::Util qw(weaken refaddr);
use Ref::Store::Common;
use Carp::Heavy;
use Ref::Store::PP::Magic;

use base qw(Ref::Store::Key);

sub new {
    my ($cls,$scalar,$table) = @_;
    
    my $self = [];
    @{$self}[HR_KFLD_STRSCALAR, HR_KFLD_REFSCALAR, HR_KFLD_TABLEREF] =
        ("$scalar", $scalar, $table);
    bless $self, $cls;
    
    $table->scalar_lookup->{$scalar} = $self;
    weaken($table->scalar_lookup->{$scalar});
    
    hr_pp_trigger_register($self, "$scalar", $table->forward);
    hr_pp_trigger_register($self, "$scalar", $table->scalar_lookup);
    return $self;
}

sub ithread_predup {
    #Perl data structures are still valid here..
}

sub ithread_postdup {
    #PP::Magic information is dup'd as well, nothing for us here. Key is static
}

package Ref::Store::PP::Key::Encapsulating;
use strict;
use warnings;
use base qw(Ref::Store::PP::Key);
use Ref::Store::Common;
use Ref::Store::Common qw(:pp_constants);
use Ref::Store::PP::Magic;
use Scalar::Util qw(weaken isweak);
use Log::Fu;
use constant {
    HR_KFLD_VHREF => HR_KFLD_AVAILABLE() + 1
};
use Devel::Peek qw(Dump);

sub new {
    my ($cls,$obj,$table) = @_;
    my $self = [];
    @{$self}[HR_KFLD_STRSCALAR, HR_KFLD_REFSCALAR, HR_KFLD_TABLEREF] =
        ($obj+0, $obj, $table);
    
    #log_err("Creating new encapsulating key for object", $obj+0);
    hr_pp_trigger_register($obj, $obj+0, $table->scalar_lookup);
    
    weaken($table->scalar_lookup->{$obj+0} = $self);
    
    bless $self, $cls;
    return $self;
}

my $DUPKEY_KENCAP_PFIX = '__PP_KENCAP:';
my $DUPKEY_LINFO_PFIX = '__PP_OLD_LOOKUPS:';

sub ithread_predup {
    my ($self,$ptr_map,$value) = @_;
    $ptr_map->{
        $DUPKEY_KENCAP_PFIX . $self->[HR_KFLD_STRSCALAR]
    } = $value + 0;
}

sub ithread_postdup {
    my ($self,$ptr_map,$old_taddr) = @_;
    
    my $obj = $self->[HR_KFLD_REFSCALAR];
    my $old_objaddr = $self->[HR_KFLD_STRSCALAR];
    
    hr_pp_trigger_replace_key(
        $obj, $old_objaddr, $self->[HR_KFLD_TABLEREF]->scalar_lookup,
        $obj + 0);
    
    my $old_vaddr = $ptr_map->{
        $DUPKEY_KENCAP_PFIX . $self->[HR_KFLD_STRSCALAR] };
    my $vhash = $ptr_map->{
        $DUPKEY_LINFO_PFIX . $old_taddr}->[DUPIDX_RLOOKUP]->{$old_vaddr};
    
    hr_pp_trigger_replace_key(
        $obj, $old_objaddr, $vhash,
        $obj + 0);
    
    $self->[HR_KFLD_STRSCALAR] = $obj + 0;
}

sub link_value {
    my ($self,$value) = @_;
    my $obj = $self->[HR_KFLD_REFSCALAR];
    my $stored_privhash = $self->[HR_KFLD_TABLEREF]->reverse->{$value+0};
    hr_pp_trigger_register($obj, $obj+0, $stored_privhash);
}

sub unlink_value {
    my ($self,$value) = @_;
    my $obj = $self->[HR_KFLD_REFSCALAR];
    hr_pp_trigger_unregister($obj,
                             $self->[HR_KFLD_TABLEREF]->reverse->{$value+0},
                             $obj + 0
                             );
}

sub exchange_value {
    my ($self,$old,$new) = @_;
    $self->unlink_value($old);
    $self->link_value($new);
}


sub weaken_encapsulated {
    my $self = shift;
    weaken($self->[HR_KFLD_REFSCALAR]);
}


sub kstring {
    my $self = shift;
    $self->[HR_KFLD_STRSCALAR];
}

sub dump {
    my ($self,$hrd) = @_;
    $hrd->iprint("ENCAP: %s", $hrd->fmt_ptr($self->[HR_KFLD_REFSCALAR]));
}

#This is called:

# 1) When the reverse value entry is deleted:
#   ACTION: clean up encapsulated object magic
#
# 2) When the object itself has triggered
#   A deletion from the value's reverse entry.
#   ACTION: 

use Data::Dumper;

sub DESTROY {
    my $self = shift;
    my $table = $self->[HR_KFLD_TABLEREF];
    my $obj = $self->[HR_KFLD_REFSCALAR];
    my $obj_s = $self->[HR_KFLD_STRSCALAR];
    
    delete $table->scalar_lookup->{$obj_s};
    my $stored = delete $table->forward->{$obj_s};
    
    if($obj) {
        #log_info("Unregistering triggers on $obj");
        hr_pp_trigger_unregister($obj, $table->scalar_lookup, $obj_s);
        #hr_pp_trigger_unregister($obj, $table->forward);
        #log_info("Done");
    }
    
    #log_info("Found stored.. $stored", $stored+0);
    
    return unless $stored;
    my $stored_privhash = $table->reverse->{$stored+0};
    
    if($stored && $obj) {
        hr_pp_trigger_unregister($obj, $stored_privhash, $obj_s);
    }
    
    #log_info("STRSCALAR=", $self->[HR_KFLD_STRSCALAR]);
    delete $stored_privhash->{$self->[HR_KFLD_STRSCALAR]};
    
    if(!scalar %$stored_privhash) {
        #log_info("Table empty!");
        delete $table->reverse->{$stored+0};
        hr_pp_trigger_unregister($stored, $table->reverse, $obj_s);
    }
    #else {
    #    print Dumper($stored_privhash);
    #    Dump($stored_privhash);
    #}
    #log_info("Done");
}



package Ref::Store::PP;
use strict;
use warnings;
use Scalar::Util qw(weaken refaddr);
use base qw(Ref::Store);
use Ref::Store::PP::Magic;
use Ref::Store::Common qw(:pp_constants);


use Log::Fu { level => "debug" };

sub new_key {
    my ($self,$ukey) = @_;
    my $cls = ref $ukey ? 'Ref::Store::PP::Key::Encapsulating' :
        'Ref::Store::PP::Key';
    $cls->new($ukey, $self);
}

sub dref_add {
    my ($self,$value,$target,$key) = @_;
    $key ||= $value+0;
    hr_pp_trigger_register($value, $key, $target);
}

sub dref_del {
    my ($self,$value,$target) = @_;
    hr_pp_unregister($value, $target);
}

sub dref_add_str {
    my ($self,$value,$target,$key) = @_;
    hr_pp_trigger_register($value, $key, $target);
}

sub dref_add_ptr {
    my ($self,$value,$target) = @_;
    hr_pp_trigger_register($value, $value+0, $target);
}

sub dref_del_ptr {
    my ($self,$value,$target,$mkey) = @_;
    hr_pp_trigger_unregister($value,$target,$mkey);
}

sub ithread_store_lookup_info {
    my ($self,$ptr_map) = @_;
    my @Linfo;
    @Linfo[DUPIDX_SLOOKUP,DUPIDX_ALOOKUP,DUPIDX_FLOOKUP,DUPIDX_RLOOKUP] =
        ($self->scalar_lookup,$self->attr_lookup,$self->forward,$self->reverse);
    $ptr_map->{
        $DUPKEY_LINFO_PFIX . ($self + 0)
    } = \@Linfo;
}

1;