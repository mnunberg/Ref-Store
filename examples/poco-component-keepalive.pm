package POE::Component::Client::Keepalive;
BEGIN {
  $POE::Component::Client::Keepalive::VERSION = '0.268';
  sub POE::Kernel::CATCH_EXCEPTIONS () { 0 }
}

use warnings;
use strict;

use Carp qw(croak cluck);
use Errno qw(ETIMEDOUT EBADF);
use Socket qw(SOL_SOCKET SO_LINGER);

use POE;
use POE::Wheel::SocketFactory;
use POE::Component::Connection::Keepalive;
use POE::Component::Resolver;
use Net::IP qw(ip_is_ipv4);
use Log::Fu;
use Scalar::Util qw(weaken);

my $ssl_available;
eval {
  require POE::Component::SSLify;
  $ssl_available = 1;
};

use constant DEBUG => 1;
use constant DEBUG_DNS => DEBUG || 0;
use constant DEBUG_DEALLOCATE => DEBUG || 0;

# Manage connection request IDs.

my $CurrentID = 0;

my $default_resolver;
my $instances = 0;

my @LookupKeys;
BEGIN {
  @LookupKeys = qw(
    ATTR_CONNKEY_FREE
    ATTR_CONNKEY_BUSY
    KEY_SOCKET
    KEY_CONNKEY
    ATTR_CONNKEY
    ATTR_SOCKET_USED
    ATTR_SOCKET_FREE
    KEY_WID
    KEY_REQID
    KEY_WHEELOBJ
    KEY_REQOBJ
    KEY_CONNOBJ
  );
  foreach (@LookupKeys) {
    no strict 'refs';
    my $tmp = $_;
    *{$tmp} = sub () { "$tmp-"; };
  }
}

use Ref::Store::XS;

sub _new_lookup {
  my $lookup = Ref::Store::XS->new();
  no strict 'refs';
  $lookup->register_kt("$_-", "$_-") foreach @LookupKeys;
  log_info("Initializing lookup $lookup");
  return $lookup;
}



# The connection manager uses a number of data structures, most of
# them arrays.  These constants define offsets into those arrays, and
# the comments document them.


use constant {
  SKI_SOCKET => 0,
  SKI_KEY    => 1,
  SKI_ATIME  => 2,
  
  #'union'-type field:
  #timer is only active when we have a raw socket and not a SockeFactory connect wheel
  SKI_TIMER  => 3,
  SKI_WHEEL  => 3,
};


                                 # @$self = (
#use constant SF_POOL      => 0;  #   \%socket_pool, UNUSED!
use constant SF_QUEUE     => 1;  #   \@request_queue,
#use constant SF_USED      => 2;  #   \%sockets_in_use, UNUSED!
use constant SF_WHEELS    => 3;  #   H::R,
use constant SF_USED_EACH => 4;  #   \%count_by_triple,
use constant SF_MAX_OPEN  => 5;  #   $max_open_count,
use constant SF_MAX_HOST  => 6;  #   $max_per_host,
use constant SF_SOCKETS   => 7;  #   H::R,
use constant SF_KEEPALIVE => 8;  #   $keep_alive_secs,
use constant SF_TIMEOUT   => 9;  #   $default_request_timeout,
use constant SF_RESOLVER  => 10; #   $poco_client_dns_object,
use constant SF_SHUTDOWN  => 11; #   $shutdown_flag,
use constant SF_REQ_INDEX => 12; #   H::R,
use constant SF_BIND_ADDR => 13; #   $bind_address,
                                 # );

# @request_queue = (
#   $request,
#   $request,
#   ....
# );

                                    # $request = [
use constant RQ_SESSION     => 0;   #   $request_session,
use constant RQ_EVENT       => 1;   #   $request_event,
use constant RQ_SCHEME      => 2;   #   $request_scheme,
use constant RQ_ADDRESS     => 3;   #   $request_address,
use constant RQ_IP          => 4;   #   $request_ip,
use constant RQ_PORT        => 5;   #   $request_port,
use constant RQ_CONN_KEY    => 6;   #   $request_connection_key,
use constant RQ_CONTEXT     => 7;   #   $request_context,
use constant RQ_TIMEOUT     => 8;   #   $request_timeout,
use constant RQ_START       => 9;   #   $request_start_time,
use constant RQ_TIMER_ID    => 10;  #   $request_timer_id,
use constant RQ_WHEEL_ID    => 11;  #   $request_wheel_id,
use constant RQ_ACTIVE      => 12;  #   $request_is_active,
use constant RQ_ID          => 13;  #   $request_id,
use constant RQ_ADDR_FAM    => 14;  #   $request_address_family,
use constant RQ_FOR_SCHEME  => 15;  #   $request_address_family,
use constant RQ_FOR_ADDRESS => 16;  #   $request_address_family,
use constant RQ_FOR_PORT    => 17;  #   $request_address_family,
                                    # ];

# Create a connection manager.

