package _ObjBase;
use strict;
use warnings;
my $can_use_threads = eval 'use threads; 1';

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
use Ref::Store::Common;
use Scalar::Util qw(weaken isweak);
use Test::More;
use Data::Dumper;
use Log::Fu;
use Devel::Peek qw(Dump);

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
    
    #use Data::Dumper;
    #print Dumper($hash);
    
    ok(!$hash->has_attr(42, $t), "Attribute automatically deleted");
    my $v2 = ValueObject->new();
    
    $hash->store_a(42, $t, $v);
    $hash->store_a(42, $t, $v2);
    $hash->unlink_a(42, $t);
    ok(!($hash->has_attr(42, $t) || $hash->has_value($v) || $hash->has_value($v2)),
       "Totally deleted!");
    #print Dumper($hash);
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
    #print Dumper($hash);
    
    #Test value GC
    $attr = KeyObject->new();
    $hash->store_a($attr, $t, $v);
    undef $v;
    ok(!($hash->has_value($v)||$hash->has_attr($attr,$t)),
       "Attribute object Value GC");
    #print Dumper($hash);
    diag "Attribute tests done";
}

use constant {
    ATTR_FOO => '_attr_foo',
    ATTR_BAR => '_attr_bar',
    KEY_GAH  => '_key_gah',
    KEY_MEH  => '_key_meh'
};
sub test_chained_basic {
    diag "Chained tests";
    my $hash = $Impl->new();
    
    ValueObject->reset_counter();
    KeyObject->reset_counter();
    
    my $nested_obj = ValueObject->new();
    my $key = 'first_key';
    
    {
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
    }
    $Data::Dumper::Useqq = 1;
    #print Dumper($hash);
    #print $hash->dump();
    undef $nested_obj;
    ok($hash->is_empty(), "Nested deletion OK");
    #$hash->dump();
    #undef $second_obj;
    #undef $third_obj;
    #print Dumper($hash);
}

sub test_oexcl {
    my $h = $Impl->new();
    my $v = \time();
    $h->store("foo", $v);
    my $v2 = \time();
    eval {
        $h->store("foo", $v2);
    };
    ok($@, "Error for duplicate insertion ($@)");
}

sub test_threads {
    if(!$can_use_threads) {
        diag "Not testing threads. Couldn't load threads.pm";
        return;
    }
    diag "Testing threads (String keys)";
    my $table = $Impl->new();
    my $v = ValueObject->new();
    my $k = "some_key";
    $table->store_sk($k, $v);
    my $k2 = "other_key";
    $table->store_sk($k2, $v);
    #$table->dump();
    
    my $fn = sub {
        #$table->dump();
        my $res = $table->fetch_sk($k) == $v && $table->fetch_sk($k2) == $v;
        return $res;
    };
    my $thr = threads->create($fn); #line displaying message
    ok($fn->(), "Same thing works in the parent!");
    ok($thr->join(), "Thread duplication");
    #undef $thr;
    
    ############################################################################
    diag "Testing threads (object keys)";
    
    my $ko = KeyObject->new();
    $table->store_sk($ko, $v);
    
    $fn = sub {
        my $ret = $table->fetch_sk($ko) == $v;
        return $ret;
    };
    
    $thr = threads->create($fn);
    ok($fn->(), "Object keys working");
    ok($thr->join(),"Thread duplication for encapsulated object keys");
    #undef $thr;
    
    diag "Testing thread duplication with dual (key and/or value) objects";
    #undef $table;
    #$table = $Impl->new();
    my $k_first = KeyObject->new();
    my $v_first = ValueObject->new();
    my $v_second = ValueObject->new();
    
    $table->store_sk($k_first, $v_first);
    $table->store_sk($v_first, $v_second);
    
    $fn = sub {
        $table->fetch_sk($k_first) == $v_first &&
            $table->fetch_sk($v_first) == $v_second
    };
    
    $thr = threads->create($fn);
    ok($fn->(), "Ok in parent");
    ok($thr->join(), "Ok in thread!");
    
    diag "About to undef table";
    
    $table->purge($_) foreach ($k_first,$v_first,$v_second);
    undef $table;
    
    $table = $Impl->new();
    
    diag "Will test attributes";
    $table->register_kt("ATTR");
    $table->store_a(1, "ATTR", $v);
    
    $thr = threads->create(sub{
        grep $v, $table->fetch_a(1, 'ATTR')
    });
    ok($thr->join(), "Got value from attribute store");

    $table->register_kt('ATTROBJ');
    $table->store_a($v_first, 'ATTROBJ', $v);
    $table->store_a($v_first, 'ATTROBJ', $v_second);

    $thr = threads->create(sub{
            grep($v, $table->fetch_a($v_first, 'ATTROBJ')) &&
            grep($v_second, $table->fetch_a($v_first, 'ATTROBJ'))
    });

    ok($thr->join(), "Attribute Object");

    diag("Returning..");
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
    test_oexcl();
    done_testing();
}
1;
