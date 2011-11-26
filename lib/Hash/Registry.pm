package Hash::Registry;
use strict;
use warnings;
use Scalar::Util qw(weaken);

use Hash::Registry::Common;
use Hash::Registry::Attribute;
use Hash::Registry::Dumper;

our $VERSION = '0.01';
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
use base qw(Hash::Registry::Feature::KeyTyped);

################################################################################
################################################################################
################################################################################
### GENERIC FUNCTIONS                                                        ###
################################################################################
################################################################################
################################################################################
sub _keyfunc_defl {
	my $k = shift;
	if(ref $k) {
		return $k + 0;
	}
	return $k;
}

our $SelectedImpl;

sub new {
	my ($cls,%options) = @_;
	
	if($cls eq __PACKAGE__) {
		if(!defined $SelectedImpl) {
			log_debug("Will try to select best implementation");
			foreach (qw(XS PP Sweeping)) {
				my $impl = $cls . "::$_";
				eval "require $impl";
				if(!$@) {
					$SelectedImpl = $impl;
					last;
				}
			}
		}
		die "Can't load any implmented" unless $SelectedImpl;
		$cls = $SelectedImpl;
		log_debug("Using $SelectedImpl");
	}
	
	$options{keyfunc} ||= \&_keyfunc_defl;
	$options{unkeyfunc} ||= sub { $_[0] };
	$options{attr_lookup} = {};
	$options{reverse} = {};
	$options{forward} = {};
	$options{scalar_lookup} = {};
	my $self = $cls->_real_new(%options);
	return $self;
}

sub purge {
	my ($self,$value) = @_;
	return unless defined $value;
	my $vstring = $value + 0;
	
	my $prev = Dumper($self);
	foreach my $ko (values %{ $self->reverse->{$vstring} }) {
		if(!defined $ko) {
			log_err("State of table when entering this function");
			print $prev;
			log_err("Current state");
			print Dumper($self);
			die "Found stale key object!";
		}
		$ko->unlink_value($value);
	}
	
	$self->dref_del_ptr($value, $self->reverse, $value + 0);
	delete $self->reverse->{$vstring};
	return $value;
}

#Not fully implemented
sub exchange_value {
	my ($self,$old,$new) = @_;
	my $olds = $old+0;
	my $news = $new + 0;
	die "Can't switch to existing value!" if exists $self->reverse->{$news};
	
	return unless exists $self->reverse->{$olds};
	
	my $newh = {};
	my $oldh = $self->reverse->{$olds};
	$self->reverse->{$news} = $newh;
	
	while (my ($kaddr,$kobj) = each %$oldh) {
		$newh->{$kaddr} = $kobj;
		$kobj->exchange_value($old,$new);
		delete $oldh->{$kaddr};
	}
}

sub register_kt {
	my ($self,$kt,$id_prefix) = @_;
	if(!$self->keytypes) {
		$self->keytypes({});
	}
	$id_prefix ||= $kt;
	if(!exists $self->keytypes->{$kt}) {
		#log_info("Registering CONST=$kt PREFIX=$id_prefix");
		$self->keytypes->{$kt} = $id_prefix;
	}
}

sub maybe_cleanup_value {
	my ($self,$value) = @_;
	my $v_rhash = $self->reverse->{$value+0};
	if(!scalar %$v_rhash) {
		delete $self->reverse->{$value+0};
		$self->dref_del_ptr($value, $self->reverse, $value + 0);
	} else {
		#log_warn(scalar %$v_rhash);
	}
}

################################################################################
################################################################################
################################################################################
### INFORMATIONAL FUNCTIONS                                                  ###
################################################################################
################################################################################
################################################################################
sub has_key {
	my ($self,$key) = @_;
	$key = ref $key ? $key + 0 : $key;
	return (exists $self->forward->{$key} || exists $self->scalar_lookup->{$key});
}

*lexists = \&has_key;

sub has_value {
	my ($self,$value) = @_;
	return 0 if !defined $value;
	$value = $value + 0;
	return exists $self->reverse->{$value};
}

sub vlookups {
	my ($self,$value) = @_;
	my @ret;
	$value = $value + 0;
	my $vhash = $self->reverse->{$value};
	$vhash ||= {};
	foreach my $ko (values %$vhash) {
		push @ret, $ko->kstring;
	}
	return @ret;
}

