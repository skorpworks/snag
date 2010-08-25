#!/usr/bin/env perl
### This is a watchdog for snagc[.pl]

use strict;

use FindBin qw($Bin $Script);
use lib "/opt/snag/lib/perl5";

use SNAG;
use Config::General qw/ParseConfig/; 
use File::Spec::Functions qw/rootdir catpath catfile devnull catdir/;
use Mail::Sendmail;
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
    my $cmd = '
               /opt/snag/bin/pp -c "/opt/snag/bin/snagw.pl"
               -M XML::SAX::PurePerl
               -M Mail::Sendmail
               -M Sys::Hostname
               -M Sys::Syslog
               -M Data::Dumper
               -M Date::Parse
               -M SNAG
               -a "/opt/snag/snag.conf"
               -a "/opt/snag/lib/perl5/site_perl/5.12.1/XML/SAX/ParserDetails.ini;ParserDetails.ini"
               -o snagw 
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

### Start snagc
my $script = BASE_DIR . "/bin/" . "snagc";
print "Starting $script ... " if $debug;
system $script;
print "Done!\n" if $debug;

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
    my $script_bin = $poller . '_snagp';
    my $script_path = BASE_DIR . "/bin/" . $script_bin;

    print "Starting $script_path ... " if $debug;
    system $script_path;
    print "Done!\n" if $debug;
  }
}

exit 0 if $nosyslog;

print "Sending syslog heartbeat ... " if $debug;
openlog('snagw', 'ndelay', 'user');
syslog('notice', 'syslog heartbeat from ' . HOST_NAME);
closelog();
print "Done!\n" if $debug;
