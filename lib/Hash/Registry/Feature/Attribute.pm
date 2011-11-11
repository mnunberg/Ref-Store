package Hash::Registry::Feature::Attribute::TH;
use strict;
use warnings;
use Scalar::Util qw(weaken);
use Log::Fu;
use Tie::Hash;
use base qw(Tie::ExtraHash);
use Exporter qw(import);
#TieHash fields
use Data::Dumper;
our @EXPORT = qw(TH_HASH TH_ATTR);

use constant {
    TH_HASH => 0,
    TH_ATTR => 1,
};

sub TIEHASH {
    my ($cls,$attrobj) = @_;
    bless [{}, $attrobj], $cls;
}

sub DELETE($$) {
    my ($hobj,$key) = @_;
    #log_err("IN DELETE: $key");
    delete $hobj->[TH_HASH]->{$key};
    if(!keys %{$hobj->[TH_HASH]}) {
        #log_err("Empty!");
        delete $hobj->[TH_ATTR];
    } else {
        #log_err("Hrmm.. what else do we have?");
    }
    print Dumper($hobj->[TH_HASH]);
}

sub CLEAR {
    weaken($_[0]->[TH_ATTR]);
}

sub DESTROY {
    log_err("Bye!");
}


package Hash::Registry::Feature::Attribute;
use strict;
use warnings;
use Scalar::Util qw(weaken isweak);
use Hash::Registry::Common;
use Data::Dumper;
use Log::Fu;

my $TIEPKG;
BEGIN {
    $TIEPKG = "Hash::Registry::Feature::Attribute::TH";
    $TIEPKG->import();
    Hash::Registry::Feature::Attribute::TH->import();
}

Hash::Registry::Feature::Attribute::TH->import();

#Attr/Key fields
use constant {
    HR_KFLD_LOOKUP  => HR_KFLD_AVAILABLE(), #hash for lookups,
    HR_KFLD_TIEOBJ  => HR_KFLD_AVAILABLE()+1
};

sub new {
    my ($cls,$scalar,$ref,$table) = @_;
    my $self = [];
    $#{$self} = HR_KFLD_LOOKUP;
    my $href = tie (my %h, $TIEPKG, $self);
    bless $self, $cls;
    
    @{$self}[HR_KFLD_STRSCALAR, HR_KFLD_REFSCALAR,
            HR_KFLD_TABLEREF, HR_KFLD_LOOKUP, HR_KFLD_TIEOBJ] =
        ("$scalar", $ref, $table, $href, \%h);
    
    print Dumper($self);
    return $self;
}

sub weaken_encapsulated {
    my $self = shift;
    if (ref $self->[HR_KFLD_REFSCALAR]) {
        weaken($self->[HR_KFLD_REFSCALAR]);
    }
}

sub store_weak {
    my ($self,$k,$v) = @_;
    weaken($self->[HR_KFLD_LOOKUP]->[0]->{$k} = $v);
}

sub store_strong {
    my ($self,$k,$v) = @_;
    $self->[HR_KFLD_LOOKUP]->[0]->{$k} = $v;
}

sub get_hash {
    $_[0]->[HR_KFLD_TIEOBJ];
}

sub DESTROY {
    log_err(Dumper(\@_));
    my $h = $_[0]->[HR_KFLD_LOOKUP]->[0];
    my $table = $_[0]->[HR_KFLD_TABLEREF];
    return unless $table;
    log_err($table);
    map { $table->value_deinit_a($_, $h) } values %$h;
    print Dumper($_[0]);
    delete $table->attr_lookup->{ $_[0]->[HR_KFLD_STRSCALAR] };
}

package Hash::Registry::Feature::Attributed;
use strict;
use warnings;
use Log::Fu;
use Scalar::Util qw(weaken isweak);

sub attrcls { 'Hash::Registry::Feature::Attribute' }

sub attr_get {
    my ($self,$attr,$t,%options) = @_;
    my $ustr = $self->keytypes->{$t} . $attr;
    log_err($ustr);
    my $aobj = $self->attr_lookup->{$ustr};
    return $aobj if $aobj;
    
    if(!$options{Create}) {
        return;
    }
    
    $aobj = $self->attrcls->new($ustr, $attr, $self);
    if($options{StrongAttr}) {
        $self->attr_lookup->{$ustr} = $aobj;
    } else {
        weaken($self->attr_lookup->{$ustr} = $aobj);
    }
    return $aobj;
}

sub store_a {
    my ($self,$attr,$t,$value,%options) = @_;
    
    my $aobj = $self->attr_get($attr, $t, Create => 1);    
    my $vaddr = $value + 0;
    
    $self->value_init_a($value, $aobj->get_hash);
    
    
    if(!$options{StrongValue}) {
        $aobj->store_weak($vaddr, $value);
    } else {
        $aobj->store_strong($vaddr, $value);
    }
}

sub fetch_a {
    my ($self,$attr,$t) = @_;
    my $aobj = $self->attr_get;
    return unless $aobj;
    values %{$aobj->get_hash};
}

#Given an attribute, remove the associated object entirely
sub delete_value_by_attr {
    my ($self,$attr,$t) = @_;
    my $value = $self->fetch_a($attr, $t);
    return unless $value;
    $self->delete_value($value);
}

#Dissociates a single attribute from a value
sub delete_attr_from_value {
    my ($self,$attr,$t,$value) = @_;
    my $aobj = $self->attr_get($attr, $t);
    return unless $aobj;
    if(!delete $aobj->get_hash->{$value+0}) {
        return;
    }
    $self->value_deinit_a($value, $aobj->get_hash);
}

#This removes the attribute entirely
sub delete_attr_from_all {
    my ($self,$attr,$t) = @_;
    my $aobj = $self->attr_get($attr, $t);
    return unless $aobj;
    map { $self->value_deinit_a($_, $aobj->get_hash) } values %{$aobj->get_hash};
}


1;
#We will not implement attributes_for_value. 