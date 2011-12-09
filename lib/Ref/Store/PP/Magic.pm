package Ref::Store::PP::Magic;
use strict;
use warnings;
use Variable::Magic qw(cast dispell wizard getdata);
use Scalar::Util qw(weaken refaddr reftype isweak);
use base qw(Exporter);
use Data::Dumper;
use Log::Fu;
use Devel::Peek;
use Devel::GlobalDestruction;

use Constant::Generate [qw(
    IDX_KEY
    IDX_TARGET
)];

our @EXPORT = qw(
    hr_pp_trigger_register
    hr_pp_trigger_free
    hr_pp_trigger_unregister
    hr_pp_trigger_replace_key
    hr_pp_purge
);

our $Wizard;

sub _init_wizard {
    $Wizard = wizard(
        data => sub { $_[1] },
        free => \&trigger_fire
    );
}

_init_wizard();

sub hr_pp_purge {
    my ($ref) = @_;
    &dispell($ref, $Wizard);
}

sub trigger_fire {
    #log_err("FIRE!");
    my ($ref,$actions) = @_;

    foreach (@$actions) {
        my ($key,$target) = @$_;
        next unless defined $target && defined $key;
        if(reftype $target eq       'HASH') {
            delete $target->{$key};
        } elsif (reftype $target eq 'ARRAY') {
            delete $target->[$key];
        } elsif (reftype $target eq 'CODE') {
            $target->($ref,$key);
        } else {
            die "Unknown target $target";
        }
    }
    @$actions = ();
}

sub hr_pp_trigger_unregister {
    my ($ref,$what,$mkey) = @_;
    
    if(!defined $what) {
        if(in_global_destruction) {
            return;
        }
        die("Container (what) must be defined");
    }
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
        &dispell($ref, $Wizard) if (defined $ref && ref $Wizard);
    }
}

sub hr_pp_trigger_register {
    
    my ($ref,$key,$target) = @_;    
    my $data = &getdata($ref, $Wizard);
    my $datum = [];
    @$datum[IDX_KEY,IDX_TARGET] = ($key,$target);
    weaken($datum->[IDX_TARGET]);
    weaken($datum->[IDX_KEY]) if ref $key;
    
    if(!$data) {
        $data = [ $datum ];
        &cast($ref, $Wizard, $data);
        return;
    }
    
    foreach (@$data) {
        my ($ekey,$etarget) = @$_;
        if (defined $etarget && defined $ekey &&
            $target == $etarget && $key eq $ekey) {
            return;
        }
    }
    push @$data, $datum;
}

use Carp qw(cluck);

#This one exists primarily for thread duplication
sub hr_pp_trigger_replace_key {
    my ($ref,$key,$target,$newkey) = @_;
        
    my $data = &getdata($ref,$Wizard);
    if(!$data) {
        cluck("");
        log_warn("No data yet? ($ref)");
        hr_pp_trigger_register($ref,$key,$target);
        log_warn("Casted!");
        return;
    }
    
    foreach (@$data) {
        my ($ekey,$etarget) = @$_;
        if($etarget == $target && $ekey eq $key) {
            $_->[IDX_KEY] = $key;
            weaken($_->[IDX_KEY]) if ref $key;
            return;
        }
    }
    hr_pp_trigger_register($ref,$key,$target);
}

1;
