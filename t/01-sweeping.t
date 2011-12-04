#!/usr/bin/perl
use strict;
use warnings;
use blib;
use Ref::Store::Sweeping;
use Test::More;
use Log::Fu { level => "debug" };
my $Impl = 'Ref::Store::Sweeping';
use Dir::Self;
use Data::Dumper;
$Ref::Store::Sweeping::SweepInterval = 1;

BEGIN {
    require(__DIR__ . '/common.pm');
}

my $lo = $Impl->new();
ok($lo, "Creation");

{
    my $v = ValueObject->new();
    my $k = KeyObject->new();
    $lo->store_sk($k, $v);
    #$lo->dump();
    #print Dumper($lo);
    $lo->sweep();
    is($lo->fetch_sk($k) + 0, $v +0, "Fetch");
}

$lo->sweep();
ok($lo->is_empty, "Everything clear");

{
    my $v = ValueObject->new();
    my $k = KeyObject->new();
    my $attr = '42';
    $lo->register_kt($attr);
    $lo->store_a($k, $attr, $v);
    ok(grep($v, $lo->fetch_a($k, $attr)), "Object attribute OK");
}
$lo->sweep();
ok($lo->is_empty, "Everything clear again");

$HRTests::Impl = $Impl;
#HRTests::test_all();
done_testing();