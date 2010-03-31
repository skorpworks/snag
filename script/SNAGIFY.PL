#!/usr/bin/env perl

BEGIN
{
  use File::Basename;
  chdir dirname $0;
  print "Changing dir to " . (dirname $@) . "\n";
  unshift @INC, "modules";
}

use strict;
use warnings;
use FindBin qw($Bin);
use File::Copy;
use File::Find;
use File::Path;
use Config::General qw/ParseConfig SaveConfig/; 
use Sys::Hostname;
use Data::Dumper;
use File::Spec::Functions qw/splitpath splitdir catfile rootdir catdir catpath/;
use Fcntl ':mode';

# Most of the SNAG constants won't be available until we generate the snag.conf
# We only use OS, OSDIST, and HOST_NAME which are config file independent
use SNAG;

my $host = HOST_NAME;
## Find our snag.conf outside of our directory
my $confin;
%$confin = ParseConfig(-ConfigFile => "snagify.conf");
my $confout;

my ($rlogin,$rpass,$ruid,$rgid) = getpwnam('root');
my ($ulogin,$upass,$uuid,$ugid) = getpwnam('snag');


unless(-d $confin->{directory}->{base_dir})
{
  print 'Creating ' . $confin->{directory}->{base_dir} . ' ... ';
  if(deep_mkdir($confin->{directory}->{base_dir}))
  {
    print "Done!\n";
  }
  else
  {
    print "FAILED!\n";
  } 
  $confout->{directory}->{base_dir} = $confin->{directory}->{base_dir};
}

#########
if(defined $confin->{directory}->{cfg_dir})
{
  if (-d $confin->{directory}->{cfg_dir})
  {
    print 'Wiping out existing ' . $confin->{directory}->{cfg_dir} . ' ... ';
    if(rmtree $confin->{directory}->{cfg_dir}, 0, 0)
    {
      print "Done!\n";
    }
    else
    {
      print "FAILED!\n";
    }
    $confout->{directory}->{cfg_dir} = $confin->{directory}->{cfg_dir};
  }

#########
  print 'Copying configs to ' . $confin->{directory}->{cfg_dir} . ' ... ';
  if(deep_copy('conf', $confin->{directory}->{cfg_dir}))
  {
    print "Done!\n";
  }
  else
  {
    print "FAILED!\n";
  }
#########
}

#########
unless(-d $confin->{directory}->{log_dir})
{
  print 'Creating ' . $confin->{directory}->{log_dir} . ' ... ';
  if(deep_mkdir($confin->{directory}->{log_dir}))
  {
    print "Done!\n";
  }
  else
  {
    print "FAILED\n";
  } 
  $confout->{directory}->{log_dir} = $confin->{directory}->{log_dir};
}

unless(-d $confin->{directory}->{tmp_dir})
{
  print 'Creating ' . $confin->{directory}->{tmp_dir} . ' ... ';
  if(deep_mkdir($confin->{directory}->{tmp_dir}))
  {
    print "Done!\n";
  }
  else
  {
    print "FAILED\n";
  } 
  $confout->{directory}->{tmp_dir} = $confin->{directory}->{tmp_dir};
}

unless(-d $confin->{directory}->{state_dir})
{
  print 'Creating ' . $confin->{directory}->{state_dir} . ' ... ';
  if(deep_mkdir($confin->{directory}->{state_dir}))
  {
    print "Done!\n";
  }
  else
  {
    print "FAILED\n";
  } 
  $confout->{directory}->{state_dir} = $confin->{directory}->{state_dir};
}

