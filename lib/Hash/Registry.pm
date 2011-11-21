package Hash::Registry;
use strict;
use warnings;
use Scalar::Util qw(weaken);

use Hash::Registry::Common;
use Hash::Registry::Attribute;
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
			foreach (qw(XS PP)) {
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

sub has_value {
	my ($self,$value) = @_;
	return 0 if !defined $value;
	$value = $value + 0;
	return exists $self->reverse->{$value};
}

sub has_attr {
	my ($self,$attr,$t) = @_;
	$self->attr_get($attr, $t);
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
		my $existing = $self->forward->{$self->KString($o)};
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
	my $attr_s = ref $attr ? $attr + 0 : $attr;
	my $attr_t = $self->keytypes->{$t};
	die "Unknown attribute type '$t'" unless $attr_t;
    my $ustr = $attr_t . $attr_s;
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
    weaken($self->reverse->{$vaddr}->{$aobj+0} = $aobj);
    
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
	log_errf("DELATTR: A=%d V=%d", $aobj+0, $value+0);
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

=head2 USAGE APPLICATIONS AND BENEFITS

This module is not designed for the simple one-off script or module. For most
applications there is no true need to have multiple dynamically associated and
deleted object entries. The benefits of this module become apparent in design
and ease of use when larger and more complex, event-oriented systems are in use.

Thus, instead of a simple synopsis, I will try to dissect and pseudo-refactor
the code in L<POE::Component::Client::HTTP> (refered to as poco-http)
to demonstrate the usefulness of this module.

=head2 SYNOPSIS

We will assume that there is a gloabl object, <$Table> which may presumably be
stored on the I<heap>

We have a bunch of key types, so let's register them.

	my @KEY_TYPES;
	BEGIN {
		 @KEY_TYPES = map 'KT_'.$_, (
		 
			"EXT_REQ", #HTTP::Request object
			"POE_REQ", #POE::Component::Client::HTTP::Request object
			"POE_REQID", #ID of the POE request
			"POE_WID", #POE::Wheel ID, needed for events.
			
		);
		
		foreach my $kt (@KEY_TYPES) {
		   no strict 'refs';
		   *{$kt} = sub () { $kt }
		}
	}
	
	#....
	#Assume a table has been created by now
	$Table->register_kt(@_)  foreach (@KEY_TYPES);
	
The poco-http API takes a request object and optionally accepts a tag, by which
the user can easily identify the response received. The prime internal identifier
used by POE is an internal Request object (C<POE::Component::Client::HTTP::Request>),
identified by its refaddr:

	my $request = $heap->{factory}->create_request(
	  $http_request, $response_event, $tag, $progress_event,
	  $proxy_override, $sender
	);
	$heap->{request}->{$request->ID} = $request;
	$heap->{ext_request_to_int_id}->{$http_request} = $request->ID;

Instead of the last two lines, we do:
	
	$Table->store_kt($request->ID, KT_POE_REQID, $request, StongValue => 1);
	#Because this is our primary reference.
	$Table->store_kt($http_request, $request);
	
Later on, in the same function, we have this code:
	
	if ($@) {
		delete $heap->{request}->{$request->ID};
		delete $heap->{ext_request_to_int_id}->{$http_request};
	
		# we can reach here for things like host being invalid.
		$request->error(400, $@);
	}
	
Which can be refactored to:

	$Table->purge($request);

Which will clean up everything associated with $request.

At this point, poco-http has submitted a request to its connection manager
(L<POE::Component::Client::KeepAlive>), and is now awaiting a response. Here is
the code which handles it, with ommisions not pertinent to the description of the
Hash::Registry module.

	sub _poco_weeble_connect_done {
	  my ($heap, $response) = @_[HEAP, ARG0];
	
	  my $connection = $response->{'connection'};
	  my $request_id = $response->{'context'};
		
	  if (defined $connection) {
		DEBUG and warn "CON: request $request_id connected ok...";
		
		#my $request = $heap->{request}->{$request_id};

Nothing revolutionary here, replace with:
		
		my $request = $Table->fetch_kt(KT_POE_REQID, $request_id);
		
		unless (defined $request) {
		  DEBUG and warn "CON: ignoring connection for canceled request";		  
		  return;
		}
	
		my $block_size = $heap->{factory}->block_size;
	
		# get wheel from the connection
		my $new_wheel = $connection->start(
		  Driver       => POE::Driver::SysRW->new(BlockSize => $block_size),
		  InputFilter  => POE::Filter::HTTPHead->new(),
		  OutputFilter => POE::Filter::Stream->new(),
		  InputEvent   => 'got_socket_input',
		  FlushedEvent => 'got_socket_flush',
		  ErrorEvent   => 'got_socket_error',
		);
	
		DEBUG and warn "CON: request $request_id uses wheel ", $new_wheel->ID;
	
		# Add the new wheel ID to the lookup table.
		
		#$heap->{wheel_to_request}->{ $new_wheel->ID() } = $request_id;
		
And instead of this construct, we use:

		$Table->store_a($new_wheel->ID(), KT_POE_WID, $request);

We skip a bunch of SSL initialization code, since it does not seem to use
any type of lookup

	else {
		DEBUG and warn(
		  "CON: Error connecting for request $request_id --- ", $_[SENDER]->ID
		);
	
		my ($operation, $errnum, $errstr) = (
		  $response->{function},
		  $response->{error_num} || '??',
		  $response->{error_str}
		);
	
		DEBUG and warn(
		  "CON: request $request_id encountered $operation error " .
		  "$errnum: $errstr"
		);
	
		DEBUG and warn "I/O: removing request $request_id";

		#my $request = delete $heap->{request}->{$request_id};
		#$request->remove_timeout();
		#delete $heap->{ext_request_to_int_id}->{$request->[REQ_HTTP_REQUEST]};


Is replaced with:

		$Table->purge($request);
		$request->remove_timeout();

Here is the timeout function:

	sub _poco_weeble_timeout {
	  my ($kernel, $heap, $request_id) = @_[KERNEL, HEAP, ARG0];
	  
	  #my $request = delete $heap->{request}->{$request_id};
	  
Instead, we delete ALL lookup data associated with the key by doing this:

	  my $request = $Table->purgeby_kt($request_id, KT_POE_REQID);
	  ...
	  
We don't need this line

	  delete $heap->{ext_request_to_int_id}->{$request->[REQ_HTTP_REQUEST]};
	  ...
	  
Nor do we need this

		delete $heap->{wheel_to_request}->{$wheel_id};
		...

etc. etc.
The rest of the POE code is more or less the same.

Look here for some other code which could use an even better helping of this
module.


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

A <Lookup Type> is just an identifier by which one can fetch and store a value.
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
not weaken the key object

=item StrongValue

By default the value is weakened before it is inserted into the database, and when
the last external reference is destroyed, an implicit L</purge> is performed. Setting
this to true will disable this behavior and not weaken the value object.

=back

This method is also available as C<store_sk>

=item fetch($key)

Returns the value object indexed under C<$key>, if any. Also available under C<fetch_sk>

=item lexists($key)

Returns true if C<$key> exists in the database. Also available as C<lexists_sk>

=item unlink($key)

Removes C<$key> from the database. If C<$key> is linked to a value, and that value
has no other keys linked to it, then the value will also be deleted from the databse.
Also available as C<unlink_sk>


=item purgeby($key)
If C<$key> is linked to a value, then that value is removed from the database via
L</purge>

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
all attributes must have a type, and all API functions requiring a key will also
require a type.
A suffix of C<_a> is appended to all API functions.
In addition, the following differences in behavior and options exist

=over

=item store_a($attr, $type, $value, %options)

Like L</store>, but option hash takes a C<StrongAttr> option instead of a C<StrongKey>
option, which is the same. Attributes will be weakened for all associated values
if C<StrongAttr> was not specified during I<any> insertion operation.

=item fetch_a($attr, $type)

Fetch function returns an I<array> of values, and not a single value.

=item dissoc_a($attr, $type, $value)

Dissociates an attribute lookup from a single value. This function is special
for attributes, where a single attribute can be tied to more than a single value.

=item unlink_a($attr, $type)

Removes the attribtue from the database. Since multiple values can be tied to the
same attribute, this can potentially remove many values from the DB. Be sure to
use this function with caution

=back

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