sub new {
  my $class = shift;
  croak "new() needs an even number of parameters" if @_ % 2;
  my %args = @_;

  my $max_per_host = delete($args{max_per_host}) || 4;
  my $max_open     = delete($args{max_open})     || 128;
  my $keep_alive   = delete($args{keep_alive})   || 4;
  my $timeout      = delete($args{timeout})      || 6;
  my $resolver     = delete($args{resolver});
  my $bind_address = delete($args{bind_address});

  my @unknown = sort keys %args;
  if (@unknown) {
    croak "new() doesn't accept: @unknown";
  }

  my $self = bless [
    undef,                # SF_POOL
    [ ],                # SF_QUEUE
    undef,                # SF_USED
    _new_lookup(),      # SF_WHEELS
    { },                # SF_USED_EACH
    $max_open,          # SF_MAX_OPEN
    $max_per_host,      # SF_MAX_HOST
    _new_lookup(),      # SF_SOCKETS
    $keep_alive,        # SF_KEEPALIVE
    $timeout,           # SF_TIMEOUT
    undef,              # SF_RESOLVER
    undef,              # SF_SHUTDOWN
    _new_lookup(),      # SF_REQ_INDEX
    $bind_address,      # SF_BIND_ADDR
  ], $class;

  $default_resolver = $resolver
    if $resolver && eval { $resolver->isa('POE::Component::Resolver') };

  $self->[SF_RESOLVER] = (
    $default_resolver ||= POE::Component::Resolver->new()
  );

  POE::Session->create(
    object_states => [
      $self => {
        _start               => "_ka_initialize",
        _stop                => "_ka_stopped",
        ka_add_to_queue      => "_ka_add_to_queue",
        ka_cancel_dns_response => "_ka_cancel_dns_response",
        ka_conn_failure      => "_ka_conn_failure",
        ka_conn_success      => "_ka_conn_success",
        ka_deallocate        => "_ka_deallocate",
        ka_dns_response      => "_ka_dns_response",
        ka_keepalive_timeout => "_ka_keepalive_timeout",
        ka_reclaim_socket    => "_ka_reclaim_socket",
        ka_relinquish_socket => "_ka_relinquish_socket",
        ka_request_timeout   => "_ka_request_timeout",
        ka_resolve_request   => "_ka_resolve_request",
        ka_set_timeout       => "_ka_set_timeout",
        ka_shutdown          => "_ka_shutdown",
        ka_socket_activity   => "_ka_socket_activity",
        ka_wake_up           => "_ka_wake_up",
      },
    ],
  );

  return $self;
}

# Initialize the hidden session behind this component.
# Set an alias so the public methods can send it messages easily.

sub _ka_initialize {
  my ($object, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];
  $instances++;
  $heap->{resolve} = { };
  $kernel->alias_set("$object");
}

# When programs crash, the session may stop in a non-shutdown state.
# _ka_stopped and DESTROY catch this either way the death occurs.

sub _ka_stopped {
  $_[OBJECT][SF_SHUTDOWN] = 1;
}

sub DESTROY {
  my $self = shift;
  $self->shutdown();
}

# Request to wake up.  This should only happen during the edge
# condition where the component's request queue goes from empty to
# having one item.
#
# It also happens during free(), to see if there are more sockets to
# deal with.
#
# TODO - Make the _ka_wake_up stuff smart enough not to post duplicate
# messages to the queue.

