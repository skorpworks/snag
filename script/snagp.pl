#!/usr/bin/env perl

use strict;

BEGIN { $ENV{POE_EVENT_LOOP} = "POE::XS::Loop::Poll"; };
use FindBin;
use lib "$FindBin::Bin/../lib/perl5";
use local::lib "$FindBin::Bin/../";

use POE;

use SNAG;
use SNAG::Server;
use SNAG::Client;

use Getopt::Long;
use Data::Dumper;

foreach my $arg (@ARGV)
{
  $arg =~ s/^\-{1,2}//;
  $SNAG::flags{$arg} = 1;
}

### Get rid of this once all sources are converted to dispatching
my %options;
GetOptions(\%options, 'debug', 'verbose');

my $debug = $SNAG::flags{debug};

my $scriptname = SCRIPT_NAME;
exit if already_running();

die "Invalid usage of snagp.pl!" unless (split /_snagp/, $scriptname) == 2;
my ($type) = (split /_snagp/, $scriptname)[0];

my ($login,$pass,$uid,$gid) = getpwnam('snag');
if ( defined $uid )
{
  $) = $gid;
  $> = $uid;
}


logger();
daemonize() unless $SNAG::flags{debug};

my $confin = CONF;

my $poller = $confin->{poller}->{$type} or die "Poller type $type does not exist in snag.conf!";

my $mod_file = $poller->{module};
$mod_file =~ s/::/\//g;
$mod_file .= ".pm";
require $mod_file;

my $mod_file = $poller->{module};
$mod_file =~ s/::/\//g;
$mod_file .= ".pm";
require $mod_file;
$poller->{module}->new
(
  Alias   => $type,
  Source  => $poller->{ds},
);

SNAG::Client->new( $confin->{client} );

$SIG{INT} = $SIG{TERM} = sub
{
  $poe_kernel->call('logger' => 'log' => "Killed");
  exit;
};

$poe_kernel->run;
