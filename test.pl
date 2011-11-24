#!/usr/bin/perl
use strict;
use warnings;
use blib;

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
use Memory::Usage;

my $Htype = 'Hash::Registry::PP';
GetOptions('x|xs' => \my $use_xs,
	'p|pp' => \my $use_pp,
	'sweeping' => \my $use_sweep,
	'c|count=i' => \my $count,
	'i|iterations=i' => \my $iterations,
	'm|mode=s' => \my $Mode,
	'd|dump'	=> \my $Dump,
);

$count ||= 50;
$iterations ||= 1;
$Mode ||= 'all';

my $i_BEGIN = 1;
my $i_END = $count;
my $Mu = Memory::Usage->new();
$Mu->record("BEGIN");
sub single_pass {
	my $Hash = $Htype->new();
	my @olist;
	#Create object list..
	my ($impl_s) = (split(/::/, $Htype))[-1];
	timethis(1, sub {
		@olist = map { ValueObject->new() } ($i_BEGIN..$i_END);
	}, "Object Creation");
	
	$Mu->record("[$impl_s] Objects Created");
	
	if($Mode =~ /key|all/i ) {
		timethis(1, sub {
			foreach my $i ($i_BEGIN..$i_END) {
				my $obj = $olist[$i-1];
				$Hash->store($i, $obj);
				$Hash->store(-$i, $obj);
				push @olist, $obj;
			}
		}, "Store");
		
		log_infof("Created %d objects\n", $ValueObject::ObjectCount);
		
		log_infof("Have %d objects now", $ValueObject::ObjectCount);
		log_infof("FORWARD=%d, REVERSE=%d, KEYS=%d",
			scalar values %{$Hash->forward},
			scalar values %{$Hash->reverse},
			scalar values %{$Hash->scalar_lookup});
		
		$Mu->record("[$impl_s] Key storage");
		
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
					#print Dumper($Hash);
					die $@;
				}
			}
		}, "Fetch");
	}
	
	if($Mode =~ m/attr|all/i) {
		my $ATTRTYPE = 42;
		my $ATTRTYPE_ALT = "ALLYOURBASE";
		$Hash->register_kt($ATTRTYPE, "TESTATTR");
		$Hash->register_kt($ATTRTYPE_ALT, "ALTATTR");
		my @attrpairs = (
			[43, $ATTRTYPE],
			[666, $ATTRTYPE],
			[770, $ATTRTYPE],
			[1, $ATTRTYPE_ALT]
		);
		
		timethis(1, sub {
			foreach my $o (@olist) {
				$Hash->store_a(@$_, $o) foreach @attrpairs;
			}
		}, "Attribute (STORE)");
		$Mu->record("[$impl_s] Attribtue Storage");
		
		my $result_count = 0;
		timethis(1, sub {
			map { $result_count += scalar $Hash->fetch_a(@$_) }
				@attrpairs;
		}, "Attribute (FETCH)");
		log_info("Got total $result_count entries");
		
	}
	
	if($Dump) {
		$Hash->dump();
	}
	

	timethis(1, sub { @olist = () }, "Delete");
	
	if($Hash->isa('Hash::Registry::Sweeping')) {
		log_warn("Sweeping..");
		$Hash->sweep();
	}
	$Mu->dump();

	log_debug("Everything should be cleared");
	log_infof("Have %d objects now", $ValueObject::ObjectCount);
	log_infof("FORWARD: %d, REVERSE=%d",
		scalar values %{$Hash->forward},
		scalar values %{$Hash->reverse}
	);
	$Hash->dump();
}




my $use_all = !($use_xs||$use_pp||$use_sweep);
my @impl_map = (
	$use_xs, 'XS',
	$use_pp, 'PP',
	$use_sweep, 'Sweeping'
);



my @EnabledImplementations;

while (@impl_map) {
	my ($enabled,$backend) = splice(@impl_map, 0, 2);
	if(!$enabled && !$use_all) {
		next;
	}
	push @EnabledImplementations, 'Hash::Registry::'.$backend;
}

foreach my $impl (@EnabledImplementations) {
	$Htype = $impl;
	eval "require $Htype";
	log_warn("Using $Htype");
	for (1..$iterations) {
		single_pass();
	}
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
