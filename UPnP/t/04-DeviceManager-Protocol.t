# This file checks that the HTTP, UDP, GENA and SOAP messages sent by
# the UPnP::DeviceManager module match the UPnP specification.  It
# creates a DeviceManager instance in a child thread and simulates a
# ControlPoint in the main thread, checking the messages sent across
# for validity.

use Test::More;

use constant NOTIFICATION_PORT => 8989;
use constant SEARCH_PORT => 8990;
use constant SUBSCRIPTION_PORT => 8991;
use constant DEVICE_PORT => 8992;

# Prepend all tests with triple hash marks to dynamically
# calculate the number of tests.
open(ME,$0) or die $!;
my $TestCount = grep(/\#\#\#/,<ME>);
close(ME);

use UPnP::DeviceManager;
use UPnP::Common;
use Socket;
use IO::Select;
use IO::Handle;
use HTTP::Daemon;
use LWP::UserAgent;
use SOAP::Lite;

my $spin = 1;
my $ssdpTestDone = 0;
my $searchTestDone = 0;
my $firstNotification = 1;
my $sid;

$SIG{INT} = $SIG{KILL} = sub { $spin = 0 };

# Create a socket pair for IPC between the parent and child
# processes created below.
my ($child, $parent) = 
    IO::Socket->socketpair( AF_UNIX, SOCK_STREAM, PF_UNSPEC ) 
    or die "Cannot create socketpair: $!";
$child->autoflush(1);
$parent->autoflush(1);

my ($ssdpSocket, $searchSocket, $subscriptionSocket);

# We need to fork to create a DeviceManager. Don't worry, we'll join
# before quitting. Also, we'll make sure that we only output from the
# parent process.
my $pid = fork();
die "fork() failed: $!" unless defined $pid;
if ($pid) {
    # Parent process is the protocol tester.
    close $parent;

    plan tests => $TestCount;

    # Create a socket on which we can hear the DeviceManager's SSDP
    # events
    $ssdpSocket = IO::Socket::INET->new(Proto => 'udp',
					Reuse => 1,
					LocalPort => SSDP_PORT) ||
	die("Error creating SSDP multicast listen socket: $!\n");
    my $ip_mreq = inet_aton(SSDP_IP) . INADDR_ANY;
    setsockopt($ssdpSocket, 
	       IP_LEVEL,
	       IP_ADD_MEMBERSHIP,
	       $ip_mreq);
    setsockopt($ssdpSocket, 
	       IP_LEVEL,
	       IP_MULTICAST_TTL,
	       pack 'I', 4);
    
    # Create the socket on which search requests go out
   $searchSocket = IO::Socket::INET->new(Proto => 'udp',
					 LocalPort => SEARCH_PORT) ||
	die("Error creating search socket: $!\n");
	setsockopt($searchSocket, 
		   IP_LEVEL,
		   IP_MULTICAST_TTL,
		   pack 'I', 4);

    # Create the socket on which we'll listen for events to which we are
    # subscribed.
    $subscriptionSocket = HTTP::Daemon->new(LocalPort => SUBSCRIPTION_PORT) ||
	die("Error creating subscription socket: $!\n");

    my $select = IO::Select->new($ssdpSocket, 
				 $searchSocket, 
				 $subscriptionSocket);

    $child->print("\n");

    eval {
	while ($spin) {
	    my @rsocks = $select->can_read(1);
	    for my $sock (@rsocks) {
		if ($sock == $ssdpSocket) {
		    testSSDPEvent($sock);
		}
		elsif ($sock == $searchSocket) {
		    testSearchResponse($sock);
		}
		elsif ($sock == $subscriptionSocket) {
		    testNotification($sock);
		}
	    }
	}
    };

    $child->print("q\n");

    close $child;
    wait;
}
else {
    # Child process will be the DeviceManager.
    close $child;
    my $select = IO::Select->new($parent);
    my $timeout = 1;
    my $state = 0;
    my ($dm, $device, $service);

    while ($spin) {
	my @rsocks = $select->can_read($timeout);
	for my $sock (@rsocks) {
	    if ($sock == $parent) {
		my $line = $sock->getline;
		if ($line && $line eq "q\n") {
		    $spin = 0;
		}
		elsif (++$state == 1) {
		    $dm = UPnP::DeviceManager->new(NotificationPort => 
						   NOTIFICATION_PORT);
		    $device = $dm->registerDevice(
				    DevicePort => DEVICE_PORT,
				    DescriptionFile => './t/description1.xml',
				    ResourceDirectory => './t');
		    $select->add($dm->sockets());
		    $service = $device->getService(
				    'urn:upnp-org:serviceId:RenderingControl');
		    $service->onAction(sub {
			my ($service, $action, $arg) = @_;
			if ($action eq 'ListPresets' && $arg == 5) {
			    return 'foo';
			}
			return 'bar';
		    });
		    $service->setValue('LastChange' => 'yesterday');
		    $device->start;
		}
		elsif ($state == 2) {
		    $service->setValue('LastChange' => 'today');
		}
	    }
	    elsif (defined($dm)) {
		$dm->handleOnce($sock);
	    }
	}
	if (defined($dm)) {
	    $timeout = $dm->heartbeat;
	}
    }

    close $parent;
}

sub testSSDPEvent {
    my $sock = shift;
    my $buf = '';
    
    my $peer = recv($sock, $buf, 2048, 0);
    my ($port, $iaddr) = sockaddr_in($peer);

    # Only listen to events that originated from this process
    if (!$ssdpTestDone && ($port == NOTIFICATION_PORT) &&
	(inet_ntoa($iaddr) eq UPnP::Common::getLocalIP())) {

	# Section 1.1.2 of the UPnP Architecture document
	# 'Discovery: Advertisement: Device available -- NOTIFY with ssdp:alive'
	diag("Testing Section 1.1.2");

	### Confirm that we got a full HTTP header
	ok( $buf =~ /\015?\012\015?\012/, 'Checking for full HTTP header' ) || 
	    return;

	$buf =~ s/^(?:\015?\012)+//;  # ignore leading blank lines
	### Confirm that we got a good first line
	ok( $buf =~ 
	    s/^(\S+)[ \t]+(\S+)(?:[ \t]+(HTTP\/\d+\.\d+))?[^\012]*\012//,
	    'Checking first line of header' ) || return;

	### Confirm that we got a NOTIFY
	is ($1, 'NOTIFY', 'HTTP method');

	### Confirm that the resource is *
	is ($2, '*', 'HTTP resource');

	my $headers = UPnP::Common::parseHTTPHeaders($buf);
	
	### Check the HOST header
	is ($headers->header('HOST'), '239.255.255.250:1900', 'HOST header');

	### Check the Cache-control header
	cmp_ok ($headers->header('Cache-control'), '=~',
		'max-age ?=', 'Cache-control header');

	### Check the Location header
	is( $headers->header('Location'), 
	    'http://' . UPnP::Common::getLocalIP() . ':' . DEVICE_PORT . '/description.xml',
	    'Location header' );

	### Check the NT header
	# We won't check its value, since we don't know what we'll 
	# get first (UDP datagram ordering is not guaranteed...
	# though it probably is through the loopback device).
	ok (defined($headers->header('NT')), 'NT header');

	### Check the NTS header
	is ($headers->header('NTS'), 'ssdp:alive', 'NTS header');

	### Check the Server header
	ok (defined($headers->header('Server')), 'Server header');

	### Check the USN header
	cmp_ok ($headers->header('USN'), '=~',
		'uuid:Perl-UPnP-Test-Device1', 'USN header');

	my $header = 'M-SEARCH * HTTP/1.1' . CRLF .
		'HOST: ' . SSDP_IP . ':' . SSDP_PORT . CRLF .
		'MAN: "ssdp:discover"' . CRLF .
		'ST: uuid:Perl-UPnP-Test-Device1' . CRLF .
		'MX: 3' . CRLF .
		CRLF;

	my $destaddr = sockaddr_in(SSDP_PORT, inet_aton(SSDP_IP));
	send($searchSocket, $header, 0, $destaddr);

	$ssdpTestDone = 1;
    }
}

sub testSearchResponse {
    my $sock = shift;
    my $buf = '';

    recv($sock, $buf, 2048, 0);

    if (!$searchTestDone) {
	# Section 1.2.3 of the UPnP Architecture document
	# 'Discovery: Search: Response'
	diag("Testing Section 1.2.3");
	
	### Confirm that we got a full HTTP header
	ok( $buf =~ /\015?\012\015?\012/, 'Checking for full HTTP header' ) || 
	    return;
	
	$buf =~ s/^(?:\015?\012)+//;  # ignore leading blank lines
	### Confirm that we got a good first line
	ok( $buf =~ 
	    s/^(\S+)[ \t]+(\S+)[ \t]+(\S+)[^\012]*\012//,
	    'Checking first line of header' ) || return;
	
	my $headers = UPnP::Common::parseHTTPHeaders($buf);
	
	### Success code
	is( $2, 200, 'HTTP return code' );
	
	### Check the Cache-control header
	cmp_ok ($headers->header('Cache-control'), '=~',
		'max-age ?=', 'Cache-control header');
	
	### Check the EXT header
	ok( defined($headers->header('EXT')), 'EXT header' );
	
	### Check the Location header
	is( $headers->header('Location'), 
	    'http://' . UPnP::Common::getLocalIP() . ':' . DEVICE_PORT . '/description.xml',
	    'Location header' );
	
	### Check the Server header
	ok (defined($headers->header('Server')), 'Server header');
	
	### Check the USN header
	is ($headers->header('USN'), 'uuid:Perl-UPnP-Test-Device1', 'USN header');
	testControl();
	$searchTestDone = 1;
    }
}

sub testControl {
    my $base = 'http://' . UPnP::Common::getLocalIP() . ':' . DEVICE_PORT;

    # Section 2.9 of the UPnP Architecture document
    # 'Description: Retrieving a description'
    diag("Testing Section 2.9");

    my $ua = LWP::UserAgent->new;
    my $resp = $ua->get($base . '/description.xml');
    
    ### Successful retrieval
    ok( $resp->is_success, 'Description retrieval' );

    ### Check content-length header
    ok( defined($resp->header('Content-length')), 
	'Content-length header' );

    ### Check content-type header
    is( $resp->header('Content-type'), 'text/xml', 'Content-type header' );

    # Section 3.2.2 of the UPnP Architecture document
    # 'Control: Action: Response'
    diag("Testing Section 3.2.2");

    my $lite = SOAP::Lite->uri(
			   'urn:schemas-upnp-org:service:RenderingControl:1');
    my $envelope = $lite->serializer->envelope(method => 'ListPresets',
			      SOAP::Data->name('InstanceID')->type(int => 5));
    my $req = HTTP::Request->new("POST",
			     $base . '/MediaRenderer/RendererControl/Control',
			     HTTP::Headers->new,
			     $envelope);
    $req->header('Content-type', 'text/xml');
    $req->header('Host', $base);
    $req->header('Content-length', length $envelope);
    $req->header('SOAPAction', '"urn:schemas-upnp-org:service:RenderingControl:1#ListPresets"');

    $resp = $ua->request($req);

    ### Successful call 
    ok( $resp->is_success, 'SOAP invocation successful' );

    my $som = $lite->deserializer->deserialize($resp->content);
    ### SOAP envelope in response
    isa_ok( $som, 'SOAP::SOM' );

    ### Check content-length header
    ok( defined($resp->header('Content-length')), 
	'Content-length header' );
    
    ### Check content-type header
    cmp_ok( $resp->header('Content-type'), '=~',
	    'text/xml', 'Content-type header' );

    ### Check the EXT header
    ok( defined($resp->header('EXT')), 'EXT header' );

    ### Check the Server header
    ok ( defined($resp->header('Server')), 'Server header' );

    $som->match('/Envelope/Body/[1]');
    
    ### Check the methodname
    is ( $som->dataof->name, 'ListPresetsResponse', 'Response method name' );

    ### Check the argument name
    is ( $som->dataof('[1]')->name, 'CurrentPresetNameList', 
	 'Response argument name' );

    ### Check the result
    is ( $som->result, 'foo', 'Result of action' );

    # Section 3.3.2 of the UPnP Architecture document
    # 'Control: Query: Response'
    diag("Testing Section 3.3.2");

    $envelope = $lite->serializer->envelope(method =>
			      SOAP::Data->name('ListPresets')
				     ->uri('urn:schemas-upnp-org:control-1-0'),
			      SOAP::Data->name('varName')
					       ->value('LastChange'));
    $req = HTTP::Request->new("POST",
			     $base . '/MediaRenderer/RendererControl/Control',
			     HTTP::Headers->new,
			     $envelope);
    $req->header('Content-type', 'text/xml');
    $req->header('Host', $base);
    $req->header('Content-length', length $envelope);
    $req->header('SOAPAction', 
		 '"urn:schemas-upnp-org:control-1-0#QueryStateVariable"');

    $resp = $ua->request($req);

    ### Successful call 
    ok( $resp->is_success, 'query successful' );
   
    $som = $lite->deserializer->deserialize($resp->content);
    ### SOAP envelope in response
    isa_ok( $som, 'SOAP::SOM' );

    ### Check content-length header
    ok( defined($resp->header('Content-length')), 
	'Content-length header' );
    
    ### Check content-type header
    cmp_ok( $resp->header('Content-type'), '=~',
	    'text/xml', 'Content-type header' );

    ### Check the EXT header
    ok( defined($resp->header('EXT')), 'EXT header' );

    ### Check the Server header
    ok ( defined($resp->header('Server')), 'Server header' );

    $som->match('/Envelope/Body/[1]');
    
    ### Check the methodname
    is ( $som->dataof->name, 'QueryStateVariableResponse', 
	 'Response method name' );

    ### Check the method node namespace
    is ( $som->dataof->uri, 'urn:schemas-upnp-org:control-1-0', 
	 'Response method node namespace' );

    ### Check the argument name
    is ( $som->dataof('[1]')->name, 'return', 
	 'Response argument name' );

    ### Check the result
    is ( $som->result, 'yesterday', 'Result of query' );

    # Section 4.1.1 of the UPnP Architecture document
    # 'Eventing: Subscribing: SUBSCRIBE with NT and CALLBACK'
    diag('Testing Section 4.1.1');
    
    $req = HTTP::Request->new("SUBSCRIBE",
			     $base . '/MediaRenderer/RendererControl/Event',
			     HTTP::Headers->new);
    $req->header('Host', UPnP::Common::getLocalIP() . ':' . DEVICE_PORT);
    $req->header('Callback', '<http://' . UPnP::Common::getLocalIP() . ':' 
		 . SUBSCRIPTION_PORT . '>');
    $req->header('NT', 'upnp:event');
    $req->header('Timeout', 'Second-1800');
    
    $resp = $ua->request($req);

    ### Successful subscription 
    ok( $resp->is_success, 'subscription successful' );
    
    ### Check the Server header
    ok ( defined($resp->header('Server')), 'Server header' );

    ### Check the SID header
    $sid = $resp->header('SID');
    cmp_ok ( $sid, '=~', 'uuid:', 'SID header' );
    
    ### Check the SID header
    cmp_ok ( $resp->header('Timeout'), '=~', 
	     'Second-', 'Timeout header' );
}

sub testNotification {
    my $sock = shift;
    my $c = $sock->accept;
    my $req = $c->get_request;

    my $response = HTTP::Response->new(HTTP::Status::RC_OK);
    $response->protocol('HTTP/1.1');
    if ($firstNotification) {
	# Section 4.2.1 of the UPnP Architecture document
	# 'Eventing: Event messages: NOTIFY'
	diag('Testing Section 4.2.1');
	
	### notification HTTP method
	is( $req->method, 'NOTIFY', 'HTTP method' );
	
	### Check the HOST header
	is ($req->header('HOST'), UPnP::Common::getLocalIP() . ':' . SUBSCRIPTION_PORT, 
	    'HOST header');
	
	### Check content-length header
	ok( defined($req->header('Content-length')), 
	    'Content-length header' );
	
	### Check content-type header
	is( $req->header('Content-type'), 'text/xml', 'Content-type header' );
	
	### Check the NT header
	is( $req->header('NT'), 'upnp:event', 'NT header');
	
	### Check the NTS header
	is( $req->header('NTS'), 'upnp:propchange', 'NTS header');
	
	### Check the SID header
	is( $req->header('SID'), $sid, 'SID header');
	
	### Check the SEQ header
	is( $req->header('SEQ'), 0, 'SEQ header');
	
	$firstNotification = 0;

	# Trigger a device state variable change
	$child->print("\n");

	$c->send_response($response);
	$c->close;
    }
    else {
	### Check the SEQ header
	is( $req->header('SEQ'), 1, 'second SEQ header');

	$c->send_response($response);
	$c->close;

	testUnsubscribe();

	# We're done
	$spin = 0;
    }

}

sub testUnsubscribe {

    # Section 4.1.3 of the UPnP Architecture document
    # 'Eventing: Canceling a subscription: UNSUBSCRIBE'
    diag("Testing Section 4.1.3");

    my $ua = LWP::UserAgent->new;
    my $base = 'http://' . UPnP::Common::getLocalIP() . ':' . DEVICE_PORT;

    $req = HTTP::Request->new("UNSUBSCRIBE",
			     $base . '/MediaRenderer/RendererControl/Event',
			     HTTP::Headers->new);
    $req->header('Host', UPnP::Common::getLocalIP() . ':' . DEVICE_PORT);
    $req->header('SID', $sid);

    $resp = $ua->request($req);

    ### Successful unsubscription 
    ok( $resp->is_success, 'unsubscription successful' );
}


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
