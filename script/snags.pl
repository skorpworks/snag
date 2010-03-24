#!/usr/bin/env perl

use strict;

BEGIN { $ENV{POE_EVENT_LOOP} = "POE::XS::Loop::Poll"; };
use POE;

use SNAG;
use SNAG::Server;
use SNAG::Client;

use Getopt::Long;
use XML::Simple;
use Data::Dumper;

foreach my $arg (@ARGV)
{
  $arg =~ s/^\-{1,2}//;
  $SNAG::flags{$arg} = 1;
}

### Get rid of this once all sources are converted to dispatching
my %options;
GetOptions(\%options, 'debug', 'verbose');

my $scriptname = SCRIPT_NAME;
exit if already_running();

die "Invalid usage of snags.pl!" unless (split /_/, $scriptname) == 2;
my ($type) = (split /_/, $scriptname)[0];

my ($login,$pass,$uid,$gid) = getpwnam('snag');
if ( defined $uid )
{
  $) = $gid;
  $> = $uid;
}

umask(0022);

logger();
daemonize() unless $SNAG::flags{debug};

#my $confin = XMLin(BASE_DIR . '/SNAG.xml', KeyAttr => [qw/name/], ForceArray => qr/^(server|client)$/ ) or die "Could not open configuration file SNAG.xml!";
my $confin = XMLin(BASE_DIR . '/SNAG.xml', KeyAttr => {server => 'name'}, ForceArray => qr/^(server|client)$/ ) or die "Could not open configuration file SNAG.xml!";

my $server = $confin->{server}->{$type} or die "Server type $type does not exist in SNAG.xml!";

my $mod_file = $server->{module};
$mod_file =~ s/::/\//g;
$mod_file .= ".pm";
require $mod_file;

$server->{module}->new
(
  Alias		=> $type,
  Port		=> $server->{port},
  Key		=> $server->{key},
  Args		=> $server->{args},
  Options 	=> \%options,
);

SNAG::Client->new( $confin->{client} );

$SIG{INT} = $SIG{TERM} = sub
{
  $poe_kernel->call('logger' => 'log' => "Killed");
  exit;
};

$poe_kernel->run;