*vexists = \&has_value;

sub has_attr {
	my ($self,$attr,$t) = @_;
	$self->attr_get($attr, $t);
}

sub is_empty {
	my $self = shift;
	%{$self->scalar_lookup} == 0
		&& %{$self->reverse} == 0
		&& %{$self->forward} == 0
		&& %{$self->attr_lookup} == 0;
}

sub dump {
	my $self = shift;
	my $dcls = "Hash::Registry::Dumper";
	my $hrd = $dcls->new();
	#my $hrd = Hash::Registry::Dumper->new();
	#log_err($hrd);
	$hrd->dump($self);
	$hrd->flush();
	#print Dumper($self);
}
################################################################################
################################################################################
################################################################################
### KEY FUNCTIONS                                                            ###
################################################################################
################################################################################
################################################################################
sub new_key {
	die "new_key not implemented!";
}

sub ukey2ikey {
	my ($self, $ukey, %options) = @_;
	
	my $ustr = $self->keyfunc->($ukey);
	my $expected = delete $options{O_EXCL};
	my $create_if_needed = delete $options{Create};
	
	#log_info($ustr);
	my $o = $self->scalar_lookup->{$ustr};
	if($expected && $o) {
		my $existing = $self->forward->{$o->kstring};
		if($existing && $expected != $existing) {
			die "Request O_EXCL for new key ${\$o->kstring} => $expected but key ".
			"is already tied to $existing";
		}
	}
	
	if(!$o && $create_if_needed) {
		$o = $self->new_key($ukey);
		if(!$options{StrongKey}) {
			$o->weaken_encapsulated();
		}
	}
	
	return $o;
}

sub store_sk {
	my ($self,$ukey,$value,%options) = @_;
	my $o = $self->ukey2ikey($ukey,
		Create => 1,
		O_EXCL => $value,
		%options
	);
	my $vstring = $value+0;
	my $kstring = $o->kstring;
	$self->reverse->{$vstring}->{$kstring} = $o;
	$self->forward->{$kstring} = $value;
	
	#Add a back-delete to the reverse entry. The forward
	#entry for keys are handled by the keys themselves.
	$self->dref_add_ptr($value, $self->reverse);
	$o->link_value($value);
	
	if(!$options{StrongValue}) {
		weaken($self->forward->{$kstring});
	}
	return $value;
}
*store = \&store_sk;

sub fetch_sk {
	my ($self,$simple_scalar) = @_;
	#log_info("called..");
	my $o = $self->ukey2ikey($simple_scalar);
	return unless $o;
	return $self->forward->{$o->kstring};
}
*fetch = \&fetch_sk;

#This dissociates a value from a single key
sub unlink_sk {
	my ($self,$simple_scalar) = @_;
	
	my $stored = $self->fetch($simple_scalar);
	
	my $ko = $self->ukey2ikey($simple_scalar);
	return unless $ko;
	
	die "Found orphaned key $ko" unless $stored;
	my $vstr = $stored + 0;
	my $kstr = $ko->kstring;
	delete $self->reverse->{$vstr}->{$kstr};
	my $v = delete $self->forward->{$kstr};
	
	$ko->unlink_value($stored);
	
	if(!keys %{$self->reverse->{$vstr}}) {
		
		delete $self->reverse->{$vstr};
		$self->dref_del_ptr($stored, $self->reverse, $stored+0);
		
	}
	
	return $stored;
}
*unlink = \&unlink_sk;

sub purgeby_sk {
	my ($self,$kspec) = @_;
	my $value = $self->fetch($kspec);
	return unless $value;
	$self->purge($value);
	return $value;
}

*purgeby = \&purgeby_sk;

*lexists_sk = \&lexists;

################################################################################
################################################################################
################################################################################
### ATTRIBUTE FUNCTIONS                                                      ###
################################################################################
################################################################################
################################################################################
sub new_attr {
	my ($self,$astr,$attr) = @_;
	my $cls = ref $attr ? 'Hash::Registry::Attribute::Encapsulating' :
		'Hash::Registry::Attribute';
	$cls->new($astr,$attr,$self);
}

