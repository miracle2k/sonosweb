# This file checks that the HTTP, UDP, GENA and SOAP messages sent
# by the UPnP::ControlPoint module match the UPnP specification.
# It creates a ControlPoint instance in a child thread and simulates
# a Device in the main thread, checking the messages sent across
# for validity.

use Test::More;

# Prepend all tests with triple hash marks to dynamically
# calculate the number of tests.
open(ME,$0) or die $!;
my $TestCount = grep(/\#\#\#/,<ME>);
close(ME);

use UPnP::ControlPoint;
use UPnP::Common;
use Socket;
use IO::Select;
use IO::Handle;
use HTTP::Daemon;
use SOAP::Lite;

use constant SEARCH_PORT => 8997;
use constant SUBSCRIPTION_PORT => 8998;
use constant DEVICE_PORT => 8999;
 
my $spin = 1;
my $firstSubscription = 1;
my $ssdpTestDone = 0;

$SIG{INT} = $SIG{KILL} = sub { $spin = 0 };

# Create a socket pair for IPC between the parent and child
# processes created below.
my ($child, $parent) = 
    IO::Socket->socketpair( AF_UNIX, SOCK_STREAM, PF_UNSPEC ) 
    or die "Cannot create socketpair: $!";
$child->autoflush(1);
$parent->autoflush(1);


# We need to fork to test. Don't worry, we'll join before
# quitting. Also, we'll make sure that we only output from the parent
# process.
my $pid = fork();
die "fork() failed: $!" unless defined $pid;
if ($pid) {
    # Parent process is the protocol tester.
    close $parent;

    plan tests => $TestCount;

    # Create a socket on which we can hear the ControlPoint's SSDP
    # events
    my $ssdpSocket = IO::Socket::INET->new(Proto => 'udp',
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

    my $daemon = HTTP::Daemon->new(LocalPort => DEVICE_PORT);
    my $select = IO::Select->new($ssdpSocket, $daemon);

    $child->print("\n");

    eval {
	while ($spin) {
	    my @rsocks = $select->can_read(1);
	    for my $sock (@rsocks) {
		if ($sock == $ssdpSocket) {
		    testSSDPEvent($sock);
		}
		elsif ($sock == $daemon) {
		    my $c = $sock->accept;
		    handleRequest($c);
		}
	    }
	}
    };

    $child->print("q\n");

    close $child;
    wait;
}
else {
    # Child process will create a ControlPoint.
    close $child;

    $cp = UPnP::ControlPoint->new(SearchPort => SEARCH_PORT,
				  SubscriptionPort => SUBSCRIPTION_PORT);
    my $select = IO::Select->new($parent, $cp->sockets);
    my $state = 0;
    my $device;
    
    while ($spin) {
	my @rsocks = $select->can_read(1);
	for my $sock (@rsocks) {
	    if ($sock == $parent) {
		my $line = $sock->getline;
		if ($line && $line eq "q\n") {
		    $spin = 0;
		}
		elsif (++$state == 1) {
		    my $search = $cp->searchByType(
				   "urn:schemas-upnp-org:device:TestDevice:1",
				   \&searchCallback);
		}
	    }
	    else {
		$cp->handleOnce($sock);
	    }
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
    if (!$ssdpTestDone && $port == SEARCH_PORT && 
	inet_ntoa($iaddr) eq UPnP::Common::getLocalIP()) {

	# Section 1.22 of the UPnP Architecture document
	# 'Discovery: Search: Request with M-SEARCH'
	diag("Testing Section 1.22");

	### Confirm that we got a full HTTP header
	ok( $buf =~ /\015?\012\015?\012/, 'Checking for full HTTP header' ) || 
	    return;

	$buf =~ s/^(?:\015?\012)+//;  # ignore leading blank lines
	### Confirm that we got a good first line
	ok( $buf =~ 
	    s/^(\S+)[ \t]+(\S+)(?:[ \t]+(HTTP\/\d+\.\d+))?[^\012]*\012//,
	    'Checking first line of header' ) || return;

	### Confirm that we got a M-SEARCH
	is ($1, 'M-SEARCH', 'HTTP method');

	### Confirm that the resource is *
	is ($2, '*', 'HTTP resource');

	my $headers = UPnP::Common::parseHTTPHeaders($buf);
	
	### Check the HOST header
	is ($headers->header('HOST'), '239.255.255.250:1900', 'HOST header');

	### Check the MAN header
	is ($headers->header('Man'), '"ssdp:discover"', 'Man header');

	### Check the MX header
	is ($headers->header('MX'), '3', 'MX header');

	### Check the ST header
	is ($headers->header('ST'), 'urn:schemas-upnp-org:device:TestDevice:1',
	    'ST header');

	my $r = HTTP::Response->new(HTTP::Status::RC_OK);
	$r->protocol('HTTP/1.1');
	$r->header('Location', 'http://' . UPnP::Common::getLocalIP() . ':' . DEVICE_PORT . '/description.xml');
	$r->header('Server', "TestServer");
	$r->header('USN', 'uuid:Perl-UPnP-Test-Device1::urn:schemas-upnp-org:device:TestDevice:1');
	$r->header('Cache-control', 'max-age=1800');
	$r->header('ST', $headers->header('ST'));

	my $notificationSock = IO::Socket::INET->new(Proto => 'udp');
	send($notificationSock, $r->as_string, 0, $peer);

	$ssdpTestDone = 1;
    }
}

sub loadFile {
    my $file = shift;
    my $str = '';
    
    open FH, "< $file";
    while (<FH>) {
	$str .= $_;
    }
    
    return $str;
}

sub handleRequest {
    my $c = shift;
    my $r = $c->get_request;
    my $uri = $r->uri;

    my $response = HTTP::Response->new;
    $response->protocol('HTTP/1.1');
    if ($uri eq '/description.xml') {
	# Section 2.9 of the UPnP Architecture document
	# 'Description: Retrieving a description'
	diag('Testing Section 2.9');

	### HTTP Method
	is( $r->method, 'GET', 'HTTP Method' );

	my $base = 'http://' . UPnP::Common::getLocalIP() . ':' . DEVICE_PORT;

	### Required HOST header
	ok( defined($r->header('Host')), 'Host header' );

	$response->code(HTTP::Status::RC_OK);
	my $description = loadFile('./t/description1.xml');

	$description =~ s/<\/root>/<URLBase>$base<\/URLBase><\/root>/;

	$response->content($description);
    }
    elsif ($uri eq '/RendererControl.xml') {
	$response->code(HTTP::Status::RC_OK);
	my $file = loadFile('./t/RendererControl.xml');
	$response->content($file);	
    }
    elsif ($uri eq '/MediaRenderer/RendererControl/Control') {
	my $soapaction = $r->header('SOAPAction');
	for ($soapaction) { s/(.*)#//; s/"$//; }
	if ($soapaction eq 'QueryStateVariable') {
	    # Section 3.3.1 of the UPnP Architecture document
	    # 'Control:Query:Invoke'
	    diag('Testing Section 3.3.1');
	
	    ### HTTP Method
	    is( $r->method, 'POST', 'HTTP Method' );

	    ### Required HOST header
	    ok( defined($r->header('Host')), 'Host header' );
	    
	    ### Required Content-length
	    ok( defined($r->header('Content-length')), 
		'Content-length header' );

	    ### Required Content-type
	    cmp_ok( $r->header('Content-type'), '=~', 'text/xml', 
		    'Content-type header' );
	    
	    ### Required SOAPAction
	    is( $r->header('SOAPAction'), 
		'"urn:schemas-upnp-org:control-1-0#QueryStateVariable"', 
		'SOAPAction header' );

	    my $deserializer = SOAP::Deserializer->new;
	    my $som = eval { $deserializer->deserialize($r->content); };
	    ### Content is XML
	    ok( defined($som), 'Content is XML' );

	    $som->match('/Envelope/Body/[1]');
	    ### namespaceURI of method is control namespace
	    is( $som->namespaceuriof, 
		'urn:schemas-upnp-org:control-1-0',
		'namespaceURI of method element' );

	    ### method name is as expected
	    is( $som->dataof->name, 'QueryStateVariable',
		'Method name' );

	    ### namespaceURI of varName is control namespace
	    is( $som->namespaceuriof, 
		'urn:schemas-upnp-org:control-1-0',
		'namespaceURI of varName element' );

	    $som->match('/Envelope/Body/[1]/[1]');
	    ### varName is as expected
	    is( $som->dataof->name, 'varName',
		'varName name' );
	}
	elsif ($soapaction eq 'ListPresets') {
	    # Section 3.1 of the UPnP Architecture document
	    # 'Control:Action:Invoke'
	    diag('Testing Section 3.1');
	
	    ### HTTP Method
	    is( $r->method, 'POST', 'HTTP Method' );

	    ### Required HOST header
	    ok( defined($r->header('Host')), 'Host header' );
	    
	    ### Required Content-length
	    ok( defined($r->header('Content-length')), 
		'Content-length header' );

	    ### Required Content-type
	    cmp_ok( $r->header('Content-type'), '=~', 'text/xml', 
		    'Content-type header' );
	    
	    ### Required SOAPAction
	    is( $r->header('SOAPAction'), 
		'"urn:schemas-upnp-org:service:RenderingControl:1#ListPresets"', 
		'SOAPAction header' );

	    my $deserializer = SOAP::Deserializer->new;
	    my $som = eval { $deserializer->deserialize($r->content); };
	    ### Content is XML
	    ok( defined($som), 'Content is XML' );

	    $som->match('/Envelope/Body/[1]');
	    ### namespaceURI of method is service type
	    is( $som->namespaceuriof, 
		'urn:schemas-upnp-org:service:RenderingControl:1',
		'namespaceURI of method element' );

	    ### method name is as expected
	    is( $som->dataof->name, 'ListPresets',
		'Method name' );
	}

	$response->code(HTTP::Status::RC_NOT_FOUND);
    }
    elsif ($uri eq '/MediaRenderer/RendererControl/Event') {

	if ($firstSubscription) {
	    # Section 4.1.1 of the UPnP Architecture document
	    # 'Eventing: Subscribing: SUBSCRIBE with NT and CALLBACK'
	    diag('Testing Section 4.1.1');
	    
	    ### HTTP Method
	    is( $r->method, 'SUBSCRIBE', 'HTTP Method' );
	    
	    ### Required HOST header
	    ok( defined($r->header('Host')), 'Host header' );
	    
	    ### Callback header is reasonable
	    cmp_ok( $r->header('Callback'), '=~',
		    '(<(.*?)>)+', 'Callback header' );
	    
	    ### NT header
	    is( $r->header('NT'), 'upnp:event', 'NT header' );
	    
	    ### SID header shouldn't be there for initial subscription
	    ok( !defined($r->header), 'SID header' );

	    $response->code(HTTP::Status::RC_OK);
	    $response->header('SID', 'uuid:01');
	    $response->header('Timeout', 'Second-1800');

	    $firstSubscription = 0;
	}
	elsif ($r->method eq 'SUBSCRIBE') {
	    # Section 4.1.2 of the UPnP Architecture document
	    # 'Eventing: Renewing a subscription: SUBSCRIBE with SID'
	    diag('Testing Section 4.1.2');

	    ### Required HOST header
	    ok( defined($r->header('Host')), 'Host header' );
	    
	    ### No Callback header
	    ok( !defined($r->header('Callback')), 'Callback header' );
	    
	    ### No NT header
	    ok( !defined($r->header('NT')), 'NT header' );

	    ### SID header
	    is( $r->header('SID'), 'uuid:01', 'SID header' );
	    
	    $response->code(HTTP::Status::RC_OK);
	    $response->header('SID', 'uuid:01');
	    $response->header('Timeout', 'Second-1800');
	}
	else {
	    # Section 4.1.3 of the UPnP Architecture document
	    # 'Eventing: Canceling a subscription: UNSUBSCRIBE'
	    diag('Testing Section 4.1.3');
    
	    ### HTTP Method
	    is( $r->method, 'UNSUBSCRIBE', 'HTTP Method' );

	    ### Required HOST header
	    ok( defined($r->header('Host')), 'Host header' );
	    
	    ### No Callback header
	    ok( !defined($r->header('Callback')), 'Callback header' );
	    
	    ### No NT header
	    ok( !defined($r->header('NT')), 'NT header' );

	    ### SID header
	    is( $r->header('SID'), 'uuid:01', 'SID header' );

	    $response->code(HTTP::Status::RC_OK);

	    # Trigger the child process to stop
	    $child->print("\n");
	    $spin = 0;
	}
    }

    $c->send_response($response);
    $c->close;
}

sub searchCallback {
    my ($search, $device, $action) = @_;

    if ($action eq 'deviceAdded') {
	my @services = $device->services;
	my $service = $services[0];
	my $proxy = $service->controlProxy;
	eval { $proxy->ListPresets(5); };
	eval { $service->queryStateVariable('LastChange'); };
	my $sub = $service->subscribe(sub { });
	$sub->renew;
	$sub->unsubscribe;
    }
}


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