sub _ka_wake_up {
  my ($self, $kernel) = @_[OBJECT, KERNEL];

  # Scan the list of requests, until we find one that can be met.
  # Fire off POE::Wheel::SocketFactory to begin the connection
  # process.
  use Data::Dumper;
  my $request_index  = 0;
  my $currently_open = scalar $self->[SF_SOCKETS]->fetch_a(1, ATTR_SOCKET_FREE);
  $currently_open += ($self->[SF_SOCKETS]->fetch_a(1, ATTR_SOCKET_USED) || 0);
  log_err("Currently open: $currently_open");
          
  my @splice_list;
  
  QUEUED:
  foreach my $request (@{$self->[SF_QUEUE]}) {
    DEBUG and warn "WAKEUP: checking for $request->[RQ_CONN_KEY]";

    # Sweep away inactive requests.

    unless ($request->[RQ_ACTIVE]) {
      push @splice_list, $request_index;
      next;
    }

    # Skip this request if its scheme/address/port triple is maxed
    # out.
    my $req_key = $request->[RQ_CONN_KEY];
    next if (
      ($self->[SF_USED_EACH]{$req_key} || 0) >= $self->[SF_MAX_HOST]
    );
    
    # Honor the request from the free pool, if possible.  The
    # currently open socket count does not increase.

    my $existing_connection = $self->_check_free_pool($req_key);
    if ($existing_connection) {
      push @splice_list, $request_index;

      _respond(
        $request, {
          connection => $existing_connection,
          from_cache => "deferred",
        }
      );
      
      # Remove the wheel-to-request index.
      
      #NB we don't need to really do this, assuming that the request itself
      #only exists in the queue, this entry should be garbage collected.
      $self->[SF_REQ_INDEX]->delete_value($request);
      next;
    }
    
    
    # we can't easily take this out of the outer loop since _check_free_pool
    # can change it from under us
    my @free_sockets = $self->[SF_SOCKETS]->fetch_a(1, ATTR_SOCKET_FREE);
    
    
    #At this point we have a valid request, but we need to make sure
    #that we don't have too many open requests..
    

    # Try to free over-committed (but unused) sockets until we're back
    # under SF_MAX_OPEN sockets.  Bail out if we can't free enough.
    # TODO - Consider removing @free_sockets in least- to
    # most-recently used order.
    while ($currently_open >= $self->[SF_MAX_OPEN]) {
      last QUEUED unless @free_sockets;
      my $next_to_go = $free_sockets[rand(@free_sockets)];
      $self->_remove_socket_from_pool($next_to_go);
      $currently_open--;
    }

    # Start the request.  Create a wheel to begin the connection.
    # Move the wheel and its request into SF_WHEELS.
    log_warnf("Found enqueued request: %d Creating wheel...", $request->[RQ_ID]);
    DEBUG and warn "WAKEUP: creating wheel for $req_key";

    my $addr = ($request->[RQ_IP] or $request->[RQ_ADDRESS]);
    my $wheel = POE::Wheel::SocketFactory->new(
      (
        defined($self->[SF_BIND_ADDR])
        ? (BindAddress => $self->[SF_BIND_ADDR])
        : ()
      ),
      RemoteAddress => $addr,
      RemotePort    => $request->[RQ_PORT],
      SuccessEvent  => "ka_conn_success",
      FailureEvent  => "ka_conn_failure",
      SocketDomain  => $request->[RQ_ADDR_FAM],
    );
    
    #Make the connecting wheel dependent on the request ID..    
    $self->[SF_WHEELS]->store_kt($request, KEY_REQOBJ, $wheel, StrongValue => 1);
    $self->[SF_WHEELS]->store_kt($wheel->ID, KEY_WID, $wheel);
    $self->[SF_REQ_INDEX]->store_kt($wheel, KEY_WHEELOBJ, $request);
    
    # store the wheel's ID in the request object
    $request->[RQ_WHEEL_ID] = $wheel->ID;

    # Count it as used, so we don't over commit file handles.
    $currently_open++;
    $self->[SF_USED_EACH]{$req_key}++;

    # Mark the request index as one to splice out.

    push @splice_list, $request_index;
  }
  continue {
    $request_index++;
  }

  # The @splice_list is a list of element indices that need to be
  # spliced out of the request queue.  We scan in backwards, from
  # highest index to lowest, so that each splice does not affect the
  # indices of the other.
  #
  # This removes the request from the queue.  It's vastly important
  # that the request be entered into SF_WHEELS before now.
  
  my $splice_index = @splice_list;
  while ($splice_index--) {
    splice @{$self->[SF_QUEUE]}, $splice_list[$splice_index], 1;
  }
}

sub allocate {
  my $self = shift;
  croak "allocate() needs an even number of parameters" if @_ % 2;
  my %args = @_;

  # TODO - Validate arguments.

  my $scheme  = delete $args{scheme};
  croak "allocate() needs a 'scheme'"  unless $scheme;
  my $address = delete $args{addr};
  croak "allocate() needs an 'addr'"   unless $address;
  my $port    = delete $args{port};
  croak "allocate() needs a 'port'"    unless $port;
  my $event   = delete $args{event};
  croak "allocate() needs an 'event'"  unless $event;
  my $context = delete $args{context};
  croak "allocate() needs a 'context'" unless $context;
  my $timeout = delete $args{timeout};
  $timeout    = $self->[SF_TIMEOUT]    unless $timeout;

  my $for_scheme  = delete($args{for_scheme}) || $scheme;
  my $for_address = delete($args{for_addr}) || $address;
  my $for_port    = delete($args{for_port}) || $port;

  croak "allocate() on shut-down connection manager" if $self->[SF_SHUTDOWN];

  my @unknown = sort keys %args;
  if (@unknown) {
    croak "allocate() doesn't accept: @unknown";
  }

  my $conn_key = (
    "$scheme $address $port for $for_scheme $for_address $for_port"
  );
  log_err("Request called for '$conn_key'");
  # If we have a connection pool for the scheme/address/port triple,
  # then we can maybe post an available connection right away.

  my $existing_connection = $self->_check_free_pool($conn_key);
  if (defined $existing_connection) {
    log_warn("Request for $conn_key immediately allocated");
    $poe_kernel->post(
      $poe_kernel->get_active_session,
      $event => {
        addr       => $address,
        context    => $context,
        port       => $port,
        scheme     => $scheme,
        connection => $existing_connection,
        from_cache => "immediate",
      }
    );
    return;
  }

  # We can't honor the request immediately, so it's put into a queue.
  DEBUG and warn "ALLOCATE: enqueuing request for $conn_key";
  my $rqid = ++$CurrentID;
  my $request = [
    $poe_kernel->get_active_session(),  # RQ_SESSION
    $event,       # RQ_EVENT
    $scheme,      # RQ_SCHEME
    $address,     # RQ_ADDRESS
    undef,        # RQ_IP
    $port,        # RQ_PORT
    $conn_key,    # RQ_CONN_KEY
    $context,     # RQ_CONTEXT
    $timeout,     # RQ_TIMEOUT
    time(),       # RQ_START
    undef,        # RQ_TIMER_ID
    undef,        # RQ_WHEEL_ID
    1,            # RQ_ACTIVE
    $rqid, # RQ_ID
    undef,        # RQ_ADDR_FAM
    $for_scheme,  # RQ_FOR_SCHEME
    $for_address, # RQ_FOR_ADDRESS
    $for_port,    # RQ_FOR_PORT
  ];
  
  $self->[SF_REQ_INDEX]->store_kt($rqid, KEY_REQID, $request, StrongValue => 1);

  $poe_kernel->refcount_increment(
    $request->[RQ_SESSION]->ID(),
    "poco-client-keepalive"
  );

  $poe_kernel->call("$self", ka_set_timeout     => $request);
  $poe_kernel->call("$self", ka_resolve_request => $request);

  return $request->[RQ_ID];
}