sub attr_get {
    my ($self,$attr,$t,%options) = @_;
	
	my $ustr =
		($self->keytypes->{$t} or die "Can't find attribute type $t") .
		$attr . (ref $attr ? $attr + 0 : $attr);
	
#	my $attr_s = ref $attr ? $attr + 0 : $attr;
#	my $attr_t = $self->keytypes->{$t};
#	die "Unknown attribute type '$t'" unless $attr_t;
#    my $ustr = $attr_t . $attr_s;
    my $aobj = $self->attr_lookup->{$ustr};
    return $aobj if $aobj;
    
    if(!$options{Create}) {
        return;
    }
    
    $aobj = $self->new_attr($ustr, $attr, $self);
    if($options{StrongAttr}) {
        $self->attr_lookup->{$ustr} = $aobj;
    } else {
		$aobj->weaken_encapsulated();
        weaken($self->attr_lookup->{$ustr} = $aobj);
    }
	#log_err("Stored $attr:$t");
    return $aobj;
}

sub store_a {
    my ($self,$attr,$t,$value,%options) = @_;
    
    my $aobj = $self->attr_get($attr, $t, Create => 1);
	if(!$value) {
		log_err(@_);
		die "NULL Value!";
	}
    my $vaddr = $value + 0;
    #log_warn("STORING $t:$attr:$value");
    #weaken($self->reverse->{$vaddr}->{$aobj+0} = $aobj);
	$self->reverse->{$vaddr}->{$aobj+0} = $aobj;
    
    if(!$options{StrongValue}) {
        $aobj->store_weak($vaddr, $value);
    } else {
        $aobj->store_strong($vaddr, $value);
    }

    #add back-delete references to both the private
    #attribute hash as well as the reverse entry.
	
    $self->dref_add_ptr($value, $aobj->get_hash);
    $self->dref_add_ptr($value, $self->reverse);
    $aobj->link_value($value);
	
    return $value;
}

sub fetch_a {
    my ($self,$attr,$t) = @_;
    my $aobj = $self->attr_get($attr, $t);
	if(!$aobj) {
		#log_err("Can't find attribute object! ($attr:$t)");
		#print Dumper($self->attr_lookup);
		return;
	}
	my @ret;
	return @ret unless $aobj;
	@ret = values %{$aobj->get_hash};
	return @ret;
}

sub purgeby_a {
    my ($self,$attr,$t) = @_;
    my @values = $self->fetch_a($attr, $t);
    $self->purge($_) foreach @values;
	return @values;
}

sub dissoc_a {
    my ($self,$attr,$t,$value) = @_;
    my $aobj = $self->attr_get($attr, $t);
	if(!$aobj) {
		log_err("Can't find attribute for $t$attr");
		return;
	}
	#log_errf("DELATTR: A=%d V=%d", $aobj+0, $value+0);
    return unless $aobj;
	my $attrhash = $aobj->get_hash;
	delete $attrhash->{$value+0};
	delete $self->reverse->{$value+0}->{$aobj+0};
	$self->dref_del_ptr($value, $attrhash, $value+0);
	
	$aobj->unlink_value($value);
	$self->maybe_cleanup_value($value);
}

sub unlink_a {
    my ($self,$attr,$t) = @_;
    my $aobj = $self->attr_get($attr, $t);
	my $attrhash = $aobj->get_hash;
    return unless $aobj;
	
	while (my ($k,$v) = each %$attrhash) {
		$self->dref_del_ptr($v, $attrhash, $v+0);
		delete $attrhash->{$k};
		delete $self->reverse->{$v+0}->{$aobj+0};
		$self->maybe_cleanup_value($v);
	}
}

*lexists_a = \&has_attr;

1;

__END__

=head1 NAME

Hash::Registry - Store objects, index by object, tag by objects - all without
leaking.


=head1 SYNOPSIS

	my $table = Hash::Registry->new();
	
Store a value under a simple string key, maintain the value as a weak reference.
The string key will be deleted when the value is destroyed:

	$table->store("key", $object);

Store C<$object> under a second index (C<$fh>), which is a globref;
C<$fh> will automatically be garbage collected when C<$object> is destroyed.

	{
		open my $fh, ">", "/foo/bar";
		$table->store($fh, $object, StrongKey => 1);
	}
	# $fh still exists with a sole reference remaining in the table
	
