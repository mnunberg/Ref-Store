package Ref::Store::PP::Magic;
use strict;
use warnings;
use Variable::Magic qw(cast dispell wizard getdata);
use Scalar::Util qw(weaken refaddr reftype);
use base qw(Exporter);
use Data::Dumper;
use Log::Fu;


our @EXPORT = qw(
    hr_pp_trigger_register
    hr_pp_trigger_free
    hr_pp_trigger_unregister
    hr_pp_purge
);

our $Wizard = wizard(
    data => sub { $_[1] },
    free => \&trigger_fire
);

sub hr_pp_purge {
    my ($ref) = @_;
    &dispell($ref, $Wizard);
}


sub trigger_fire {
    #log_err("FIRE!");
    my ($ref,$actions) = @_;
    foreach (@$actions) {
        my ($key,$target) = @$_;
        next unless $target;
        if(reftype $target eq 'HASH') {
            delete $target->{$key};
        } elsif (reftype $target eq 'ARRAY') {
            delete $target->[$key];
        } else {
            die "Unknown target $target";
        }
        #log_warnf("DELETE $target : $key");
    }
    @$actions = ();
}

sub hr_pp_trigger_unregister {
    my ($ref,$what,$mkey) = @_;
    my $actions = &getdata($ref, $Wizard);
    return unless $actions;
    my $i = $#{$actions};
    while($i >= 0) {
        my ($key,$target) = @{$actions->[$i]};
        if(defined $target && $target eq $what && $key eq $mkey) {
            splice(@{$actions}, $i);
            last;
        }
        $i--;
    }
    
    if(!@$actions) {
        &dispell($ref, $Wizard);
    }    
}
use Carp qw(cluck);
use Scalar::Util qw(weaken isweak);
sub hr_pp_trigger_register {
    
    my ($ref,$key,$target) = @_;
    
    #log_errf("$ref: KEY=$key, TARGET=$target");
    #cluck("Hi!");
    my $data = &getdata($ref, $Wizard);
    if(!$data) {
        #log_err("No data. Casting");
        $data = [ ];
        &cast($ref, $Wizard, $data);
        my $datum = [ $key, $target ];
        weaken($datum->[1]);
        weaken($datum->[0]) if ref $datum->[0];
        push @$data, $datum;
        return;
    }
    
    foreach (@$data) {
        my ($ekey,$etarget) = @$_;
        if (defined $etarget && defined $ekey &&
            $target == $etarget && $key eq $ekey) {
            #log_warn("DUP!");
            return;
        }
    }
    my $datum = [$key, $target];
    weaken($datum->[1]);
    weaken($datum->[0]) if ref $datum->[0];
    push @$data, $datum;
}

1;