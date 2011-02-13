use 5.006;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME              => 'UPnP',
    VERSION_FROM      => 'lib/UPnP/Common.pm', # finds $VERSION
    PREREQ_PM         => {SOAP::Lite => 0.55,
                          LWP::UserAgent => 2.0,
                          HTTP::Daemon => 1.0,}, # e.g., Module::Name => 1.1
);
