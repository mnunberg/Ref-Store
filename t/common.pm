package _ObjBase;
use strict;
use warnings;

sub new {
    my ($cls,%opts) = @_;
    no strict 'refs';
    my $counter_vref = \${$cls."::Counter"};
    my $v = $$counter_vref;
    my $self = \$v;
    $$counter_vref++;
    bless $self, $cls;
}

@ValueObject::ISA = qw(_ObjBase);
@KeyObject::ISA = qw(_ObjBase);


package HRTests;
use Scalar::Util qw(weaken isweak);
use Test::More;
use Data::Dumper;

our $Impl;

sub test_scalar_key {
    my $hash = $Impl->new();
    my $key = "Hello";
    my @object_list;
    my $obj = ValueObject->new();
    push @object_list, $obj;
    $hash->store($key, $obj);
    is($hash->fetch($key), $obj, "Simple retrieval");
    $hash->delete_value($obj);
    ok(!$hash->fetch($key), "Item deleted by value");
    my @keys = qw(Key1 Key2 Key3);
    foreach (@keys) {
        $hash->store($_, $obj);
    }
    
    {
        my @otmp;
        foreach (@keys) {
            push @otmp, $hash->fetch($_);
        }
        is(scalar grep($_ == $obj, @otmp),
           scalar @keys, "Multi-key lookup");
        my $ktmp = pop @keys;
        $hash->delete_key_lookup($ktmp);
        ok(!$hash->fetch($ktmp), "Single key deletion");
        $hash->delete_value_by_key(shift @keys);
        ok(!$hash->fetch(shift @keys), "Delete by single key");
    }
    weaken($obj);
    $hash->store("Key", $obj);
    @object_list = ();
    ok(!$hash->fetch("Key"), "Auto-deletion of keys");
}

sub test_multiple_hashes {
    my @hashes = (
        $Impl->new(),
        $Impl->new(),
    );
    my $obj = ValueObject->new();
    foreach (@hashes) {
        $_->store("Key", $obj);
    }
    my $results = 0;
    foreach (@hashes) {
        if($_->fetch("Key") == $obj) {
            $results++;
        }
    }
    is($results, 2, "Storage in multiple HR objects");
}

sub test_all {
    eval "require $Impl";
    test_scalar_key();
    test_multiple_hashes();
    done_testing();
}
1;