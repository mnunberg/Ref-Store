package Hash::Registry;
use strict;
use warnings;
use Scalar::Util qw(weaken);

use Hash::Registry::Common;
use Hash::Registry::Attribute;

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

sub new {
	my ($cls,%options) = @_;
	$options{keyfunc} ||= \&_keyfunc_defl;
	$options{unkeyfunc} ||= sub { $_[0] };
	$options{attr_lookup} = {};
	$options{reverse} = {};
	$options{forward} = {};
	$options{scalar_lookup} = {};
	my $self = $cls->_real_new(%options);
	return $self;
}

sub delete_value {
	my ($self,$value) = @_;
	my $vstring = $value + 0;
	
	foreach my $ko (values %{ $self->reverse->{$vstring} }) {
		$ko->unlink_value($value);
	}
	
	$self->dref_del_ptr($value, $self->reverse);
	delete $self->reverse->{$vstring};
	return $value;
}

sub register_kt {
	my ($self,$kt,$id_prefix) = @_;
	if(!$self->keytypes) {
		$self->keytypes({});
	}
	$id_prefix ||= $kt;
	die "Must have id prefix" unless $id_prefix;
	if(!exists $self->keytypes->{$kt}) {
		$self->keytypes->{$kt} = $id_prefix;
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
	$value = $value + 0;
	return exists $self->reverse->{$value};
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
	
	log_info($ustr);
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

sub store {
	my ($self,$simple_scalar,$value,%options) = @_;
	my $o = $self->ukey2ikey($simple_scalar,
		Create => 1,
		O_EXCL => $value
	);
	
	my $vstring = $value+0;
	my $kstring = $o->kstring;
	#log_err($kstring);
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

sub fetch {
	my ($self,$simple_scalar) = @_;
	my $o = $self->ukey2ikey($simple_scalar);
	return unless $o;
	return $self->forward->{$o->kstring};
}

#This dissociates a value from a single key
sub delete_key_lookup {
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
		$self->dref_del_ptr($stored, $self->reverse);
		
	}
	
	return $stored;
}

sub delete_value_by_key {
	my ($self,$kspec) = @_;
	my $value = $self->fetch($kspec);
	return unless $value;
	$self->delete_value($value);
	return $value;
}

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
    my $ustr = $self->keytypes->{$t} . $attr;
    my $aobj = $self->attr_lookup->{$ustr};
    return $aobj if $aobj;
    
    if(!$options{Create}) {
        return;
    }
    
    $aobj = $self->new_attr($ustr, $attr, $self);
    if($options{StrongAttr}) {
        $self->attr_lookup->{$ustr} = $aobj;
    } else {
        weaken($self->attr_lookup->{$ustr} = $aobj);
    }
    return $aobj;
}

sub store_a {
    my ($self,$attr,$t,$value,%options) = @_;
    
    my $aobj = $self->attr_get($attr, $t, Create => 1);    
    my $vaddr = $value + 0;
    
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
    
    return $value;
}

sub fetch_a {
    my ($self,$attr,$t) = @_;
    my $aobj = $self->attr_get($attr, $t);
    return unless $aobj;
    values %{$aobj->get_hash};
}

sub delete_value_by_attr {
    my ($self,$attr,$t) = @_;
    my $value = $self->fetch_a($attr, $t);
    return unless $value;
    $self->delete_value($value);
}

sub delete_attr_from_value {
    my ($self,$attr,$t,$value) = @_;
    my $aobj = $self->attr_get($attr, $t);
    return unless $aobj;
    if(!delete $aobj->get_hash->{$value+0}) {
        return;
    }
    
    $self->dref_del_ptr($value, $aobj->get_hash);
}

sub delete_attr_from_all {
    my ($self,$attr,$t) = @_;
    my $aobj = $self->attr_get($attr, $t);
	my $attrhash = $aobj->get_hash;
    return unless $aobj;
	
    map {
        $self->dref_del_ptr($_, $attrhash)
    } values %$attrhash;
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

	$Table->delete_value($request);

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

		$Table->delete_value($request);
		$request->remove_timeout();

Here is the timeout function:

	sub _poco_weeble_timeout {
	  my ($kernel, $heap, $request_id) = @_[KERNEL, HEAP, ARG0];
	  
	  #my $request = delete $heap->{request}->{$request_id};
	  
Instead, we delete ALL lookup data associated with the key by doing this:
	  my $request = $Table->delete_value_by_key_kt($request_id, KT_POE_REQID);
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
