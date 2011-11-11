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

package Hash::Registry::PP;
use strict;
use warnings;
use Scalar::Util qw(weaken refaddr);
use base qw(Hash::Registry);
use Hash::Registry::PP::Magic;

use Log::Fu { level => "debug" };

our $Wizard = wizard(data => \&_wiz_data, free => \&_wiz_freehook);

sub kcls() { 'Hash::Registry::PP::Key' }

sub value_init {
    my ($self,$value) = @_;
    
    hr_pp_trigger_register($value, $value+0, $self->reverse);    
}

sub value_init_a {
    my ($self,$value,$attrhash) = @_;
    log_err("Hi!");
    hr_pp_trigger_register($value, $value+0, $attrhash);
}

sub value_deinit_a {
    my ($self,$value,$attrhash) = @_;
    hr_pp_trigger_unregister($value, $attrhash);
}

sub value_cleanup {
    my ($self,$value) = @_;
    
    hr_pp_trigger_unregister($value+0, $self->reverse);
}

sub impl_init {
    
}
1;