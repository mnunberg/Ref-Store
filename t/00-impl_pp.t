#!/usr/bin/perl
use strict;
use warnings;
use Dir::Self;
BEGIN {
	require (__DIR__ . "/common.pm");
}


$HRTests::Impl = 'Ref::Store::PP';
HRTests::test_all();
