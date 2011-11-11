package Hash::Registry;
use strict;
use warnings;
use Scalar::Util qw(weaken);

use Hash::Registry::Common;
use Hash::Registry::Feature::Attribute;
use Hash::Registry::Feature::KeyTyped;

use base qw(
	Hash::Registry::Feature::Attributed
	Hash::Registry::Feature::KeyTyped
);

use Log::Fu { level => "debug" };
use Class::XSAccessor {
	constructor => '_real_new',
	accessors => [qw(
		scalar_lookup
		attr_lookup
		forward
		reverse
		keyfunc
		unkeyfunc
		impl_data
		keytypes
	)]
};

use Data::Dumper;

sub _keyfunc_defl {
	my $k = shift;
	ref $k ? 0 + $k : $k;
}

sub new {
	my ($cls,%options) = @_;
	$options{keyfunc} ||= \&_keyfunc_defl;
	$options{unkeyfunc} ||= sub { $_[0] };
	$options{attr_lookup} = {};
	$options{reverse} = {};
	$options{forward} = {};
	$options{scalar_lookup} = {};
	my $self = $cls->_real_new(%options);
	$self->impl_init();
	return $self;
}

sub ukey2ikey {
	my ($self, $ukey, %options) = @_;
	my $ustr = $self->keyfunc($ukey);
	my $expected = delete $options{O_EXCL};
	my $create_if_needed = delete $options{Create};
	
	my $o = $self->scalar_lookup->{$ustr};
	if($expected && $o) {
		my $existing = $self->forward->{$self->KString($o)};
		if($existing && $expected != $existing) {
			die "Request O_EXCL for new key ${\$o->kstring} => $expected but key ".
			"is already tied to $existing";
		}
	}
	if(!$o && $create_if_needed) {
		$o = $self->kcls->new($ukey, $self);
		if(!$options{StrongKey}) {
			$o->weaken_encapsulated();
		}
	}
	return $o;
}

sub store {
	my ($self,$simple_scalar,$value,%options) = @_;
	
	my $o = $self->ukey2ikey($simple_scalar,
		Create => 1,
		O_EXCL => $value
	);
	
	my $vstring = $self->VString($value);
	#log_err("STORE H=$value (reverse): $vstring");
	my $kstring = $self->KString($o);
	
	$self->value_init($value);
	$self->reverse->{$vstring}->{$kstring} = $o;
	$self->forward->{$kstring} = $value;
	
	if(!$options{StrongValue}) {
		weaken($self->forward->{$kstring});
	}
	return $value;
}

sub fetch {
	my ($self,$simple_scalar) = @_;
	my $o = $self->ukey2ikey($simple_scalar);
	return unless $o;
	return $self->forward->{$self->KString($o)};
}

#This dissociates a value from a single key
sub delete_key_lookup {
	my ($self,$simple_scalar) = @_;
	
	my $stored = $self->fetch($simple_scalar);
	
	my $ko = $self->ukey2ikey($simple_scalar);
	return unless $ko;
	
	return unless $stored;
	my $vstr = $self->VString($stored);
	my $kstr = $self->KString($ko);
	
	delete $self->reverse->{$vstr}->{$kstr};
	my $v = delete $self->forward->{$kstr};
	if(!scalar values %{ $self->reverse->{$vstr} }) {
		$self->value_cleanup($stored);
	}
	return $stored;
}

sub delete_value {
	my ($self,$value) = @_;
	my $vstring = $self->VString($value);
	foreach my $ko (values %{ $self->reverse->{$vstring} }) {
		delete $self->forward->{$self->KString($ko)};
	}
	
	delete $self->reverse->{$vstring};
	$self->value_cleanup($value);
	
	return $value;
}

sub KString {
	my ($self, $kobj) = @_;
	$kobj->kstring;
}

sub VString {
	my ($self,$value) = @_;
	0 + $value;
}

sub delete_value_by_key {
	my ($self,$kspec) = @_;
	my $value = $self->fetch($kspec);
	return unless $value;
	$self->delete_value($value);
	return $value;
}

sub keys_for_value {
	my ($self,$value) = @_;
	my @ret;
	my $vstring = $self->VString($value);
	my $kl = $self->reverse->{$vstring};
	return () unless $kl;
	foreach my $k (@$kl) {
		$k = $self->unkeyfunc($k);
		push @ret, $k;
	}
	return @ret;
}

1;

__END__

=head1 NAME

Hash::Registry - Leak-free lookups for real objects.

=head1 DESCRIPTION

Hash::Registry provides an efficient and worry-free way to index objects by
arbitrary data - possibly other objects, simple scalars, or whatever.


It relies on magic and such to ensure that objects you put in the lookup table
are not maintained there unless you want them to be. In other words, you can store
objects in the table, and delete them without having to worry about what other
possible indices/references may be holding down the object.

=head2 SYNOPSIS

We will demonstrate the usefulness of this module within a multi-connection socket server

	
=head2 FEATURES

=over

=item One-To-Many association

It is possible, given a value, to retrieve all its keys, and vice versa. It is also
possible to establish many-to-many relationships by using the same object as both
a key and a value for different entries.

=item Key Types

This table accepts a key of any type, be it a simple string or an object reference.
Keys are internally stored as object references and encapsulate the original
key.

=item Garbage Collection (or not)

Both key and value types can be automatically selected for garbage collection,
and strength relationships established between them. Thus, it is possible for a
value to be automatically deleted if all its keys are deleted, and for all keys
to be deleted once a value is deleted. Since both keys and values can be object
references, this provides a lot of flexibility

=item TIEHASH interface

WIP


=back

=head2 API

=over

=item new(%options)

Creates a new Hash::Registry object. It takes a hash of options:

=over

=item keyfunc

This function is responsible for converting a key to something 'unique'. The
default implementation checks to see whether the key is a reference, and if so
uses its address, otherwise it uses the stringified value. It takes the user key
as its argument

=back

=item store($ukey, $value, %options)

Stores C<$value> under <$ukey>.

Options are as follows

=over

=item StrongKey

If true, then this key will retain a reference to C<$ukey>. By default, keys are
stored as weak references and automatically deleted when the value is deleted.

Setting this to true is useful if the key is a child/dependent of the value.

By default, keys are stored as weak references

Note that it is not currently possible to modify the strength property of a key
once it has been inserted.

=item StrongValue

If true, then the value will not be deleted/garbage collected until C<$ukey> is
deleted, either via garbage collection or through manually removing the entry

=back


=item fetch($ukey)

Fetch the item stored under C<$ukey>

=item delete_key_lookup($ukey)

Removes the value stored under C<$ukey>, so that it is no longer indexed by it.
If C<$ukey> is the last key storing the value, the value will be deleted from the
table.

Returns the value

=item delete_value($value)

Deletes the value from the table. All keys will be deleted as well

=item delete_value_by_key($ukey)

Given a single key, delete the value (and all other associated keys) which is indexed
under C<$ukey>.

Returns the value.

=item keys_for_value($value)

Returns a list of the keys associated with C<$value>. Note that the return value
is a I<copy>, and modifying it will have no effect on the table.

=back
