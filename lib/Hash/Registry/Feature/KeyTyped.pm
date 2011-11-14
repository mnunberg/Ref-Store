package Hash::Registry::Feature::KeyTyped;
use strict;
use warnings;
our $AUTOLOAD;

BEGIN {
	foreach my $fname (qw(
		store
		fetch
		delete_key_lookup
		delete_value
	)) {
		my $wrapname = $fname . "_kt";
		{
			no strict 'refs';
			*{$wrapname} = sub {
				my @args = @_;
				my $self = $args[1];
				my $ktarg = splice(@_, 2);
				my $pfix = $self->get_kt_prefix($ktarg, "$fname: Can't find prefix!");
				my $orig = $args[1];
				$args[1] = $pfix.$orig;
				
				shift @args;
				$self->$fname(@args);
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
}
1;