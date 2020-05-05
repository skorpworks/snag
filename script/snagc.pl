#!/usr/bin/env perl
### This script is used to gather system statistics and information for use with snagweb and its subapps

use strict; 
use warnings;

use SNAG;
use SNAG::Client;
use SNAG::Dispatch;
use POE;

use Getopt::Long;


if($SNAG::flags{install})
{
  install('install');
}
elsif($SNAG::flags{uninstall} || $SNAG::flags{remove} || $SNAG::flags{'delete'})
{
  install('uninstall');
}
elsif($SNAG::flags{version})
{
  print "Version: " . VERSION . "\n";
  exit;
}
elsif($SNAG::flags{compile})
{
  unless($ENV{PAR_SPAWNED})
  {
    die "PP_INCLUDES environment variable not set.\n" unless $ENV{PP_INCLUDES};
    die "SNAGC_INCLUDES environment variable not set.\n" unless $ENV{SNAGC_INCLUDES};
    print "Compiling $0 to snagc ... ";
    my $includes;
    for my $include_file ($ENV{PP_INCLUDES}, $ENV{SNAGC_INCLUDES}) {
        unless ( -r $include_file ) {
            warn "$include_file does not exist - skipping\n";
            next;   
        }
        open (my $fh, '<', $include_file) || die "Could not open $include_file - $!\n";
        while (<$fh>) {
            chomp;
            next unless (/\w+/);
            $includes .= " -M $_";
        }
        close($fh);
    }
    my $cmd = "pp $0 --compile --cachedeps=/var/tmp/snag.pp --execute --bundle" . $includes . " -a /opt/snag/snag.conf -o snagc";

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

### Get rid of this once all sources are converted to dispatching

my $debug = $SNAG::flags{debug};

exit if already_running;

$SIG{INT} = $SIG{TERM} =  sub
{
  $poe_kernel->call('logger' => 'log' => "Killed");
  exit;
};

## Turn on logging 
logger();

daemonize unless $debug;

my $confin = CONF;

my $client;
if(ref ($confin->{client}) eq 'HASH')
{
  $client = [$confin->{client}]; 
}
else
{
  $client = $confin->{client};
}

SNAG::Client->new( $client );

SNAG::Dispatch->new();

if($confin->{source})
{
  foreach my $source (@{$confin->{source}})
  {
    next if ($SNAG::flags{source} && $SNAG::flags{source} ne $source->{name} && $source->{name} ne 'sysrrd');

    if ($SNAG::flags{"no$source->{name}"})
    {
      print "snagc: Skipping source \'$source->{name}\' due to --noXXX flag\n" if $debug;
      next;
    }

    print "Starting source \'$source->{name}\'\n" if $debug;

    my $mod_file = $source->{module};
    $mod_file =~ s/::/\//g;
    $mod_file .= ".pm";
    require $mod_file;

    $source->{module}->new
    (
      Alias	=> $source->{name},
      Source	=> $source->{ds}, 
      Options	=> $SNAG::flags,
    );
  }
}

$poe_kernel->run();
