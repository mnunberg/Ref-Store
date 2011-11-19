#!/usr/bin/perl
use strict;
use warnings;
use Dir::Self;
BEGIN {
	require (__DIR__ . "/common.pm");
}

use Hash::Registry::XS;
$HRTests::Impl = 'Hash::Registry::XS';
HRTests::test_all();