#############################################
########## STARTUP SCRIPTS ####################
#############################################
if(OS eq 'Linux' || OS eq 'SunOS')
{
  my $initd = '/etc/init.d/snag';
  my $script;
  if(OSDIST eq 'GENTOO')
  {
    $script = 'startup_scripts/GENTOO';
  }
  else
  {
    $script = 'startup_scripts/' . OS;
  }
  die "Could not find startup script $script" unless -e $script;

  print "Copying $script to $initd ... ";
  copy $script, $initd or die "Could not copy $script to $initd: $!";
  system "chmod 0755 $initd" and die "Could not chmod $initd: $!";
  print "Done!\n";

  if(OSDIST eq 'GENTOO')
  {
    my $script = 'startup_scripts/' . OSDIST;
    my $dir = '/etc/runlevels/default';
    warn "Directory $dir doesn't exist!" unless -d $dir;
    my $link = "$dir/snag";
    unless(-e $link)
    {
      print "Linking $initd to $link\n";
      system "ln -s $initd $link";
    }
  }
  else
  {
    my $script = 'startup_scripts/' . OS;
    my @levels;

    if(OS eq 'Linux')
    {
      @levels = (2,3,4,5);
    }
    else
    {
      @levels = (3);
    }
    foreach my $num (@levels)
    {
      my $dir = '/etc/rc' . $num . '.d';

      warn "Directory $dir doesn't exist!" unless -d $dir;
      next unless -d $dir;

      my $link = "$dir/S98snag";

      unless(-e $link)
      {
        print "Linking $initd to $link\n";
        system "ln -s $initd $link";
      }
    }
  }
}

my %server_info;
@server_info{"host", "fallbackip", "port", "key", "name"} = (@{$confin->{server}->{master}}{"host", "fallbackip", "port", "key"}, 'master');
push @{$confout->{client}}, \%server_info;


#############################################
########## SOURCE STUFF ####################
#############################################

if($confin->{host}->{$host}->{source_list})
{
  print "########################################\n";

  my $source_modules;
  foreach my $type (@{$confin->{host}->{$host}->{source_list}})
  {
    my %type_data = %{$confin->{source}->{$type}};
    $type_data{name} = $type;
    push @{$confout->{source}}, \%type_data;
  }
}

#############################################
########## POLLER STUFF #####################
#############################################
if($confin->{host}->{$host}->{poller})
{
  $confin->{host}->{$host}->{poller} = [ $confin->{host}->{$host}->{poller} ]
    if ref($confin->{host}->{$host}->{poller}) ne 'ARRAY';

  foreach my $type (@{$confin->{host}->{$host}->{poller}})
  { 
    print "+$type+\n";
    my %type_data = %{$confin->{poller}->{$type}};                                                                                                                                                              
    $confout->{poller}->{$type} = \%type_data;

    my $poller_exe = $confin->{directory}->{base_dir} . '/bin/' . $type . "_snagp.pl";                                                                                                                                                       
    unless(-e $poller_exe)
    {
      print "Linking $poller_exe to " . $confin->{directory}->{base_dir} . '/bin/snagp.pl ... ';                                                                                                                                             
      unless(system 'ln -s ' . $confin->{directory}->{base_dir} . "/bin/snagp.pl $poller_exe") ##LINUX ONLY, WHOOPS
      {
        print "Done!\n";
      }
      else
      {
        print "FAILED!\n";
      }
    }
  }                                               
}

#############################################
########## SERVER STUFF #####################
#############################################
if($confin->{host}->{$host}->{server})
{
  $confin->{host}->{$host}->{server} = [ $confin->{host}->{$host}->{server} ] 
    if ref($confin->{host}->{$host}->{server}) ne 'ARRAY';

  foreach my $type (@{$confin->{host}->{$host}->{server}})
  {
    my %type_data = %{$confin->{server}->{$type}};
    $confout->{server}->{$type} = \%type_data;

    my $server_exe = $confin->{directory}->{base_dir} . '/bin/' . $type . "_snags.pl";
    unless(-e $server_exe)
    {
      print "Linking $server_exe to " . $confin->{directory}->{base_dir} . 'bin/snags.pl ... ';
      unless(system 'ln -s ' . $confin->{directory}->{base_dir} . "/bin/snags.pl $server_exe") ##LINUX ONLY, WHOOPS!
      {
        print "Done!\n";
      }
      else
      {
        print "FAILED!\n";
      }
    }

    if($type =~ /rrd/)
    {
      copy('RULES.xml', $confin->{directory}->{base_dir}) or die $!;
    }
  }
}

