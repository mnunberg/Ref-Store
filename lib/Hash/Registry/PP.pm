package Hash::Registry::PP::Key;
use strict;
use warnings;
use Scalar::Util qw(weaken refaddr);
use Hash::Registry::Common;
use Hash::Registry::PP::Magic;

use base qw(Hash::Registry::Key);

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

package Hash::Registry::PP::Key::Encapsulating;
use strict;
use warnings;
use base qw(Hash::Registry::PP::Key);
use Hash::Registry::Common;
use Hash::Registry::PP::Magic;
use Scalar::Util qw(weaken isweak);
use Log::Fu;
use constant {
    HR_KFLD_VHREF => HR_KFLD_AVAILABLE() + 1
};
use Internals qw(GetRefCount);
use Devel::Peek qw(Dump);

sub new {
    my ($cls,$obj,$table) = @_;
    my $self = [];
    @{$self}[HR_KFLD_STRSCALAR, HR_KFLD_REFSCALAR, HR_KFLD_TABLEREF] =
        ($obj+0, $obj, $table);
    
    
    hr_pp_trigger_register($obj, $obj+0, $table->scalar_lookup);
    
    weaken($table->scalar_lookup->{$obj+0} = $self);
    
    bless $self, $cls;
    return $self;
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
    hr_pp_trigger_unregister($obj, $self->[HR_KFLD_TABLEREF]->reverse->{$value+0});
}

sub weaken_encapsulated {
    my $self = shift;
    log_warn("Weakening..");
    weaken($self->[HR_KFLD_REFSCALAR]);
    log_warnf("Weak?=%d", isweak($self->[HR_KFLD_REFSCALAR]));
    log_warnf("Weak?=%d", isweak(
                                 $self->[HR_KFLD_TABLEREF]->scalar_lookup->
                                 {$self->[HR_KFLD_STRSCALAR]}));
}


sub kstring {
    my $self = shift;
    $self->[HR_KFLD_STRSCALAR];
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
    log_info("HI");
    my $self = shift;
    my $table = $self->[HR_KFLD_TABLEREF];
    my $obj = $self->[HR_KFLD_REFSCALAR];
    my $obj_s = $self->[HR_KFLD_STRSCALAR];
    
    delete $table->scalar_lookup->{$obj_s};
    my $stored = delete $table->forward->{$obj_s};
    
    if($obj) {
        log_info("Unregistering triggers on $obj");
        hr_pp_trigger_unregister($obj, $table->scalar_lookup);
        #hr_pp_trigger_unregister($obj, $table->forward);
        log_info("Done");
    }
    
    log_info("Found stored.. $stored", $stored+0);
    
    return unless $stored;
    my $stored_privhash = $table->reverse->{$stored+0};
    
    if($stored && $obj) {
        hr_pp_trigger_unregister($obj, $stored_privhash);
    }
    
    log_info("STRSCALAR=", $self->[HR_KFLD_STRSCALAR]);
    delete $stored_privhash->{$self->[HR_KFLD_STRSCALAR]};
    
    if(!scalar %$stored_privhash) {
        log_info("Table empty!");
        delete $table->reverse->{$stored+0};
        hr_pp_trigger_unregister($stored, $table->reverse);
    } else {
        print Dumper($stored_privhash);
        Dump($stored_privhash);
    }
    log_info("Done");
}

package Hash::Registry::PP;
use strict;
use warnings;
use Scalar::Util qw(weaken refaddr);
use base qw(Hash::Registry);
use Hash::Registry::PP::Magic;

use Log::Fu { level => "debug" };

sub new_key {
    my ($self,$ukey) = @_;
    my $cls = ref $ukey ? 'Hash::Registry::PP::Key::Encapsulating' :
        'Hash::Registry::PP::Key';
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
    my ($self,$value,$target) = @_;
    hr_pp_trigger_unregister($value,$target);
}

1;