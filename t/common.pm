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
use Log::Fu;
use Internals qw(GetRefCount);
use Devel::Peek qw(Dump);

sub test_object_keys {
    my $hash = $Impl->new();
    my $v = ValueObject->new();
    
    {
        my $key = KeyObject->new();
        $hash->store($key, $v);
        is($hash->fetch($key), $v, "Object key matching");
    }
    #print Dumper($hash);
    ok(!$hash->has_value($v),  "Object key GC");
    
    #Try key GC with value going out of scope
}

sub test_object_keys2 {
    my $hash = $Impl->new();
    my $key2 = KeyObject->new();
    {
        my $v2 = ValueObject->new();
        $hash->store($key2, $v2);
    }
    ok(!$hash->has_key($key2), "Value (OKEY) GC");
    
}

sub test_scalar_attr {
    my $hash = $Impl->new;
    my $t = "my_attribute";
    my $v = ValueObject->new();
    $hash->register_kt($t);
    $hash->store_a(42, $t, $v);
    ok(grep ($v, $hash->fetch_a(42, $t)), "Attr store");
    {
        my $v2 = ValueObject->new();
        $hash->store_a(42, $t, $v2);
        my @stored = $hash->fetch_a(42, $t);
        is(@stored, 2, "Added new value to attribute");
    }
    is($hash->fetch_a(42, $t), 1, "Value GC from attr collection");
    
    $hash->delete_attr_from_value(42, $t, $v);
    ok(!$hash->has_value($v), "Value automatically deleted");
    ok(!$hash->has_attr(42, $t), "Attribute automatically deleted");
    my $v2 = ValueObject->new();
    
    $hash->store_a(42, $t, $v);
    $hash->store_a(42, $t, $v2);
    $hash->delete_attr_from_all(42, $t);
    ok(!($hash->has_attr(42, $t) || $hash->has_value($v) || $hash->has_value($v2)),
       "Totally deleted!");
}

sub test_object_attr {
    my $hash = $Impl->new();
    my $t = "OBJECT_ATTRIBUTE_";
    $hash->register_kt($t);
    my $v = ValueObject->new();
    my $attr = KeyObject->new();
    $hash->store_a($attr, $t, $v);
    ok(grep($v, $hash->fetch_a($attr, $t)), "Object attribute fetch");
    #print Dumper($hash);
    $hash->delete_attr_from_value($attr, $t, $v);
    ok(!($hash->has_attr($attr,$t)||$hash->has_value($v)), "Object attribute deletion");
    #print Dumper($hash);
    
    diag "Destroying $attr";
    undef $attr;
    
    diag "Trying object GC";
    {
        my $tmpattr = KeyObject->new();
        $hash->store_a($tmpattr, $t, $v);
    }
    ok(!$hash->has_value($v), "Attribute object GC");
    #print Dumper($hash);
    #log_err("Hi!");
}

sub test_all {
    eval "require $Impl";
    test_scalar_key();
    test_multiple_hashes();
    test_object_keys();
    test_object_keys2();
    test_scalar_attr();
    test_object_attr();
    done_testing();
}
1;