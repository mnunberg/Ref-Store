package Ref::Store::Feature::KeyTyped;
use strict;
use warnings;
our $AUTOLOAD;
use Log::Fu;
use Carp qw(confess);
use Data::Dumper;

$SIG{__DIE__} = \&confess;
BEGIN {
	foreach my $fname (qw(
		store
		fetch
		purgeby
		unlink
		lexists
	)) {
		my $wrapname = $fname . "_kt";
		{
			no strict 'refs';
			*{$wrapname} = sub {
				my @args = @_;
				my $self = $args[0];
				#print Dumper(\@args);
				my ($ktarg) = splice(@args, 2, 1);
				#log_err($ktarg);
				#log_err(@args);
				my $pfix = $self->get_kt_prefix($ktarg, "$fname: Can't find prefix ($ktarg)!");
				my $orig = $args[1];
				die "Must have defined key!" unless defined $orig;
				if(!ref $orig) {
					$orig = $pfix . $orig;
					$args[1] = $orig;
				} else {
					log_warn("Using keytypes with object key has no effect");
				}
				shift @args;
				#print Dumper($self);
				return $self->$fname(@args);
			};
		}
	}
}

sub get_kt_prefix {
	my ($self,$kt,$do_die) = @_;
	my $ret = $self->keytypes->{$kt};
	if((!$ret) && $do_die) {
		die $do_die;
	}
	return $ret;
}
1;