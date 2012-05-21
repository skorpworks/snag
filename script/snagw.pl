#!/usr/bin/env perl
### This is a watchdog for snagc[.pl]

use strict;

use FindBin qw($Bin $Script);

use SNAG;
use Config::General qw/ParseConfig/; 
use Cwd qw(abs_path);
use File::Basename;
use File::Spec::Functions qw/rootdir catpath catfile devnull catdir/;
use File::stat;
use Mail::Sendmail;
use Proc::ProcessTable;
use Sys::Hostname;
use Sys::Syslog;
use Data::Dumper;

use Getopt::Long;

our %options;
GetOptions(\%options, 'debug', 'syslog!', 'compile');
my $debug = delete $options{debug};
my $nosyslog = delete $options{nosyslog};

if($options{compile})
{
  unless($ENV{PAR_SPAWNED})
  {
    my $dest_bin = 'snagw';
    my $src_script = catfile( $Bin, $Script );

    print "Compiling $src_script to $dest_bin ... ";
    my $cmd = "
               pp --compile $0
               --bundle
	       -M Config::General
               -M Data::Dumper
               -M Data::Dumper::Concise
               -M Date::Parse
               -M Date::Format
	       -M Digest::MD5
	       -M IO::Uncompress::Gunzip
	       -M Log::Syslog::Fast
               -M Mail::Sendmail
	       -M Modern::Perl
	       -M POE::Wheel::Run
	       -M POE::Component::Client::NNTP 
	       -M POE::Wheel::FollowTail
               -M SNAG
               -M SNAG::BP
               -M Sys::Hostname
               -M Sys::Syslog
	       -M Statistics::LineFit
	       -M Statistics::Descriptive
               -M XML::SAX::PurePerl
               -M XML::Simple
               -a /opt/snag/snag.conf
	       --reusable
               -o snagw 
              ";
               #-a "/opt/snag/lib/perl5/site_perl/5.12.1/XML/SAX/ParserDetails.ini;ParserDetails.ini"

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

my $script   = BASE_DIR . "/bin/" . "snagc";
my $script_x = BASE_DIR . "/bin/" . "snagx";

#
# safety check to detect any abnormal snagc behaviour
#

my %pids;
# are snag[cx] already running?
my $procs = Proc::ProcessTable->new();
for my $proc (@{$procs->table()}) {
  if ($proc->cmndline() =~ /($script|$script_x)/) {
    my $foundproc = $1;
    $pids{basename($foundproc)} = $proc->pid();
    print "Found " . basename($foundproc) . " running.\n" if $debug;
  }
}

# FIXME: if we ever need snagw to run on windows, the mountpoint usage check will need re-writing...
print "Checking mountpoint usage...\n" if $debug;
my %mountpoints;
open(my $df, "df -k |") || die "Could not run df - $!\n";
while (<$df>) {
  next if (/^Filesystem/);
  my (undef, undef, undef, undef, $used, $mount) = split();
  $used =~ s/%//;
  $mountpoints{$mount} = $used;
}
close($df);

# where is BASE_DIR mounted?
my $absdirname = abs_path(BASE_DIR);
my ($basedir) = (File::Spec->splitdir($absdirname))[1];
$basedir = '/' . $basedir;
my $snag_mounted_on = $mountpoints{$basedir} ? $basedir : '/';

print "Checking available disk space...\n" if $debug;
# check to ensure whatever mount point BASE_DIR is found is under 98% full...
my $above_disk_threshold = $mountpoints{$snag_mounted_on} >= 98 ? 1 : 0;
if ($above_disk_threshold) {
  # we're above the disk usage threshold, if any snag daemons are running, kill them...
  openlog('snagw', 'ndelay', 'user');
  syslog('notice', "disk usage threshold: $snag_mounted_on is $mountpoints{$snag_mounted_on}% full " . HOST_NAME);
  closelog();
  for my $daemon (keys(%pids)) {
    # for safety, to ensure queue files don't fill up the disk we'll kill the daemons...
    for my $attempt (1..3) {
      kill 'TERM', $pids{$daemon};
      sleep 1;
      last unless ((kill 0, $pids{$daemon}));
      if ($attempt == 3) {
        print "Tried to kill $daemon with PID $pids{$daemon} $attempt times, failed.\n" if $debug;
      }
    }
  }
  print "$snag_mounted_on is $mountpoints{$snag_mounted_on}% full.  Exiting.\n" if $debug;
  exit();
}
     
# check to ensure queue files are not above 200MB
print "Checking size of queue files in " . LOG_DIR . "...\n" if $debug;
opendir(my $logdir, LOG_DIR) || die "Could not open " . LOG_DIR . " - $!\n";
for my $filefound (grep /queue/, readdir($logdir)) {
  my $queue_file_path = File::Spec->catfile($logdir, $filefound);
  my $filesize = (-s $queue_file_path);
  if ($filesize >= 200000000) {
    openlog('snagw', 'ndelay', 'user');
    syslog('notice', "queue file error: file is $filesize bytes " . HOST_NAME);
    closelog();
    print "$queue_file_path is $filesize bytes, wrote to syslog\n" if $debug;
  }
}
closedir($logdir);

# check that snagc is updating the queue file...
print "Checking mtime of queue file in " . LOG_DIR . "...\n" if $debug;
# not doing the queue file mtime check for snagx queue files because it's possible for a product
# to be purposely down and thus *_snagx will not run and thus not update queue files...
my $file_to_check = File::Spec->catfile(LOG_DIR, 'snagc_sysrrd_client_queue.dat');
my $now  = time();
my $stat = stat($file_to_check);
# we're concerned if the file has not been modified in 300 seconds
if (($now - $stat->mtime()) >= 300) {
  openlog('snagw', 'ndelay', 'user');
  syslog('notice', 'queue file error: file older than 300 seconds ' . HOST_NAME);
  closelog();
  print "$file_to_check is older than 300 seconds, wrote to syslog\n" if $debug;
}
print "Checks complete.\n" if $debug;

# start snagc unless it's already running...
unless ($pids{snagc}) {
  if (-x $script) {
    print "Starting $script ... " if $debug;
    system $script;
    print "Done!\n" if $debug;
  }
}

# start snagx unless it's aready running...
unless ($pids{snagx}) {
   if (-x $script_x) {
    print "Starting $script_x ... " if $debug;
    system $script_x;
    print "Done!\n" if $debug;
  }
}

### Start any additional snags.pl or snagp.pl, if configured to run on this host
my $conf = CONF;

if($conf->{server})
{
  foreach my $server (keys %{$conf->{server}})
  {
    my $script_bin = $server . '_snags';
    my $script_path = BASE_DIR . "/bin/" . $script_bin;

    print "Starting $script_path ... " if $debug;
    system $script_path;
    print "Done!\n" if $debug;
  }
}

if($conf->{poller})
{
  foreach my $poller (keys %{$conf->{poller}})
  {
    my $default_bin   = BASE_DIR . "/bin/" . $poller . '_snagp';
    my $alternate_bin = BASE_DIR . "/bin/" . $poller . '_snagp.pl';
    for my $script_path ($default_bin, $alternate_bin) {
      if (-e $script_path) {
        print "Starting $script_path ..." if $debug;
        system $script_path;
        print "Done!\n" if $debug;
        last;
      }
    }
  }
}

exit 0 if $nosyslog;

print "Sending syslog heartbeat ... " if $debug;
openlog('snagw', 'ndelay', 'user');
syslog('notice', 'syslog heartbeat from ' . HOST_NAME);
closelog();
print "Done!\n" if $debug;