Register an attribute type (C<foo_files>), and tag C<$fh> as being one of C<$foo_files>,
C<$fh> is still dependent on C<$object>

	# assume $fh is still in scope
	
	$table->register_kt("foo_files");
	$table->store_a(1, "foo_files", $fh);

Store another C<foo_file>
	
	open my $fh2, ">", "/foo/baz"
	$table->store_a(1, "foo_files", $fh);
	# $fh2 will automatically be deleted from the table when it goes out of scope
	# because we did not specify StrongKey
	
Get all C<foo_file>s

	my @foo_files = $table->fetch_a(1, "foo_files");
	
	# @foo_files contains ($fh, $fh2);
	
Get rid of C<$object>. This can be done in one of the following ways:
	
	# Implicit garbage collection
	undef $object;
	
	# Delete by value
	$table->purge($object);
	
	# Delete by key ($fh is still stored under the foo_keys attribute)
	$table->purgeby($fh);

	# remove each key for the $object value
	$table->unlink("key");
	$table->unlink($fh); #fh still exists under "foo" files
	
Get rid of C<foo_file> entries
	
	# delete, by attribute
	$table->purgeby_a(1, "foo_files");
	
	# delete a single attribute from all entries
	$table->unlink_a(1, "foo_files");
	
	# dissociate the 'foo_files' attribtue from each entry
	$table->dissoc_a(1, "foo_files", $fh);
	$table->dissoc_a(1, "foo_files", $fh2);
	
	# implicit garbage collection:
	undef $fh;
	undef $fh2;

For a more detailed walkthrough, see L<Hash::Registry::Walkthrough>
	
=head1 DESCRIPTION

Hash::Registry provides an efficient and worry-free way to index objects by
arbitrary data - possibly other objects, simple scalars, or whatever.

It relies on magic and such to ensure that objects you put in the lookup table
are not maintained there unless you want them to be. In other words, you can store
objects in the table, and delete them without having to worry about what other
possible indices/references may be holding down the object.

=head2 USAGE APPLICATIONS AND BENEFITS

At a more basic level, this module is good for general simple and safe by-object
indexing and object tagging. It is also a good replacement for L<Hash::Util::FieldHash>
support for perls which do not support tied hash C<uvar> magic.

Thus, this module can perform inside-out objects 

This module is not designed for the simple one-off script or module. For most
applications there is no true need to have multiple dynamically associated and
deleted object entries. The benefits of this module become apparent in design
and ease of use when larger and more complex, event-oriented systems are in use.

In shorter terms, this module allows you to reliably use a I<Single Source Of Truth>
for your object lookups. There is no need to synchronize multiple lookup tables
to ensure that there are no dangling references to an object you should have deleted


=head2 SYNOPSIS


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


=back

=head1 API

=head2 LOOKUP TYPES

There are three common lookup types by which values can be indexed and mapped to.

A B<Lookup Type> is just an identifier by which one can fetch and store a value.
The uniqueness of identifiers is dependent on the lookup type. Performance for various
lookup types varies.

Each lookup type has a small tag by which API functions pertaining to it can
be identified

=over

=item Value-specific operations

These functions take a B<value> as their argument, and work regardless of the lookup
type

=over

=item purge($value)

Remove C<$value> from the database. For all lookup types which are linked to C<$value>,
they will be removed from the database as well if they do not link to any other
values

=item vexists($value)

Returns true if C<$value> is stored in the database

=back

=item Simple Key (SK)

This is the quickest and simplest key type. It can use either string or object keys.
It support. The functions it supports are 

=over

=item store($key, $value, %options)

Store C<$value> under lookup <$key>. Key can be an object reference or string.

A single value can be stored under multiple keys, but a single key can only be linked
to a single value.

Options are two possible hash options:

=over

=item StrongKey

If the key is an object reference, by default it will be weakened in the databse,
and when the last reference outside the database is destroyed, an implicit L</unlink>
will be called on it. Setting C<StrongKey> to true will disable this behavior and
not weaken the key object.

A strong key is still deleted if its underlying value gets deleted

=item StrongValue

By default the value is weakened before it is inserted into the database, and when
the last external reference is destroyed, an implicit L</purge> is performed. Setting
this to true will disable this behavior and not weaken the value object.

