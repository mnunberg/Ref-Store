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

sub reset_counter {
    my $self = shift;
    no strict 'refs';
    ${ref($self) . "::Counter" } = 0;
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
    $hash->store_sk($key, $obj);
    is($hash->fetch_sk($key), $obj, "Simple retrieval");
    $hash->purge($obj);
    ok(!$hash->fetch_sk($key), "Item deleted by value");
    my @keys = qw(Key1 Key2 Key3);
    foreach (@keys) {
        $hash->store_sk($_, $obj);
    }
    
    {
        my @otmp;
        foreach (@keys) {
            push @otmp, $hash->fetch_sk($_);
        }
        is(scalar grep($_ == $obj, @otmp),
           scalar @keys, "Multi-key lookup");
        my $ktmp = pop @keys;
        $hash->unlink_sk($ktmp);
        ok(!$hash->fetch_sk($ktmp), "Single key deletion");
        $hash->purgeby_sk(shift @keys);
        ok(!$hash->fetch_sk(shift @keys), "Delete by single key");
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
    
    $hash->dissoc_a(42, $t, $v);
    ok(!$hash->has_value($v), "Value automatically deleted");
    ok(!$hash->has_attr(42, $t), "Attribute automatically deleted");
    my $v2 = ValueObject->new();
    
    $hash->store_a(42, $t, $v);
    $hash->store_a(42, $t, $v2);
    $hash->unlink_a(42, $t);
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
    $hash->dissoc_a($attr, $t, $v);
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
    
    #Test value GC
    $attr = KeyObject->new();
    $hash->store_a($attr, $t, $v);
    undef $v;
    ok(!($hash->has_value($v)||$hash->has_attr($attr,$t)),
       "Attribute object Value GC");
    #print Dumper($hash);
}

use constant {
    ATTR_FOO => '_attr_foo',
    ATTR_BAR => '_attr_bar',
    KEY_GAH  => '_key_gah',
    KEY_MEH  => '_key_meh'
};
sub test_chained_basic {
    my $hash = $Impl->new();
    
    ValueObject->reset_counter();
    KeyObject->reset_counter();
    
    my $nested_obj = ValueObject->new();
    my $key = 'first_key';
    
    $hash->store($key, $nested_obj);
    my $second_obj = ValueObject->new();
    $hash->store($nested_obj, $second_obj, StrongValue => 1);
    my $third_obj = ValueObject->new();
    $hash->store($second_obj, $third_obj, StrongValue => 1);
    $hash->register_kt(ATTR_FOO);
    $hash->register_kt(ATTR_BAR);
    $hash->store_a("1", ATTR_FOO, $third_obj);
    $hash->store_a("1", ATTR_FOO, $nested_obj);
    $hash->store_a("1", ATTR_BAR, $second_obj);
    $hash->store_a("1", ATTR_BAR, $third_obj);
    #undef $nested_obj;
    undef $second_obj;
    undef $third_obj;
    #print Dumper($hash);
}

sub test_all {
    eval "require $Impl";
    test_scalar_key();
    test_multiple_hashes();
    test_object_keys();
    test_object_keys2();
    test_scalar_attr();
    test_object_attr();
    test_chained_basic();
    done_testing();
}
1;