#!/usr/bin/perl
use strict;
use warnings;

$ValueObject::ObjectCount = 0;
sub ValueObject::new {
	my $cls = shift;
	my $v = rand();
	$ValueObject::ObjectCount++;
	my $self = \$v;
	bless $self, $cls;
	return $self;
}

sub ValueObject::DESTROY {
	#log_warn("DESTROY!");
	$ValueObject::ObjectCount--;
}

package main;
use strict;
use warnings;
use Data::Dumper;
use Getopt::Long;
use Log::Fu { level=> "debug" };
use lib "/home/mordy/src/Hash-Registry/lib";
use Benchmark qw(:all);
use Devel::Peek qw(mstat);

my $Htype = 'Hash::Registry::PP';
GetOptions('x|xs' => \my $use_xs,
	'p|pp' => \my $use_pp,
	'c|count=i' => \my $count,
	'i|iterations=i' => \my $iterations);

$count ||= 50;
$iterations ||= 1;

if($use_xs) {
	$Htype = 'Hash::Registry::XS';
}
if($use_pp) {
	$Htype = 'Hash::Registry::PP';
}

log_info("Selected $Htype implementation");

eval "require $Htype";

my $i_BEGIN = 2;
my $i_END = $count;
sub single_pass {
	my $Hash = $Htype->new();
	my @olist;
	timethis(1, sub {
		foreach my $i ($i_BEGIN..$i_END) {
			my $obj = ValueObject->new();
			$Hash->store($i, $obj);
			$Hash->store(-$i, $obj);
			push @olist, $obj;
		}
	}, "Store");

	log_infof("Created %d objects\n", $ValueObject::ObjectCount);
#print Dumper($Hash);
	log_infof("Have %d objects now", $ValueObject::ObjectCount);
	log_infof("FORWARD=%d, REVERSE=%d, KEYS=%d",
		scalar values %{$Hash->forward},
		scalar values %{$Hash->reverse},
		scalar values %{$Hash->scalar_lookup});


	timethis(1, sub {
		foreach my $i($i_BEGIN..$i_END) {
			eval {
				my $obj1 = $Hash->fetch($i) or die "POSITIVE KEY FAIL!";
				my $obj2 = $Hash->fetch(-$i) or die "GAH!";
				$obj1->isa('ValueObject') &&
				$obj2->isa('ValueObject') &&
				$obj1 == $obj2
					or die
				"Soemthing happen!";
				#log_info($obj1);
			}; if($@) {
				print Dumper($Hash);
				die $@;
			}
		}
	}, "Fetch");
	
	my $ATTRTYPE = 42;
	$Hash->register_kt($ATTRTYPE, "TESTATTR");
	
	timethis(1, sub {
		foreach my $o (@olist) {
			log_info("ATTRSTORE V=$o");
			$Hash->store_a(43, $ATTRTYPE, $o);
		}
		print Dumper($Hash);
	}, "Attribute (STORE)");
	
	
	timethis(1, sub { @olist = () }, "Delete");


	log_debug("Everything should be cleared");
	log_infof("Have %d objects now", $ValueObject::ObjectCount);
	log_infof("FORWARD: %d, REVERSE=%d",
		scalar values %{$Hash->forward},
		scalar values %{$Hash->reverse}
	);
	print Dumper($Hash);
}

for (1..$iterations) {
	mstat("PASS=$_");
	single_pass();
}

sub compare_simple {
	my %simplehash;
	timethis(1, sub {
		foreach my $i ($i_BEGIN..$i_END) {
			my $obj = ValueObject->new();
			$simplehash{$i} = $obj;
			$simplehash{-$i} = $obj;
		}
	}, "Normal hash: STORE");
	timethis(1, sub {
		foreach my $i ($i_BEGIN..$i_END) {
			my $copy;
			$copy = $simplehash{$i};
			$copy = $simplehash{-$i};
		}
	}, "Normal hash: FETCH");
	timethis(1, sub {
		%simplehash = ();
	}, "Normal hash: DELETE");
}

compare_simple();
log_info("Exiting..");
