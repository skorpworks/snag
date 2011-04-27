#!/usr/bin/env perl

use strict;
use warnings;

BEGIN { $ENV{POE_EVENT_LOOP} = "POE::XS::Loop::EPoll"; };

use POE;
use SNAG;
use SNAG::Server;
use SNAG::Client;
use Getopt::Long;
use Data::Dumper::Concise;

foreach my $arg (@ARGV)
{
  $arg =~ s/^\-{1,2}//;
  $SNAG::flags{$arg} = 1;
}

### Get rid of this once all sources are converted to dispatching
my %options;
GetOptions(\%options, 'debug', 'verbose', 'compile');

if($SNAG::flags{compile})
{
  unless($ENV{PAR_SPAWNED})
  {
    print "Compiling $0 to snagp ... ";
    my $includes;
    for my $include_file qw(includes/pp_includes includes/snagp_includes) {
        open (my $fh, '<', $include_file) || die "Could not open $include_file - $!\n";
        while (<$fh>) {
            chomp;
            next unless (/\w+/);
            $includes .= " -M $_";
        }
        close($fh);
    }
    my $cmd = "pp $0 --compile --execute --bundle" . $includes . " -a /opt/snag/snag.conf -o snagp";

    print "with cmd $cmd\n";
    my $out = '';
    open LOG, "$cmd |" || die "DIED: $!\n";
    while (<LOG>)
    {
      print $_;
      $out .= $_;
    }

    print "Done!\n";

    if($out =~ /\w/)
    {
      print "=================== DEBUG ==================\n";
      print $out;
    }
  }
  else
  {
    print "This is already a compile binary!\n";
  }

  exit;
}

my $debug = $SNAG::flags{debug};

my $scriptname = SCRIPT_NAME;
exit if already_running();

die "Invalid usage of snagp.pl\n" unless ($scriptname =~ /(.+?)_snagp/);
my $type = $1;

my ($login,$pass,$uid,$gid) = getpwnam('snag');
if ( defined $uid )
{
  $) = $gid;
  $> = $uid;
}


logger();
daemonize() unless $SNAG::flags{debug};

my $confin = CONF;

print Dumper $confin;

my $poller = $confin->{poller}->{$type} or die "Poller type $type does not exist in snag.conf!";

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