sub deallocate {
  my ($self, $req_id) = @_;
  
  my $request = $self->[SF_REQ_INDEX]->purgeby_kt($req_id, KEY_REQID);
  
  croak "deallocate() requires a request ID" unless defined $request;

  # Now pass the vetted request & its ID into our manager session.
  $poe_kernel->call("$self", "ka_deallocate", $request, $req_id);
}

sub _ka_deallocate {
  my ($self, $heap, $request, $req_id) = @_[OBJECT, HEAP, ARG0, ARG1];
  
  my $conn_key = $request->[RQ_CONN_KEY];
  my $existing_connection = $self->_check_free_pool($conn_key);
  
  # Existing connection.  Remove it from the pool, and delete the socket.
  if (defined $existing_connection) {
    $self->_remove_socket_from_pool($existing_connection->{socket});
    DEBUG_DEALLOCATE and warn(
      "deallocate called, deleted already-connected socket"
    );
    return;
  }

  # No connection yet.  Cancel the request.
  DEBUG_DEALLOCATE and warn(
    "deallocate called without an existing connection.  ",
    "cancelling connection request"
  );

  unless (exists $heap->{resolve}->{$request->[RQ_ADDRESS]}) {
    DEBUG_DEALLOCATE and warn(
      "deallocate cannot cancel dns -- no pending request"
    );
    return;
  }

  if ($heap->{resolve}->{$request->[RQ_ADDRESS]} eq 'cancelled') {
    DEBUG_DEALLOCATE and warn(
      "deallocate cannot cancel dns -- request already cancelled"
    );
    return;
  }

  $poe_kernel->call( "$self", ka_cancel_dns_response => $request );
  return;
}

sub _ka_cancel_dns_response {
  my ($self, $kernel, $heap, $request) = @_[OBJECT, KERNEL, HEAP, ARG0];

  my $address = $request->[RQ_ADDRESS];
  DEBUG_DNS and warn "DNS: canceling request for $address\n";
  my $requests = $heap->{resolve}{$address};

  # Remove the resolver request for the address of this connection
  # request

  my $req_index = @$requests;
  while ($req_index--) {
    next unless $requests->[$req_index] == $request;
    splice(@$requests, $req_index, 1);
    last;
  }

  # Clean up the structure for the address if there are no more
  # requests to resolve that address.

  unless (@$requests) {
    DEBUG_DNS and warn "DNS: canceled all requests for $address";
    $heap->{resolve}{$address} = 'cancelled';
  }

  # cancel our attempt to connect
  $poe_kernel->alarm_remove( $request->[RQ_TIMER_ID] );
  $poe_kernel->refcount_decrement(
    $request->[RQ_SESSION]->ID(), "poco-client-keepalive"
  );
}

# Set the request's timeout, in the component's context.

sub _ka_set_timeout {
  my ($kernel, $request) = @_[KERNEL, ARG0];
  $request->[RQ_TIMER_ID] = $kernel->delay_set(
    ka_request_timeout => $request->[RQ_TIMEOUT], $request
  );
}

# The request has timed out.  Mark it as defunct, and respond with an
# ETIMEDOUT error.

sub _ka_request_timeout {
  my ($self, $kernel, $request) = @_[OBJECT, KERNEL, ARG0];
  log_warnf("Request (ID=%d) timed out", $request->[RQ_ID]);
  DEBUG and warn(
    "CON: request from session ", $request->[RQ_SESSION]->ID,
    " for address ", $request->[RQ_ADDRESS], " timed out"
  );
  $! = ETIMEDOUT;

  # The easiest way to do this?  Simulate an error from the wheel
  # itself.

  if (defined $request->[RQ_WHEEL_ID]) {
    @_[ARG0..ARG3] = ("connect", $!+0, "$!", $request->[RQ_WHEEL_ID]);
    goto &_ka_conn_failure;
  }

  # But what if there is no wheel?
  _respond_with_error($request, "connect", $!+0, "$!"),
}

# Connection failed.  Remove the SF_WHEELS record corresponding to the
# request.  Remove the SF_USED placeholder record so it won't count
# anymore.  Send a failure notice to the requester.

sub _ka_conn_failure {
  my ($self, $func, $errnum, $errstr, $wheel_id) = @_[OBJECT, ARG0..ARG3];
  
  DEBUG and warn "CON: sending $errstr for function $func";
  # Remove the SF_WHEELS record.
  
  my $wheel = $self->[SF_WHEELS]->purgeby_kt($wheel_id, KEY_WID);
  my $ski = $self->[SF_SOCKETS]->fetch_kt($wheel, KEY_WHEELOBJ);
  my $request = $self->[SF_REQ_INDEX]->purgeby_kt($wheel, KEY_WHEELOBJ);
  
  $self->_ski_remove($ski);
  
  # Discount the use by request key, removing the SF_USED record
  # entirely if it's now moot.
  my $request_key = $request->[RQ_CONN_KEY];
  $self->_decrement_used_each($request_key);

  # Tell the requester about the failure.
  _respond_with_error($request, $func, $errnum, $errstr),
}