$confout->{database} = \%{ $confin->{database} };
$confout->{network} = \%{ $confin->{network} };
$confout->{message} = \%{ $confin->{message} };
my $conf_file = catfile($confin->{directory}->{base_dir}, 'snag.conf');
print "Writing $conf_file ... ";
SaveConfig($conf_file, $confout);
chmod 0770, $conf_file; 
print "Done!\n";


if(OS eq 'Linux' || OS eq 'SunOS')
{
  print "Editing crontab ... ";
  my ($old_stuff, $found, $susp);
  my $tmpfile = "/tmp/snaginstallcronout";
  my $line = "30 * * * * " . $confin->{directory}->{base_dir} . "/snagw.pl > /dev/null";
  (my $line_match = $line) =~ s#([\#\*])#\\$1#g;

  open CRON, "> $tmpfile";
  open TEMP, "/usr/bin/crontab -l |";
  while (<TEMP>)
  {
    print CRON $_;

    if(/$line_match/)
    {
      $found = 1;
    }
  }
  close CRON;
  close TEMP;

  if($found)
  {
    print "No change required!\n";
  }
  else
  {
    system "echo '\n$line' >> $tmpfile";
    system "/usr/bin/crontab $tmpfile";
    print "Done!\n";
  }

  my $gid = $ugid||$rgid;
  my $mode = 0770;   
  chown $ruid, $gid, $confin->{directory}->{log_dir};
  chown $ruid, $gid, $confin->{directory}->{base_dir};
  chmod $mode, $confin->{directory}->{base_dir};
}



print "Done!\n";

sub deep_copy
{
  my ($source_dir, $dest_dir) = @_;
  eval
  {
    find
    (
      {
        wanted => sub
        {
          my $src = $_;
          s/^$source_dir/$dest_dir/;

          return if ($src =~ m/\/\.svn/);

          if(-d $src)
          {
            mkdir $_, 0770 or die $!;
          }
          else
          {
            copy($src, $_) or die $!;
          }
        },

        no_chdir => 1,
      },

      $source_dir
    );
  };
  if($@)
  {
    warn "Deep copy error: $@";
    return 0;
  }
  
  return 1;
}

sub deep_mkdir
{
  my ($vol, $dir) = splitpath( $_[0], 1 );

  eval
  {
    my @dirs = splitdir($dir);

    for (0..$#dirs)
    {
      my $dir = catpath($vol, catdir(@dirs[0..$_]));
      unless(-d $dir)
      {
        mkdir $dir, 0770 or die $!;
      }
    }
  };
  if($@)
  {
    warn "Deep mkdir error: $@";
    return 0;
  }

  return 1;
}

sub set_snag_perms
{
  my $gid = $ugid||$rgid;
  chown $ruid, $gid, $File::Find::name;
  my $mode = 0760;   
  chmod $mode, $File::Find::name;
  $mode = 0770;   
  chmod $mode, $File::Find::dir || warn "$!\n";
}

sub set_log_perms
{
  my $gid = $ugid||$rgid;
  chown $ruid, $gid, $File::Find::name;
  chmod S_IRWXU|S_IRWXG, $File::Find::dir;
  return unless $File::Find::dir eq $confin->{log_dir};
  chmod S_IRUSR|S_IWUSR|S_IRGRP|S_IWGRP, $File::Find::name;
}

sub set_rrd_perms
{
  my $gid = $ugid||$rgid;
  chown $gid, $ruid, $File::Find::name;
  my $mode = 0740;   
  chmod $mode, $File::Find::name;
  $mode = 0750;   
  chmod $mode, $File::Find::dir || warn "$!\n";
  if ($File::Find::dir =~ /.graphs/)
  { 
    chown $ruid, $ruid, $File::Find::name;
    my $mode = 0770;   
    chmod $mode, $File::Find::name;
    $mode = 0770;   
    chmod $mode, $File::Find::dir;
  }
}

