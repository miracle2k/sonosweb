# This file does some basic testing of the UPnP::DeviceManager
# module. It creates a couple of devices in one process and a
# ControlPoint instance in other and confirms that interaction between
# them is as expected.

use Test::More;

use constant SEARCH_PORT => 8993;
use constant SUBSCRIPTION_PORT => 8994;
use constant DEVICE_PORT1 => 8995;
use constant DEVICE_PORT2 => 8996;

# Prepend all tests with triple hash marks to dynamically
# calculate the number of tests.
open(ME,$0) or die $!;
my $TestCount = grep(/\#\#\#/,<ME>);
close(ME);

BEGIN { use_ok('UPnP::DeviceManager') };
use UPnP::ControlPoint;
use UPnP::Common;
use Socket;
use IO::Select;

my $spin = 1;

$SIG{INT} = $SIG{KILL} = sub { $spin = 0 };

# Create a socket pair for IPC between the parent and child
# processes created below.
my ($child, $parent) = 
    IO::Socket->socketpair( AF_UNIX, SOCK_STREAM, PF_UNSPEC ) 
    or die "Cannot create socketpair: $!";
$child->autoflush(1);
$parent->autoflush(1);

my ($device1, $device2, $service1, $service2);
my $numCallbacks = 0;
my $firstQuery = 1;
my $dm;

# We need to fork to create a ControlPoint. Don't worry, we'll join
# before quitting. Also, we'll make sure that we only output from the
# parent process.
my $pid = fork();
die "fork() failed: $!" unless defined $pid;
if ($pid) {
    # Parent process is the DeviceManager.
    close $parent;

    plan tests => $TestCount;

    diag("Testing Device creation");

    ### Creating a ControlPoint
    $dm = UPnP::DeviceManager->new;
    isa_ok( $dm, 'UPnP::DeviceManager' );
    
    ### Register a device
    $device1 = $dm->registerDevice(DevicePort => DEVICE_PORT1,
				   DescriptionFile => './t/description1.xml',
				   ResourceDirectory => './t');
    isa_ok( $device1, 'UPnP::DeviceManager::Device' );

    ### Find a service
    $service1 = $device1->getService(
				   'urn:upnp-org:serviceId:RenderingControl');
    isa_ok( $service1, 'UPnP::DeviceManager::Service' );

    $service1->onAction(\&onAction);
    $service1->onQuery(\&onQuery);

    ### Register a second device
    $device2 = $dm->registerDevice(DevicePort => DEVICE_PORT2,
				   DescriptionFile => './t/description2.xml',
				   ResourceDirectory => './t');
    isa_ok( $device2, 'UPnP::DeviceManager::Device' );

    ### Find the corresponding service
    $service2 = $device2->getService(
				   'urn:upnp-org:serviceId:RenderingControl');
    isa_ok( $service2, 'UPnP::DeviceManager::Service' );
    
    $service2->dispatchTo('MyTest');
    $service2->setValue('LastChange', 'yesterday');

    ### Confirm number of devices
    is( scalar($dm->devices), 2, 'UPnP::DeviceManager::devices' );

    $child->print("\n");

    $device1->start;
    $device2->start;

    my $select = IO::Select->new($dm->sockets);

    eval {
	my $timeout = $dm->heartbeat;
	while ($spin) {
	    my @rsocks = $select->can_read($timeout < 1 ? $timeout : 1);
	    for my $sock (@rsocks) {
		$dm->handleOnce($sock);
	    }
	    $timeout = $dm->heartbeat;
	}
    };

    $device1->stop;
    $device2->stop;

    $child->print("q\n");

    close $child;
    wait;
}
else {
    # Child process will be the ControlPoint.
    close $child;

    my $cp = UPnP::ControlPoint->new(SearchPort => SEARCH_PORT,
				     SubscriptionPort => SUBSCRIPTION_PORT);
    my $select = IO::Select->new($parent, $cp->sockets);
    my $state = 0;
    my ($device1, $device2);

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

sub callbackInvoked {
    if (++$numCallbacks == 4) {
	$spin = 0;
    }
}

sub onAction {
    my $service = shift;
    my $action = shift;

    diag("Testing onAction callback");

    ### Called with the correct service instance
    is( $service, $service1, 'onAction callback service parameter' );

    ### Called with the correct action name
    is( $action, 'ListPresets', 'onAction callback action parameter' );

    ### Called with the correct parameter
    is ( $_[0], 5, 'control parameters' );

    callbackInvoked();

    return 'foo';
}

sub onQuery {
    my ($service, $name, $val) = @_;
    
    if ($firstQuery) {
	diag("Testing onQuery callback");

	### Called with the correct service instance
	is( $service, $service1, 'onQuery callback service parameter' );
	
	### Called with the correct variable name
	is( $name, 'LastChange', 'onQuery callback name parameter' );

	### First time val is undefined
	ok( !defined($val), 'onQuery val parameter' );

	$firstQuery = 0;
    }
    else {
	### Second time val is what we set it to last
	is( $val, 'yesterday', 'onQuery val parameter' );
    }

    callbackInvoked();

    return 'yesterday';
}

sub searchCallback {
    my ($search, $device, $action) = @_;

    if ($action eq 'deviceAdded') {
	my @services = $device->services;
	my $service = $services[0];
	my $proxy = $service->controlProxy;
	eval { $proxy->ListPresets(5); };
	if ($device->UDN eq 'uuid:Perl-UPnP-Test-Device1') {
	    eval { $service->queryStateVariable('LastChange'); };
	    eval { $service->queryStateVariable('LastChange'); };
	}
    }
}

sub packageCalled {
    my $class = shift;

    diag("Testing action dispatching");
    
    ### Called with the correct class
    is( $class, 'MyTest', 'action class parameter' );

    ### Called with the correct parameter
    is ( $_[0], 5, 'control parameters' );
    
    callbackInvoked();

    return 'foo';
}

package MyTest;

sub ListPresets {
    return main::packageCalled(@_);
}

1;


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
