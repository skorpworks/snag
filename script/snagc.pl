#!/usr/bin/env perl
### This script is used to gather system statistics and information for use with snagweb and its subapps

use strict; 
use FindBin qw($Bin $Script);
use lib "$FindBin::Bin/../lib";

use SNAG;
use SNAG::Client;
use SNAG::Dispatch;
use File::Spec::Functions qw/rootdir catpath catfile devnull catdir/;
use POE;

use Getopt::Long;

foreach my $arg (@ARGV)
{
  $arg =~ s/^\-{1,2}//;
  $SNAG::flags{$arg} = 1;
}

if($SNAG::flags{install})
{
  install('install');
}
elsif($SNAG::flags{uninstall} || $SNAG::flags{remove} || $SNAG::flags{'delete'})
{
  install('uninstall');
}
elsif($SNAG::flags{compile})
{
  unless($ENV{PAR_SPAWNED})
  {
    my $dest_bin = 'snagc';
    my $src_script = catfile( $Bin, $Script );

    print "Compiling $src_script to $dest_bin ... ";

    my $cmd = "pp -c \"$src_script\"";
    $cmd .= " -M XML::LibXML::SAX";
    $cmd .= " -M XML::SAX::PurePerl ";
    $cmd .= " -M Crypt::Blowfish ";
    $cmd .= " -M POE::Filter::Reference ";
    $cmd .= " -M POE::Wheel::Run ";
    $cmd .= " -M Date::Parse ";
    $cmd .= " -M Crypt::Blowfish ";
    $cmd .= " -M Net::Ping ";
    $cmd .= " -M SNAG::Source::SystemInfo";
    $cmd .= " -M SNAG::Source::SystemInfo::Linux";
    $cmd .= " -M SNAG::Source::SystemStats";
    $cmd .= " -M SNAG::Source::SystemStats::Linux";
    $cmd .= " -M SNAG::Source::SystemStats::Linux::RHEL5";
    $cmd .= " -M SNAG::Source::xen";
    $cmd .= " -M SNAG::Source::checkpoint";
    $cmd .= " -a \"/opt/local/SNAG/SNAG.xml;SNAG.xml\"";
    $cmd .= " -a \"/opt/local/SNAG/lib/perl5/site_perl/5.10.0/XML/SAX/ParserDetails.ini;ParserDetails.ini\"";
    $cmd .= " --lib=\"/opt/local/SNAG/modules\" ";
    $cmd .= " -o $dest_bin 2>&1";


    my $out;
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
}

### Get rid of this once all sources are converted to dispatching
our %options;
GetOptions(\%options, 'debug', 'verbose', 'startatend', 'noclient', 'source=s');

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
    next if ($options{source} && $options{source} ne $source->{name} && $source->{name} ne 'sysrrd');

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
      Options	=> \%options,
    );
  }
}

$poe_kernel->run();