# Connection succeeded.  Remove the SF_WHEELS record corresponding to
# the request.  Flesh out the placeholder SF_USED record so it counts.

sub _ka_conn_success {
  my ($self, $socket, $wheel_id) = @_[OBJECT, ARG0, ARG3];
  
  my $wheel = $self->[SF_WHEELS]->purgeby_kt($wheel_id, KEY_WID);
  my $request = $self->[SF_REQ_INDEX]->purgeby_kt($wheel, KEY_WHEELOBJ);
  # Remove the SF_WHEELS record.
  
  if ($request->[RQ_SCHEME] eq 'https') {
    unless ($ssl_available) {
      die "There is no SSL support, please install POE::Component::SSLify";
    }
    eval {
      $socket = POE::Component::SSLify::Client_SSLify($socket);
    };
    if ($@) {
      _respond_with_error($request, "sslify", undef, "$@");
      return;
    }
  }
  
  my $ski = [
    $socket, #SKI_SOCKET,
    $request->[RQ_CONN_KEY], #SKI_KEY,
    time(), #SKI_ATIME,
    undef, #SKI_TIMER
  ];
  
  $self->[SF_SOCKETS]->store_kt($socket, KEY_SOCKET, $ski, StrongValue => 1);
  $self->_ski_mark_used($ski);
  
  DEBUG and warn(
    "CON: posting... to $request->[RQ_SESSION] . $request->[RQ_EVENT]"
  );

  # Build a connection object around the socket.
  my $connection = POE::Component::Connection::Keepalive->new(
    socket  => $socket,
    manager => $self,
  );
  $self->[SF_SOCKETS]->store_kt($connection, KEY_CONNOBJ,
                                $socket, StrongValue => 1);
  # Give the socket to the requester.
  _respond(
    $request, {
      connection => $connection,
    }
  );
}

# The user is done with a socket.  Make it available for reuse.

sub free {
  my ($self, $socket) = @_;
  return if $self->[SF_SHUTDOWN];
  DEBUG and warn "FREE: freeing socket";
  if(!$socket) {
    warn "Don't have socket!";
    return;
  }
  my $ski = $self->[SF_SOCKETS]->fetch_kt($socket, KEY_SOCKET);
  # Remove the accompanying SF_USED record.
  croak "can't free() undefined socket" unless defined $ski;
  
  $poe_kernel->call("$self", "ka_reclaim_socket", $ski);
  
  # Avoid returning things by mistake.
  return;
}

# A sink for deliberately unhandled events.

sub _ka_ignore_this_event {
  # Do nothing.
}

# An internal method to fetch a socket from the free pool, if one
# exists.



sub _ski_mark_used {
  my ($self,$ski) = @_;
  #cluck("Telling you how we got here");
  log_warn("Marking $ski as used");
  my $table = $self->[SF_SOCKETS];
  my $key = $ski->[SKI_KEY];
  $table->store_a(1, ATTR_SOCKET_USED, $ski);
  $table->store_a($key, ATTR_CONNKEY_BUSY, $ski);  

  $table->dissoc_a(1, ATTR_SOCKET_FREE, $ski);
  $table->dissoc_a($key, ATTR_CONNKEY_FREE, $ski);
  
}

sub _ski_mark_free {
  my ($self,$ski) = @_;
  log_warn("Marking $ski as free");
  my $table = $self->[SF_SOCKETS];
  my $key = $ski->[SKI_KEY];
  $table->store_a(1, ATTR_SOCKET_FREE, $ski);
  $table->store_a($key, ATTR_CONNKEY_FREE, $ski);
  
  $table->dissoc_a(1, ATTR_SOCKET_USED, $ski);
  $table->dissoc_a($key, ATTR_CONNKEY_BUSY, $ski);
  
}

sub _check_free_pool {
  my ($self, $conn_key) = @_;
  
  #Get all free sockets for this connection
  log_err("Fetching free list");
  my @free = $self->[SF_SOCKETS]->fetch_a($conn_key, ATTR_CONNKEY_FREE);
  log_err("Done!");
  return unless @free;
  
  my $ski = shift @free;
  
  #mark as used  
  $self->_ski_mark_used($ski);
  
  DEBUG and warn "CHECK: reusing $conn_key";

  # _check_free_pool() may be operating in another session, so we call
  # the correct one here.
  
  
  $ski->[SKI_ATIME] = time();
  $self->[SF_USED_EACH]{$conn_key}++;
  $poe_kernel->call("$self", "ka_relinquish_socket", $ski);
  
    # Build a connection object around the socket.
    my $connection = POE::Component::Connection::Keepalive->new(
      socket  => $ski->[SKI_SOCKET],
      manager => $self,
    );
    
  return $connection;
}

sub _decrement_used_each {
  my ($self, $request_key) = @_;
  unless (--$self->[SF_USED_EACH]{$request_key}) {
    delete $self->[SF_USED_EACH]{$request_key};
    log_err("Nothing left for $request_key");
  }
}

# Reclaim a socket.  Put it in the free socket pool, and wrap it with
# select_read() to discard any data and detect when it's closed.

sub _ka_reclaim_socket {
  my ($self, $kernel, $ski) = @_[OBJECT, KERNEL, ARG0];
  log_err("Reclaim=$ski");
  my $socket = $ski->[SKI_SOCKET];
    
  # Decrement the usage counter for the given connection key.
  my $request_key = $ski->[SKI_KEY];
  $self->_decrement_used_each($request_key);
  
  if(!defined fileno $socket) {
    DEBUG and warn "RECLAIM: freed socket has previously been closed";
    $self->_ski_remove($ski);
    goto &_ka_wake_up;
  }
  
  # Socket is still open.  Check for lingering data.
  DEBUG and warn "RECLAIM: checking if socket still works";

  # Check for data on the socket, which implies that the server
  # doesn't know we're done.  That leads to desynchroniziation on the
  # protocol level, which strongly implies that we can't reuse the
  # socket.  In this case, we'll make a quick attempt at fetching all
  # the data, then close the socket.

  my $rin = '';
  vec($rin, fileno($socket), 1) = 1;
  my ($rout, $eout);
  my $socket_is_active = select ($rout=$rin, undef, $eout=$rin, 0);

  if ($socket_is_active) {
    DEBUG and warn "RECLAIM: socket is still active; trying to drain";
    use bytes;

    my $socket_had_data = sysread($socket, my $buf = "", 65536) || 0;
    DEBUG and warn "RECLAIM: socket had $socket_had_data bytes. 0 means EOF";
    DEBUG and warn "RECLAIM: Giving up on socket.";

    # Avoid common FIN_WAIT_2 issues, but only for valid sockets.
    #if ($socket_had_data and fileno($socket)) {
    if ($socket_had_data) {
      my $opt_result = setsockopt(
        $socket, SOL_SOCKET, SO_LINGER, pack("sll",1,0,0)
      );
      die "setsockopt: " . ($!+0) . " $!" if (not $opt_result and $!  != EBADF);
    }
    $self->_ski_remove($ski);
    goto &_ka_wake_up;
  }

  # Socket is alive and has no data, so it's in a quiet, theoretically
  # reclaimable state.

  DEBUG and warn "RECLAIM: reclaiming socket";

  # Watch the socket, and set a keep-alive timeout.
  $kernel->select_read($socket, "ka_socket_activity");
  
  my $ski_to = $ski;
  weaken($ski_to);
  if(!defined $ski->[SKI_TIMER]) {
    $ski->[SKI_TIMER] = $kernel->delay_set(
      ka_keepalive_timeout => $self->[SF_KEEPALIVE], $ski_to
    );
  }
  
  $self->_ski_mark_free($ski);
  
  goto &_ka_wake_up;
}

# Socket timed out.  Discard it.

sub _ka_keepalive_timeout {
  my ($self, $ski) = @_[OBJECT, ARG0];
  log_err("Timeout triggered!");
  $self->_ski_remove($ski);
}

# Relinquish a socket.  Stop selecting on it.

sub _ka_relinquish_socket {
  my ($kernel, $ski) = @_[KERNEL, ARG0];
  my $sock = $ski->[SKI_SOCKET];
  log_warn("RELINQUISH: $ski $sock");
  $kernel->alarm_remove($ski->[SKI_TIMER]) if defined $ski->[SKI_TIMER];
  $ski->[SKI_TIMER] = undef;
  
  $kernel->select_read($sock, undef) if defined $sock;
}

# Shut down the component.  Release any sockets we're currently
# holding onto.  Clean up any timers.  Remove the alias it's known by.

sub shutdown {
  my $self = shift;
  return if $self->[SF_SHUTDOWN];
  $poe_kernel->call("$self", "ka_shutdown");
}

sub _ka_shutdown {
  my ($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];

  return if $self->[SF_SHUTDOWN];

  $instances--;

  # Clean out the request queue.
  foreach my $request (@{$self->[SF_QUEUE]}) {
    $self->_shutdown_request($kernel, $request);
  }
  $self->[SF_QUEUE] = [ ];
  # Clean out the socket pool.
  
  #TODO: Implement 'all values' or whatever API function for HR
  
  my @skis = $self->[SF_SOCKETS]->fetch_a(1, ATTR_SOCKET_FREE);
  foreach my $ski (@skis) {
    $self->_ski_remove($ski);
  }
  log_err("Have SKIs", @skis);
  @skis = ();
  
  my @open = $self->[SF_SOCKETS]->fetch_a(1, ATTR_SOCKET_FREE);
  log_err("REMAINING SKIs", @open);
  log_err(Dumper($self->[SF_SOCKETS]));
  
  # Stop any pending resolver requests.
  foreach my $host (keys %{$heap->{resolve}}) {
    if ($heap->{resolve}{$host} eq 'cancelled') {
      DEBUG and warn "SHT: Skipping shutdown for $host (already cancelled)";
      next;
    }
    DEBUG and warn "SHT: Shutting down resolver requests for $host";
    foreach my $request (@{$heap->{resolve}{$host}}) {
      $self->_shutdown_request($kernel, $request);
    }
  }
  $heap->{resolve} = { };

  # Shut down the resolver.
  DEBUG and warn "SHT: Shutting down resolver";
  if ( $self->[SF_RESOLVER] != $default_resolver ) {
	  $self->[SF_RESOLVER]->shutdown();
  }
  $self->[SF_RESOLVER] = undef;

  if ( $default_resolver and !$instances ) {
    $default_resolver->shutdown();
    $default_resolver = undef;
  }

  # Finish keepalive's shutdown.
  $kernel->alias_remove("$self");
  $self->[SF_SHUTDOWN] = 1;
  
  return;
}

