package Hash::Registry::Attribute::TH;
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
    delete $hobj->[TH_HASH]->{$key};
    if(!keys %{$hobj->[TH_HASH]}) {
        delete $hobj->[TH_ATTR];
    }
}

sub CLEAR {
    my $hobj = shift;
    delete $hobj->[TH_ATTR];
}

package Hash::Registry::Attribute;
use strict;
use warnings;
use Scalar::Util qw(weaken isweak);
use Hash::Registry::Common;
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
        
    return $self;
}

sub unlink_value {
    my ($self,$value) = @_;
    return unless delete $self->[HR_KFLD_LOOKUP]->[0]->{$value+0};
    
    $self->[HR_KFLD_TABLEREF]->dref_del_ptr(
        $value, $self->[HR_KFLD_LOOKUP]->[0]);
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

sub DESTROY {
    my $h = $_[0]->[HR_KFLD_LOOKUP]->[0];
    my $table = $_[0]->[HR_KFLD_TABLEREF];
    return unless $table;

    map { $table->dref_del_ptr($_, $h) } values %$h;
    #log_err("DELETING USTR:", $_[0]->[HR_KFLD_STRSCALAR]);
    delete $table->attr_lookup->{ $_[0]->[HR_KFLD_STRSCALAR] };
}

package Hash::Registr::Attribute::Encapsulating;
use strict;
use warnings;
use base qw(Hash::Registry::Attribute);
use Scalar::Util qw(weaken);
use Hash::Registry::Common;

sub new {
    my ($cls,$astr,$encapsulated,$table) = @_;
    my $self = $cls->SUPER::new($astr, $encapsulated, $table);
    
    $table->dref_add_str($encapsulated, $table->attr_lookup, $astr);
}

sub weaken_encapsulated {
    my $self = shift;
    weaken($self->[HR_KFLD_REFSCALAR]);
}

sub DESTROY {
    my $self = shift;
    $self->SUPER::DESTROY();
    if($self->[HR_KFLD_REFSCALAR]) {
        
        #Remove dref from encapsulated object.
        
        $self->[HR_KFLD_TABLEREF]->dref_del_ptr(
            $self->[HR_KFLD_REFSCALAR], $self->[HR_KFLD_STRSCALAR]);
        
    }
}