=back

It is important to note the various rules and behaviors with key and value
storage options.

There are two conditions under which an entry (key and value) may be deleted from
the table. The first condition is when a key or value is a reference type, and
its referrent goes out of scope; the second is when either a key or a value is
explicitly deleted from the table.

It is helpful to think of entries as a miniature version of implicit reference
counting. Each key represents an inherent increment in the value's reference
count, and each key has a reference count of one, represented by the amount of
values it actually stores.

Based on that principle, when either a key or a value is forced to I<leave> the
table (either explicitly, or because its referrant has gone out of scope), its
dependent objects decrease in their table-based implicit references.

Consider the simple case of implicit deletion:

	{
		my $key = "string":
		my $value = \my $foo
		$table->store($key, $foo);
	}
	
In which case, the string C<"string"> is deleted from the table as $foo goes out
of scope.

The following is slightly more complex
	
	my $value = \my $foo;
	{
		my $key = \my $baz;
		$table->store($key, $value, StrongValue => 1);
	}
	
In this case, C<$value> is removed from the table, because its key object's
referrant (C<$baz>) has gone out of scope. Even though C<StrongValue> was specified,
the value is not deleted because its own referrant (C<$foo>) has been destroyed,
but rather because its table-implicit reference count has gone down to 0 with the
destruction of C<$baz>

The following represents an inverse of the previous block

	my $key = \my $baz;
	{
		my $value = \my $foo;
		$table->store($key, $value, StrongKey => 1);
	}
	
Here C<$value> is removed from the table because naturally, its referrant, C<$foo>
has been destroyed. C<StrongKey> only maintains an extra perl reference to C<$baz>.

However, by specifying both C<StrongKey> and C<StrongValue>, we are able to
completely disable garbage collection, and nothing gets deleted

	{
		my $key = \my $baz;
		my $value = \my $foo;
		$table->store($key, $value, StrongKey => 1, StrongValue => 1);
	}

This method is also available as C<store_sk>.

It is an error to call this method twice on the same lookup <-> value specification.

=item fetch($key)

Returns the value object indexed under C<$key>, if any. Also available under C<fetch_sk>

=item lexists($key)

Returns true if C<$key> exists in the database. Also available as C<lexists_sk>

=item unlink($key)

Removes C<$key> from the database. If C<$key> is linked to a value, and that value
has no other keys linked to it, then the value will also be deleted from the databse.
Also available as C<unlink_sk>
	
	$table->store("key1", $foo);
	$table->store("key2", $foo);
	$table->store("key3", $bar);
	
	$table->unlink("key1"); # $foo is not deleted because it exists under "key2"
	$table->unlink("key3"); # $bar is deleted because it has no remaining lookups
	
=item purgeby($key)

If C<$key> is linked to a value, then that value is removed from the database via
L</purge>. Also available as C<purgeby_sk>.

These two blocks are equivalent:
	
	# 1
	my $v = $table->fetch($k);
	$table->purge($v);
	
	# 2
	$table->purgeby($k);

=back

=item Typed Keys

Typed keys are like simple keys, but with more flexibility. Whereas a simple key
can only store associate any string with a specific value, typed keys allow
for associating the same string key with different values, so long as the
type is different. A scenario when this is useful is associating IDs received from
different libraries, which may be identical, to different values.

For instance:

	use Library1;
	use Library1;
	
	my $hash = Hash::Registry->new();
	$hash->register_kt('l1_key');
	$hash->register_kt('l2_key');
	
	#later on..
	my $l1_value = Library1->get_handle();
	my $l2_value = Library2->get_handle();
	
	#assume that this is possible:
	
	$l1_value->ID == $l2_value->ID();
	
	$hash->store_kt($l1_value->ID(), 'l1_key', $l1_value);
	$hash->store_kt($l2_value->ID(), 'l2_key', $l2_value);

Note that this will only actually work for B<string> keys. Object keys can still
only be unique to a single value at a time.


All functions described for L</Simple Keys> are identical to those available for
typed keys, except that the C<$key> argument is transformed into two arguments;

thus:
	
	store_kt($key, $type, $value);
	fetch_kt($key, $type);

and so on.

In addition, there is a function which must be used to register key types:

=over

=item register_kt($ktype, $id)

Register a keytype. C<$ktype> is a constant string which is the type, and C<$id>
is a unique identifier-prefix (which defaults to C<$ktype> itself)

=back

=item Attributes

Whereas keys map value objects according to their I<identities>, attributes map
objects according to arbitrary properties or user defined tags. Hence an attribute
allows for a one-to-many relationship between a lookup index and its corresponding
value.

The common lookup API still applies. Attributes must be typed, and therefore
all attribute functions must have a type as their second argument.

A suffix of C<_a> is appended to all API functions.
In addition, the following differences in behavior and options exist

=over

=item store_a($attr, $type, $value, %options)

Like L</store>, but option hash takes a C<StrongAttr> option instead of a C<StrongKey>
option, which is the same. Attributes will be weakened for all associated values
if C<StrongAttr> was not specified during I<any> insertion operation.

=item fetch_a($attr, $type)

Fetch function returns an I<array> of values, and not a single value.

thus:
	
	my $value = $hash->fetch($key);
	#but
	my @values = $hash->fetch_a($attr,$type);
	
However, storing an attribute is done only one value at a time.

=item dissoc_a($attr, $type, $value)

Dissociates an attribute lookup from a single value. This function is special
for attributes, where a single attribute can be tied to more than a single value.

=item unlink_a($attr, $type)

Removes the attribtue from the database. Since multiple values can be tied to the
same attribute, this can potentially remove many values from the DB. Be sure to
use this function with caution

=back

It is possible to use attributes as tags for boolean values or flags, though the
process right now is somewhat tedious (eventually this API will be extended to allow
less boilerplate)

	use constant ATTR_FREE => "attr_free";
	use constant ATTR_BUSY => "attr_busy";
	
	$hash->register_kt(ATTR_FREE);
	$hash->register_kt(ATTR_BUSY);
	
	$hash->store_a(1, ATTR_FREE, $value); #Value is now tagged as 'free';
	
	#to mark the value as busy, be sure to inclusively mark the busy tag first,
	#and then remove the 'free' mark. otherwise the value will be seen as destroyed
	#and associated references removed:
	
	$hash->store_a(1, ATTR_BUSY, $value);
	$hash->dissoc_a(1, ATTR_FREE, $value);
	
	#mark as free again:
	
	$hash->store_a(1, ATTR_FREE, $value);
	$hash->dissoc_a(1, ATTR_BUSY, $value);
	
The complexities come from dealing with a triadic value for a tag. A tag for a value
can either be true, false, or unset. so C<0, ATTR_FREE> is valid as well.

=back

=head2 CONSTRUCTION

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

Hash::Registry will try and select the best implementation (C<Hash::Registry::XS>
and C<Hash::Registry::PP>, in that order). You can override this by seting
C<$Hash::Registry::SelectedImpl> to a package of your choosing (which must be
loaded).

=back

=head2 DEBUGGING

Often it is helpful to know what the table is holding and indexing, possibly because
there is a bug or because you have forgotten to delete something.

The following functions are available for debugging

=over

=item vexists($value)

Returns true if C<$value> exists in the database. The database internally maintains
a hash of values. When functioning properly, a value should never exist without
a key lookup, but this is still alpha software

=item vlookups($value)

Returns an array of stringified lookups for which this value is registered

=item lexists(K)

Returns true if the lookup C<K> exists. See the L</API> section for lookup-specific
parameters for C<K>

=item is_empty

Returns true if there are no lookups and no values in the database

=item dump

Prints a tree-like representation of the database. This will recurse the entire
database and print information about all values and all lookup types. In addition,
for object references, it will print the reference address in decimal and hexadecimal,
the actual SV address of the reference, and whether the reference is a weak
reference.

=back

=head1 AUTHOR

Copyright (C) 2011 by M. Nunberg

You may use and distribute this program under the same terms as perl itself


=head1 SEE ALSO

=over

=item L<Hash::Util::FieldHash>

Hash::Registry implements a superset of Hash::Util::FieldHash, but the latter is
most likely quicker. However, it will only work with perls newer than 5.10

=item L<Tie::RefHash::Weak>

=item L<Variable::Magic>

Perl API for magic interface, used by the C<PP> backend

=back