sub _shutdown_request {
  my ($self, $kernel, $request) = @_;
  $self->[SF_REQ_INDEX]->delete_value($request);
  
  if (defined $request->[RQ_TIMER_ID]) {
    DEBUG and warn "SHT: Shutting down resolver timer $request->[RQ_TIMER_ID]";
    $kernel->alarm_remove($request->[RQ_TIMER_ID]);
  }
  
  if (defined $request->[RQ_WHEEL_ID]) {
    DEBUG and warn "SHT: Shutting down resolver wheel $request->[RQ_TIMER_ID]";
    delete $self->[SF_WHEELS]{$request->[RQ_WHEEL_ID]};
  }

  if (defined $request->[RQ_SESSION]) {
    my $session_id = $request->[RQ_SESSION]->ID;
    DEBUG and warn "SHT: Releasing session $session_id";
    $kernel->refcount_decrement($session_id, "poco-client-keepalive");
  }
}

# A socket in the free pool has activity.  Read from it and discard
# the output.  Discard the socket on error or remote closure.

sub _ka_socket_activity {
  my ($self, $kernel, $socket) = @_[OBJECT, KERNEL, ARG0];
  my $ski = $self->[SF_SOCKETS]->fetch_kt($socket, KEY_SOCKET);
  
  if (DEBUG) {
    my $key = $ski->[SKI_KEY];
    if(!$key) {
      print Dumper($ski);
      die "SKI without key!";
    }
    warn "CON: Got activity on socket for $key";
  }

  # Any socket activity on a kept-alive socket implies that the socket
  # is no longer reusable.

  use bytes;
  my $socket_had_data = sysread($socket, my $buf = "", 65536) || 0;
  DEBUG and warn "CON: socket had $socket_had_data bytes. 0 means EOF";
  DEBUG and warn "CON: Removing socket from the pool";
  $self->_ski_remove($ski);  
}

sub _ka_resolve_request {
  my ($self, $kernel, $heap, $request) = @_[OBJECT, KERNEL, HEAP, ARG0];

  my $host = $request->[RQ_ADDRESS];

  # Skip DNS resolution if it's already a dotted quad.
  # ip_is_ipv4() doesn't require quads, so we count the dots.
  #
  # TODO - Do the same for IPv6 addresses containing colons?
  # TODO - Would require AF_INET6 support around the SocketFactory.
  if ((($host =~ tr[.][.]) == 3) and ip_is_ipv4($host)) {
    DEBUG_DNS and warn "DNS: $host is a dotted quad; skipping lookup";
    $kernel->call("$self", ka_add_to_queue => $request);
    return;
  }

  # It's already pending DNS resolution.  Combine this with previous.
  if (exists $heap->{resolve}->{$host}) {
    DEBUG_DNS and warn "DNS: $host is piggybacking on a pending lookup.\n";
    push @{$heap->{resolve}->{$host}}, $request;
    return;
  }

  # New request.  Start lookup.
  $heap->{resolve}->{$host} = [ $request ];

  my $response = $self->[SF_RESOLVER]->resolve(
    event   => 'ka_dns_response',
    host    => $host,
    service => $request->[RQ_SCHEME],
  );

  DEBUG_DNS and warn "DNS: looking up $host in the background.\n";
}

sub _ka_dns_response {
  my ($self, $kernel, $heap, $response_error, $addresses, $request) = @_[
    OBJECT, KERNEL, HEAP, ARG0..ARG2
  ];

  # We've shut down.  Nothing to do here.
  return if $self->[SF_SHUTDOWN];

  my $request_address = $request->{host};
  my $requests = delete $heap->{resolve}->{$request_address};

  DEBUG_DNS and warn "DNS: got response for request address $request_address";

  # Requests on record.
  if (defined $requests) {
    # We can receive responses for canceled requests.  Ignore them: we
    # cannot cancel PoCo::Client::DNS requests, so this is how we reap
    # them when they're canceled.
    if ($requests eq 'cancelled') {
      DEBUG_DNS and warn "DNS: reaping cancelled request for $request_address";
      return;
    }
    unless (ref $requests eq 'ARRAY') {
      die "DNS: got an unknown requests for $request_address: $requests";
    }
  }
  else {
    die "DNS: Unexpectedly undefined requests for $request_address";
  }

  # This is an error.  Cancel all requests for the address.
  # Tell everybody that their requests failed.
  if ($response_error) {
    DEBUG_DNS and warn "DNS: resolver error = $response_error";
    foreach my $request (@$requests) {
      _respond_with_error($request, "resolve", undef, $response_error),
    }
    return;
  }

  DEBUG_DNS and warn "DNS: got a response";

  # A response!
  foreach my $address_rec (@$addresses) {
    my $numeric = $self->[SF_RESOLVER]->unpack_addr($address_rec);

    DEBUG_DNS and warn "DNS: $request_address resolves to $numeric";

    foreach my $request (@$requests) {
      # Don't bother continuing inactive requests.
      next unless $request->[RQ_ACTIVE];
      $request->[RQ_IP] = $numeric;
      $request->[RQ_ADDR_FAM] = $address_rec->{family};
      log_warn("Adding to queue: $request");
      $kernel->yield(ka_add_to_queue => $request);
    }

    # Return after the first good answer.
    return;
  }

  # Didn't return here.  No address record for the host?
  foreach my $request (@$requests) {
    DEBUG_DNS and warn "DNS: $request_address does not resolve";
    _respond_with_error($request, "resolve", undef, "Host has no address."),
  }
}


