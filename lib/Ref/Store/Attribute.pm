package Ref::Store::Attribute::TH;
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

sub DELETE {
    my ($hobj,$key) = @_;
    #log_err("DELETE!");
    delete $hobj->[TH_HASH]->{$key};
    if(!scalar %{$hobj->[TH_HASH]}) {
        delete $hobj->[TH_ATTR];
    }
}

sub CLEAR {
    my $hobj = shift;
    delete $hobj->[TH_ATTR];
}

package Ref::Store::Attribute;
use strict;
use warnings;
use Scalar::Util qw(weaken isweak);
use Ref::Store::Common;
use Data::Dumper;
use Log::Fu;

my $TIEPKG = __PACKAGE__ . "::TH";

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
        ($scalar, $ref, $table, $href, \%h);
    
    #log_errf("(%d) ATTR[%s %s]",$self,  $scalar, $ref);
    return $self;
}

sub link_value { }

sub unlink_value {
    my ($self,$value) = @_;
    return unless delete $self->[HR_KFLD_TIEOBJ]->{$value+0};    
    $self->[HR_KFLD_TABLEREF]->dref_del_ptr(
        $value,
        $self->[HR_KFLD_LOOKUP]->[0],
        $value + 0,
    );
}

sub weaken_encapsulated {
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

sub kstring {
    my $self = shift;
    $self->[HR_KFLD_STRSCALAR];
}

sub dump {
    my ($self,$hrd) = @_;
    my $h = $self->[HR_KFLD_LOOKUP]->[0];
    foreach my $v (values %$h) {
        $hrd->iprint("V: %s", $hrd->fmt_ptr($v));
    }
}

sub DESTROY {
    my $self = shift;
    #log_errf("%d: BYE", $self+0);
    my $h = $self->[HR_KFLD_LOOKUP]->[0];
    my $table = $self->[HR_KFLD_TABLEREF];
    return unless $table;
    #log_err("Will iterate over contained values..");
    foreach my $v (values %$h) {
        #log_errf("Deleting reverse entry %d { %d }", $v+0, $self+0);
        delete $table->reverse->{$v+0}->{$self+0};
        $table->dref_del_ptr($v, $h, $v+0);
    }
    delete $table->attr_lookup->{ $self->[HR_KFLD_STRSCALAR] };
}

package Ref::Store::Attribute::Encapsulating;
use strict;
use warnings;
use base qw(Ref::Store::Attribute);
use Scalar::Util qw(weaken);
use Ref::Store::Common;
use Log::Fu;

sub new {
    my ($cls,$astr,$encapsulated,$table) = @_;
    my $self = $cls->SUPER::new($astr, $encapsulated, $table);
    $self->_init_encapsulated($encapsulated, $astr, $table);
    return $self;
}

sub _init_encapsulated {
    my ($self,$encapsulated,$astr,$table) = @_;
    $table->dref_add_str($encapsulated, $table->attr_lookup, $astr);
    $table->dref_add_str($encapsulated, $self->[$self->HR_KFLD_LOOKUP], "1");
}

sub _deinit_encapsulated {
    my $self = shift;
    return unless $self->[HR_KFLD_REFSCALAR];
    my $table = $self->[HR_KFLD_TABLEREF];
    my $encap = $self->[HR_KFLD_REFSCALAR];
    my $astr = $self->[HR_KFLD_STRSCALAR];
    
    $table->dref_del_ptr($encap, $table->attr_lookup, $astr);
    $table->dref_del_ptr($encap, $self->[$self->HR_KFLD_LOOKUP], "1");
}

sub weaken_encapsulated {
    my $self = shift;
    weaken($self->[HR_KFLD_REFSCALAR]);
}

sub link_value {
    my ($self,$value) = @_;
    my $vhash = $self->[HR_KFLD_TABLEREF]->reverse->{$value+0};
    weaken($vhash);
    weaken($self);
    $self->[HR_KFLD_TABLEREF]->dref_add_str(
        $self->[HR_KFLD_REFSCALAR], $vhash, $self + 0
    );
}

sub dump {
    my ($self,$hrd) = @_;
    $hrd->iprint("ENCAP: %s", $self->[HR_KFLD_REFSCALAR]);
    $self->SUPER::dump($hrd);
}

sub DESTROY {
    my $self = shift;
    #log_err("DESTROY!");
    use Data::Dumper;
    $self->SUPER::DESTROY();
    my $table = $self->[HR_KFLD_TABLEREF];
    my $astr = $self->[HR_KFLD_STRSCALAR];
    if($self->[HR_KFLD_REFSCALAR]) {
        
        #Remove dref from encapsulated object.
        $table->dref_del_ptr(
            $self->[HR_KFLD_REFSCALAR],
            $table->attr_lookup,
            $astr,
        );
        
        $table->dref_del_ptr(
            $self->[HR_KFLD_REFSCALAR],
            $self->[$self->HR_KFLD_LOOKUP],
            "1"
        );
        
    }
    
    while (my ($k,$v) = each %{$self->[$self->HR_KFLD_LOOKUP]->[0] }) {
        my $vhash = $table->reverse->{$k};
        delete $vhash->{$self+0};
        $table->dref_del_ptr($v, $self->get_hash, $v + 0);
        if(! scalar %$vhash) {
            delete $table->reverse->{$k};
            $table->dref_del_ptr($v, $table->reverse, $v + 0);
        }
    }
}