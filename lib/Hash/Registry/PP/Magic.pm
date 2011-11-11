package Hash::Registry::PP::Magic;
use strict;
use warnings;
use Variable::Magic qw(cast dispell wizard getdata);
use Scalar::Util qw(weaken refaddr);
use base qw(Exporter);
use Data::Dumper;
use Log::Fu;


our @EXPORT = qw(
    hr_pp_trigger_register
    hr_pp_trigger_free
    hr_pp_trigger_unregister
);

our $Wizard = wizard(
    data => sub { $_[1] },
    free => \&trigger_fire
);

sub trigger_fire {
    my ($ref,$actions) = @_;
    log_err("FIRE:$ref");
    foreach (@$actions) {
        my ($key,$target) = @$_;
        if(!$target) {
            log_warn("Target undefined for $key");
        } else {
            log_warn("Have target=$target");
        }
        next unless $target;
        #print Dumper($target);
        delete $target->{$key};
    }
    @$actions = ();
}

sub hr_pp_trigger_unregister {
    my ($ref,$what) = @_;
    #log_err("UNREGISTER $ref:$what");
    my $actions = &getdata($ref, $Wizard);
    return unless $actions;
    my $i = $#{$actions};
    while($i >= 0) {
        my ($key,$target) = @{$actions->[$i]};
        if($target == $what) {
            splice(@{$actions}, $i);
            last;
        }
    }
    
    if(!@$actions) {
        &dispell($ref, $Wizard);
    }    
}
use Carp qw(cluck);
sub hr_pp_trigger_register {
    
    my ($ref,$key,$target) = @_;
    
    log_errf("$ref: KEY=$key, TARGET=$target");
    #cluck("Hi!");
    my $data = &getdata($ref, $Wizard);
    if(!$data) {
        log_err("No data. Casting");
        $data = [ ];
        &cast($ref, $Wizard, $data);
        push @$data, [$key, $target];
        return;
    }
    
    foreach (@$data) {
        my ($ekey,$etarget) = @$_;
        if ($target == $etarget) {
            log_warn("DUP!");
            return;
        }
    }
    push @$data, [$key, $target];
}

1;