sub _ka_add_to_queue {
  my ($self, $kernel, $request) = @_[OBJECT, KERNEL, ARG0];

  push @{ $self->[SF_QUEUE] }, $request;

  # If the queue has more than one request in it, then it already has
  # a wakeup event pending.  We don't need to send another one.
  my $qsize = @{$self->[SF_QUEUE]};
  log_err("Queue size is $qsize");
  return if @{$self->[SF_QUEUE]} > 1;
  
  # If the component's allocated socket count is maxed out, then it
  # will check the queue when an existing socket is released.  We
  # don't need to wake it up here.
  my $use_count = $self->[SF_SOCKETS]->fetch_a(1, ATTR_SOCKET_USED) || 0;
  log_errf("Use count: %d, MAX=%d", $use_count, $self->[SF_MAX_OPEN]);
  
  return if $use_count >= $self->[SF_MAX_OPEN];

  # Likewise, we shouldn't awaken the session if there are no
  # available slots for the given scheme/address/port triple.  "|| 0"
  # to avoid an undef error.
  my $conn_key = $request->[RQ_CONN_KEY];
  
  log_errf("Max per host: %d", $self->[SF_MAX_HOST]);
  log_errf("Current for key '%s': %d", $conn_key, $self->[SF_USED_EACH]{$conn_key});
  return if (
    ($self->[SF_USED_EACH]{$conn_key} || 0) >= $self->[SF_MAX_HOST]
  );

  # Wake the session up, and return nothing, signifying sound and fury
  # yet to come.
  DEBUG and warn "posting wakeup for $conn_key";
  $poe_kernel->post("$self", "ka_wake_up");
  return;
}

# Remove a socket from the free pool, by the socket handle itself.
sub _ski_remove {
  my ($self,$ski) = @_;
  log_err("Removing $ski");
  $self->[SF_SOCKETS]->delete_value($ski);
  my $sock = delete $ski->[SKI_SOCKET];
  $poe_kernel->alarm_remove($ski->[SKI_TIMER]) if defined $ski->[SKI_TIMER];
  if(defined $sock and defined fileno $sock) {
    $poe_kernel->select_read($sock, undef);
    close($sock);
  } else {
    log_err("Socket for $ski is invalid!");
  }
  log_warn("Socket is $sock");
}

sub _remove_socket_from_pool {
  my ($self, $socket) = @_;
  my $ski = $self->[SF_SOCKETS]->fetch_kt($socket, KEY_SOCKET);
  $self->_ski_remove($ski);
  
  # Avoid common FIN_WAIT_2 issues.
  # Commented out because fileno() will return true for closed
  # sockets, which makes setsockopt() highly unhappy.  Also, SO_LINGER
  # will cause te socket closure to block, which is less than ideal.
  # We need to revisit this another way, or just let sockets enter
  # FIN_WAIT_2.

#  if (fileno $socket) {
#    setsockopt($socket, SOL_SOCKET, SO_LINGER, pack("sll",1,0,0)) or die(
#      "setsockopt: $!"
#    );
#  }
}

# Internal function.  NOT AN EVENT HANDLER.

sub _respond_with_error {
  my ($request, $func, $num, $string) = @_;
  _respond(
    $request,
    {
      connection => undef,
      function   => $func,
      error_num  => $num,
      error_str  => $string,
    }
  );
}

sub _respond {
  my ($request, $fields) = @_;

  # Bail out early if the request isn't active.
  return unless $request->[RQ_ACTIVE] and $request->[RQ_SESSION];

  $poe_kernel->post(
    $request->[RQ_SESSION],
    $request->[RQ_EVENT],
    {
      addr        => $request->[RQ_ADDRESS],
      context     => $request->[RQ_CONTEXT],
      port        => $request->[RQ_PORT],
      scheme      => $request->[RQ_SCHEME],
      for_addr    => $request->[RQ_FOR_ADDRESS],
      for_scheme  => $request->[RQ_FOR_SCHEME],
      for_port    => $request->[RQ_FOR_PORT],
      %$fields,
    }
  );

  # Drop the extra refcount.
  $poe_kernel->refcount_decrement(
    $request->[RQ_SESSION]->ID(),
    "poco-client-keepalive"
  );

  # Remove associated timer.
  if ($request->[RQ_TIMER_ID]) {
    $poe_kernel->alarm_remove($request->[RQ_TIMER_ID]);
    $request->[RQ_TIMER_ID] = undef;
  }

  # Deactivate the request.
  $request->[RQ_ACTIVE] = undef;
}

1;
