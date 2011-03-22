#!/usr/bin/env perl

use strict;

BEGIN { $ENV{POE_EVENT_LOOP} = "POE::XS::Loop::Poll"; };
use FindBin qw($Bin $Script);
use File::Spec::Functions qw(catfile);
use lib "/opt/snag/lib/perl5";

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
    my $dest_bin = 'snagp';
    my $src_script = catfile( $Bin, $Script );

    print "Compiling $src_script to $dest_bin ... ";
    my $cmd = '
               /opt/snag/bin/pp --compile "/opt/snag/bin/snagp.pl" 
               --bundle
               -M XML::SAX::PurePerl  
               -M Crypt::Blowfish  
               -M POE::Filter::Reference  
               -M POE::Wheel::Run  
               -M Date::Parse 
               -M DBM::Deep 
               -M Data::Dumper
               -M DBM::Deep::Engine::File 
               -M DBM::Deep::Iterator::File 
               -M Crypt::Blowfish  
               -M Net::Ping 
               -M Sys::Syslog
               -M SNAG  
               -M SNAG::Source::apache
               -M SNAG::Source::xen 
               -M SNAG::Source::mysql
               -M SNAG::Source::vserver
               -M SNAG::Source::apache_logs
               -M SNAG::Source::monitor     
               -M SNAG::Source::stormcellar     
               -M SNAG::Source::SystemInfo 
               -M SNAG::Source::SystemInfo::Linux 
               -M SNAG::Source::SystemStats 
               -M SNAG::Source::SystemStats::Linux 
               -a "/opt/snag/snag.conf" 
               -a "/opt/snag/lib/perl5/site_perl/5.12.1/XML/SAX/ParserDetails.ini;ParserDetails.ini" 
               --lib="/root/perl5/lib"  
               --reusable 
               -o snagp
              ';

    $cmd =~ s/([\n\r\l])+/ /g;

    print "with cmd $cmd\n";
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
