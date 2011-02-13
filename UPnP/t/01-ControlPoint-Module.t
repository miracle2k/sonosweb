# This file does some basic testing of the UPnP::ControlPoint
# module. It creates a ControlPoint instance in one process and a
# DeviceManager instance in other and confirms that interaction
# between them is as expected.

use Test::More;

# Prepend all tests with triple hash marks to dynamically
# calculate the number of tests.
open(ME,$0) or die $!;
my $TestCount = grep(/\#\#\#/,<ME>);
close(ME);

BEGIN { use_ok('UPnP::ControlPoint') };
use UPnP::DeviceManager;
use UPnP::Common;
use Socket;
use IO::Select;
use IO::Handle;

my $spin = 1;
my $firstEvent = 1;

$SIG{INT} = $SIG{KILL} = sub { $spin = 0 };

# Create a socket pair for IPC between the parent and child
# processes created below.
my ($child, $parent) = 
    IO::Socket->socketpair( AF_UNIX, SOCK_STREAM, PF_UNSPEC ) 
    or die "Cannot create socketpair: $!";
$child->autoflush(1);
$parent->autoflush(1);
my $cp;

# We need to fork to create test devices. Don't worry, we'll join
# before quitting. Also, we'll make sure that we only output from the
# parent process.
my $pid = fork();
die "fork() failed: $!" unless defined $pid;
if ($pid) {
    # Parent process is the ControlPoint.
    close $parent;

    plan tests => $TestCount;

    diag("Testing ControlPoint creation");

    ### Creating a ControlPoint
    $cp = UPnP::ControlPoint->new;
    isa_ok( $cp, 'UPnP::ControlPoint' );

    # Start a search by device type *before* any matching devices 
    # exist on the network.
    my $search = $cp->searchByType("urn:schemas-upnp-org:device:TestDevice:1",
				    \&searchCallback1);
    ### Confirm that the search object was created
    ok( defined $search, 'Search by device type' );

    # Tell the child to start advertising
    $child->print("\n");

    eval {
	$cp->handle;
    };

    $child->print("q\n");

    close $child;
    wait;
}
else {
    # Child process will create devices.
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
		    $dm = UPnP::DeviceManager->new;
		    $device = $dm->registerDevice(
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
		elsif ($state == 3) {
		    $device->stop;
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

sub searchCallback1 {
    my ($search, $device, $action) = @_;

    if ($action eq 'deviceAdded') {

	### Device search succeeded
	pass( 'Device search succeeded before initial device advertisement' );

	diag("Testing device object model");

	### Device is of right type
	isa_ok( $device, 'UPnP::ControlPoint::Device' );

	### deviceType
	is( $device->deviceType, 
	    'urn:schemas-upnp-org:device:TestDevice:1', 
	    'UPnP::ControlPoint::Device::deviceType' );
	### friendlyName
	is( $device->friendlyName, 
	    'Perl UPnP Test Device', 
	    'UPnP::ControlPoint::Device::friendlyName' );
	### manufacturer
	is( $device->manufacturer, 
	    'Your friendly neighborhood Perl developer', 
	    'UPnP::ControlPoint::Device::manufacturer' );
	### manufacturerURL
	is( $device->manufacturerURL, 
	    'www.cpan.org', 
	    'UPnP::ControlPoint::Device::manufacturerURL' );
	### modelName
	is( $device->modelName, 
	    'PerlUPnP1', 
	    'UPnP::ControlPoint::Device::modelName' );
	### modelNumber
	is( $device->modelNumber, 
	    0.01, 
	    'UPnP::ControlPoint::Device::modelNumber' );
	### modelURL
	is( $device->modelURL, 
	    'www.cpan.org', 
	    'UPnP::ControlPoint::Device::modelURL' );
	### modelDescription
	is( $device->modelDescription, 
	    'A device used to test the Perl UPnP implementation.', 
	    'UPnP::ControlPoint::Device::modelDescription' );
	### serialNumber
	is( $device->serialNumber, 
	    '0100108640-92', 
	    'UPnP::ControlPoint::Device::serialNumber' );
	### UPC
	is( $device->UPC, 
	    '876078133106', 
	    'UPnP::ControlPoint::Device::UPC' );
	### presentationURL
	is( $device->presentationURL, 
	    'www.cpan.org', 
	    'UPnP::ControlPoint::Device::presentationURL' );

	my @services = $device->services;
	### There should be one service
	is( scalar(@services), 1, "Checking number of services" );
	
	my $service = $services[0];
	### Service is of right type
	isa_ok( $service, 'UPnP::ControlPoint::Service' );
	
	### serviceType
	is( $service->serviceType, 
	    'urn:schemas-upnp-org:service:RenderingControl:1',
	    'UPnP::ControlPoint::Service::serviceType' );
	### serviceId
	is( $service->serviceId, 
	    'urn:upnp-org:serviceId:RenderingControl',
	    'UPnP::ControlPoint::Service::serviceId' );
	### SCPDURL
	my $scpdurl = $service->SCPDURL;
	cmp_ok( "$scpdurl", '=~', '/RendererControl.xml',
		'UPnP::ControlPoint::Service::SCPDURL');
	### eventSubURL
	my $eventsuburl = $service->eventSubURL;
	cmp_ok( "$eventsuburl", '=~', '/MediaRenderer/RendererControl/Event',
		'UPnP::ControlPoint::Service::eventSubURL');
	### controlURL
	my $controlurl = $service->controlURL;
	cmp_ok( "$controlurl", '=~', '/MediaRenderer/RendererControl/Control',
		'UPnP::ControlPoint::Service::controlURL');

	diag("Testing service object model");

	my @actions = $service->actions;
	### Number of actions
	is( scalar(@actions), 2, "UPnP::ControlPoint::Service::actions" );
	
	### Retrieve action by name
	my $action = $service->getAction('ListPresets');
	isa_ok( $action, 'UPnP::Common::Action' );

	### Action name
	is( $action->name, 'ListPresets', 'UPnP::Common::Action::name' );

	my @arguments = $action->arguments;
	### Number of arguments
	is( scalar(@arguments), 2, 'UPnP::Common::Action::arguments' );

	### Retrieve in argument
	my ($argument) = $action->inArguments;
	isa_ok( $argument, 'UPnP::Common::Argument' );

	### Argument name
	is( $argument->name, 'InstanceID', 'UPnP::Common::Argument::name' );

	### Argument relatedStateVar
	is( $argument->relatedStateVariable, 
	    'A_ARG_TYPE_InstanceID', 
	    'UPnP::Common::Argument::relatedStateVariable' );

	### Argument type
	is( $service->getArgumentType($argument), 
	    'int', 'UPnP::Common::Service::getArgumentType' );

	my @stateVars = $service->stateVariables;
	### Number of state variables
	is( scalar(@stateVars), 5, "UPnP::ControlPoint::Service::stateVariables" );

	### Retrieve state variable by name
	my $stateVar = $service->getStateVariable('LastChange');
	isa_ok( $stateVar, 'UPnP::Common::StateVariable' );

	### StateVariable name
	is( $stateVar->name, 'LastChange', 'UPnP::Common::StateVariable::name' );

	### StateVariable type
	is( $stateVar->type, 'string', 'UPnP::Common::StateVariable::type' );

	### StateVariable evented
	is( $stateVar->evented, 1, 
	    'UPnP::Common::StateVariable::evented' );

	### StateVariable SOAPType
	is( $stateVar->SOAPType, 'string', 
	    'UPnP::Common::StateVariable::SOAPType' );

	diag("Testing action invocation");
	
	### ControlProxy
	my $proxy = $service->controlProxy;
	isa_ok( $proxy, 'UPnP::ControlPoint::ControlProxy' );

	### Call through the proxy
	my $result = $proxy->ListPresets(5);
	isa_ok( $result, 'UPnP::ControlPoint::ActionResult' );

	### Check that the result is successful
	ok( $result->isSuccessful, 'Result successful' );

	### Check that we got the right value back
	is( $result->getValue('CurrentPresetNameList'), 'foo',
	    "Result is correct" );

	diag("Testing querying state");

	### Result of query is correct
	my $val = $service->queryStateVariable('LastChange');
	is( $val, 'yesterday', 
	    'UPnP::ControlPoint::Service::queryStateVariable' );

	diag("Testing subscription");
	
	### Subscription
	my $subscription = $service->subscribe(\&event);
	isa_ok( $subscription, 'UPnP::ControlPoint::Subscription' );
    }
}

sub event {
    my ($service, %properties) = @_;

    if ($firstEvent) {
	### Confirm that the initial event value is correct
	is( $properties{LastChange}, 'yesterday',
	    'Initial event value' );
	$firstEvent = 0;

	# Trigger the child to change the event value
	$child->print("\n");
    }
    else {
	### Confirm that the changed event value is correct
	is( $properties{LastChange}, 'today',
	    'Changed event value' );

	# Start a second search to confirm that we can find a device
	# *after* intial device advertisement.
	my $search = $cp->searchByType(
				  "urn:schemas-upnp-org:device:TestDevice:1",
				  \&searchCallback2);
    }
}	


sub searchCallback2 {
    my ($search, $device, $action) = @_;

    if ($action eq 'deviceAdded') {
	### Device search succeeded
	pass( 'Device search succeeded after initial device advertisement' );

	# Trigger the child to shut down
	$child->print("\n");
    }
    elsif ($action eq 'deviceRemoved') {
	### Device remove correctly reported
	pass( 'Device removal correctly reported' );
	$cp->stopHandling;
    }
}


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:

