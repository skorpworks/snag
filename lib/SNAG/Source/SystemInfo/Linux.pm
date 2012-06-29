package SNAG::Source::SystemInfo::Linux;
use base 'Exporter';

use strict;
use SNAG;
use File::Find;
use DBM::Deep;
use DBM::Deep::Engine::File;                                                                                                                                                                                                                                                   
use DBM::Deep::Iterator::File;   
use File::Spec::Functions qw/catfile/;
use Storable qw/dclone store retrieve/;
use Proc::ProcessTable;
use Date::Format;
use Data::Dumper::Concise;
use Digest::SHA qw(sha256_hex);
use Digest::MD5 qw(md5_hex);
use Net::Nslookup;
use File::Which;
use Network::IPv4Addr qw(ipv4_parse ipv4_cidr2msk);

our @EXPORT = qw/installed_software_check config_files_check vmware_host arp startup portage system static_routes bonding config_files_whole installed_software_whole service_monitor iscsi mounts smartctl/; 
our %EXPORT_TAGS = ( 'all' => \@EXPORT ); 

### The periods must all have the same lowest common
our $config =
{
  'iscsi'	        => { 'period' => 60, if_tag => 'storage.iscsi.client' },

  'listening_ports'     => { 'period' => 300, data => $SNAG::Dispatch::shared_data },
  'tags'          	=> { 'period' => 300, data => $SNAG::Dispatch::shared_data },
  'service_monitor'     => { 'period' => 300 },
  'mounts'              => { 'period' => 300 },

  'installed_software_check' => { 'period' => 600 },
  'config_files_check' 	=> { 'period' => 600 },

  'bonding'             => { 'period' => 300 },

  'smartctl'            => { 'period' => 900, data => $SNAG::Dispatch::shared_data },

  'vmware_host'		=> { 'period' => 1800, if_tag => 'virtual.vmware.host' },

  'arp' 		=> { 'period' => 7200 },

  'startup'             => { 'period' => 21600 },

  'portage'             => { 'period' => 21600 },

  'system' 		=> { 'period' => 21600, data => $SNAG::Dispatch::shared_data },
  #'kernel_settings'     => { 'period' => 21600 }, ### Too noisy, refine and maybe use later
  'static_routes'       => { 'period' => 21600 },
  'config_files_whole' 	=> { 'period' => 21600 },

  'apache_version'      => { 'period' => 21600, if_tag => 'service.web.apache' },

  'installed_software_whole'	=> { 'period' => 43200 },
};

#our @EXPORT = keys %$config;
#our %EXPORT_TAGS = ( 'all' => \@EXPORT ); fix the $config stuff in SystemInfo first

######## Default files to track
my %default_config_files = 
(
  '/boot/grub/grub.conf' => 1,
  '/etc/apt/sources.list' => 1,
  '/etc/fstab' => 1,
  '/etc/group' => 1,    
  '/etc/hosts' => 1,
  '/etc/hosts.allow' => 1,
  '/etc/hosts.deny' => 1,
  '/etc/inittab' => 1,
  '/etc/issue' => 1,
  '/etc/iscsi.conf' => 1,
  '/etc/krb5.conf' => 1,
  '/etc/krb.conf' => 1, 
  '/etc/mail/sendmail.cf' => 1,
  '/etc/mail/submit.cf' => 1,
  '/etc/motd' => 1,     
  '/etc/nsswitch.conf' => 1,
  '/etc/ntp.conf' => 1,
  '/etc/pam.d/su' => 1, 
  '/etc/pam.d/system-auth' => 1,
  '/etc/passwd' => 1,
  '/etc/shadow' => 1,
  '/etc/profile' => 1,
  '/etc/resolv.conf' => 1,
  '/etc/selinux/config' => 1,
  '/etc/services' => 1,
  '/etc/ssh/sshd_config' => 1,
  '/etc/sudoers' => 1,
  '/etc/sysconfig/network' => 1,
  '/etc/sysctl.conf' => 1,
  '/etc/syslog.conf' => 1,
  '/etc/rsyslog.conf' => 1,
  '/etc/system' => 1,
  '/etc/xinetd.d/eklogin' => 1, 
  '/proc/vmware/version' => 1,
  '/proc/mdstat' => 1,
  '/root/.ssh/authorized_keys' => 1,
  '/usr/lib/portage/bin/pkglist' => 1,
  '/usr/local/apache2/conf/httpd.conf' => 1,
  '/usr/local/apache2/conf/ssl.conf' => 1,
  '/usr/local/apache2/conf/extra/Alias.conf' => 1,
  '/usr/local/apache2/conf/extra/Redirect.conf' => 1,
  '/usr/local/apache2/conf/extra/Proxy.conf' => 1,
  '/usr/local/apache2/conf/extra/httpd-vhosts.conf' => 1,
  '/usr/local/apache2/conf/extra/httpd-ssl.conf' => 1,
  '/usr/local/apache2/conf/workers.properties' => 1,
  '/usr/local/apache2/conf/uriworkermap.properties' => 1,
  '/usr/portage/metadata/timestamp' => 1,
  '/usr/vice/etc/cacheinfo' => 1,
  '/var/lib/portage/config' => 1,
  '/var/lib/portage/world' => 1,
  '/var/lib/pgsql/data/postgresql.conf' => 1,
  '/var/lib/pgsql/data/pg_hba.conf' => 1,
  '/etc/sysconfig/rhn/up2date' => 1,
  '/etc/sysconfig/rhn/systemid' => 1,
  '/etc/yum.conf' => 1,
  '/etc/make.conf' => 1,
);

$default_config_files{LOG_DIR . '/snag.uuid'} = 1;

my %default_config_dirs =
(
  "/etc/"                           => '.*.conf$', # use . for wildcard for entire directory
  "/etc/conf.d/"                    => '.', # use . for wildcard for entire directory
  "/etc/cron.d/"                    => '.', # use . for wildcard for entire directory
  "/etc/cron.daily/"                => '.', # use . for wildcard for entire directory
  "/etc/cron.hourly/"               => '.', # use . for wildcard for entire directory
  "/etc/cron.weekly/"               => '.', # use . for wildcard for entire directory
  "/etc/logrotate.d/"               => '.',
  "/etc/rsyslog.d/"                 => '.',
  "/etc/ssh/"                       => '.',
  "/etc/sysconfig/"                 => '.', # use . for wildcard for entire directory
  "/etc/sysconfig/network-scripts/" => 'ifcfg-',
  "/etc/yum/"                       => 'yum-',
  "/etc/yum.repos.d/"               => '.', # use . for wildcard for entire directory
  "/root/.ssh/"                     => '(.pub|authorized_keys)$',
);

#### Add some more files at runtime
sub build_config_file_list
{
  my %config_files = map { $_ => 1 } grep { -e $_ } keys %default_config_files;

  my $host = HOST_NAME;

  if( $host =~ /^somehosttoignore\d$/ ) #TODO this needs to be a config option or go away
  {
    ### ignore auth files on interactive machines, too noisy
    delete $config_files{'/etc/passwd'};
    delete $config_files{'/etc/group'};
    delete $config_files{'/etc/shadow'};
  }

  # add all config files for vservers
  my @vservers = glob('/etc/vservers/*');
  $default_config_dirs{$_ . '/'} = '.' for @vservers;
  
  foreach my $dir (keys %default_config_dirs)
  {
    next unless -d $dir;
    opendir SCRIPTS, $dir;
    foreach my $name (readdir SCRIPTS)
    { 
      next if $name =~ /^(\.+)$/; # ignore . and .. inside wildcard directories
      next unless $name =~ /$default_config_dirs{$dir}/;
      next unless -f $dir . $name; 
      $config_files{$dir . $name} = 1;
    }
    closedir SCRIPTS;
  }

  foreach my $cron_dir ('/var/spool/cron/', '/var/spool/cron/crontabs/')
  {
    opendir CRONS, $cron_dir;
    foreach my $name (grep { $_ ne '.' && $_ ne '..' } readdir CRONS)
    {
      next if $name eq 'core';

      my $file = $cron_dir . $name;
      if(-f $file)
      {
        $config_files{$cron_dir . $name} = 1;
      }
    }
    closedir CRONS;
  }

  if(-e '/proc/vmware/vm/')
  {
    find
    (
      sub
      {
	if($_ eq 'names')
	{
	  open IN, $File::Find::name;
	  my $line;
	  while(<IN>)
	  {
	    if(/uuid/)
	    {
              my ($cfg_file) = /cfgFile=\"([^\"]+)\"/;

	      $config_files{$cfg_file} = 1;
	    }
	  }
	}
      },
      '/proc/vmware/vm/'
    );
  }

  return \%config_files;
}

sub service_monitor
{
  my $state_file = catfile(LOG_DIR, 'service_monitor.state');

  my $service_monitor;

  if(-e $state_file)
  {
    $service_monitor = retrieve($state_file) or die "Could not open $state_file";
  }

  my $table = new Proc::ProcessTable;

  my $process_list;
  foreach my $ref (@{$table->table})
  {
    $process_list->{ $ref->{pid} } = $ref;
  }

  my $active_procs;
  my $info;

  while( my ($pid, $ref) = each %$process_list)
  {
    ### Ignore any process owned by SNAGc.pl
    if(defined $ref->{ppid} && defined $process_list->{ $ref->{ppid} }->{fname} && $process_list->{ $ref->{ppid} }->{fname} =~ m/\bsnagc(\.pl|.{0})\b/i)
    {
      #print "Skipping $ref->{fname} because owned by SNAGc.pl\n";
      next;
    }

    next if (defined $ref->{state} && $ref->{state} eq 'defunct');
    next unless $ref->{fname};

    $active_procs->{ $ref->{fname} }->{ $ref->{cmndline} }++;

    unless($service_monitor->{ $ref->{fname} })
    {
      ### don't keep track of new services if they're first discovered running in a tty
      unless($ref->{ttydev})
      {
        $service_monitor->{ $ref->{fname} } = {};
      }
    }

    if( !$ref->{ttydev} && defined $service_monitor->{$ref->{fname}} && defined $service_monitor->{$ref->{fname}}->{run_ratio} && $service_monitor->{$ref->{fname}}->{run_ratio} > .9 && $service_monitor->{$ref->{fname}}->{samples} > 48)
    {
      unless ($ref->{'cmndline'} =~ m/^\/proc/ || $ref->{'exec'} =~ m/^\/usr\/sbin\/cron/)
      {
        #print "$ref->{'cmndline'}, 'cwd' => $ref->{'cwd'}, 'exec' => $ref->{'exec'}\n";
        push @{$info->{process}}, { 'process' => $ref->{fname}, 'cmdline' => $ref->{'cmndline'}, 'cwd' => $ref->{'cwd'}, 'exec' => $ref->{'exec'} };
      }
    }
  }

  @{$info->{process}} = sort { $a->{process} cmp $b->{process} } @{$info->{process}} if defined $info->{process};

  foreach my $proc (keys %$service_monitor)
  {
    my $running_flag = exists $active_procs->{$proc} ? 1 : 0;

    my ($old_ratio, $samples) = (0, 0);

    if($service_monitor->{$proc})
    {
      $old_ratio = $service_monitor->{$proc}->{run_ratio};
      $samples = $service_monitor->{$proc}->{samples};
    }

    if($samples > 40 && !$running_flag && $old_ratio > .9)
    {
      my $pct = sprintf('%.0f', $old_ratio * 100);
      my $seen = time2str("%Y-%m-%d %T", time);

      print STDERR join REC_SEP, ('events', HOST_NAME, 'sysinfo', 'service_state', 'service state change', "proc $proc is not running.  usual run rate is $pct%", '', $seen);  print STDERR "\n";
    }

    my $new_ratio = ( ( $old_ratio * $samples ) + $running_flag ) / ( $samples + 1 );

    $service_monitor->{$proc}->{run_ratio} = $new_ratio;
    
    ### keep only a window of the last week
    $samples = $samples >= 10080 ? 10080 : ($samples + 1);
    $service_monitor->{$proc}->{samples} = $samples;
  }

  store($service_monitor, $state_file) or die "Could not store $state_file";

  return $info;
}


sub config_files_whole
{
  my $args = shift;

  my $info;

  #Add any new files that might have popped up
  my $config_files = build_config_file_list();

  my $state_files = DBM::Deep->new
  (
    file => catfile(LOG_DIR, 'sysinfo_conf_files.state'),
    autoflush => 1,
  ) or die $!;

  $state_files->clear;
  $state_files->optimize;

  $state_files->import({ %$state_files, %$config_files });

  foreach my $file (keys %$state_files)
  {
    if(-e $file)
    {
      (my $escaped_file = $file) =~ s#([ ()])#\\$1#g;

      if($file eq '/etc/shadow')
      {
        local $/ = "\n";

        my $contents;

        open (SHAD, "</etc/shadow");
        while (<SHAD>)
        {
          s/^([\w\_\.]+)\:([\w\/\\\.\$]{3,})\:/"$1:" . sha256_hex(md5_hex($2))/e;
          $contents .= $_;
        }
        close SHAD;

        $info->{conf}->{$file} = { contents => $contents };
      }
      else
      {
        $info->{conf}->{$file} = { contents => `/bin/cat $escaped_file` || '' };
      }
    }
    else
    {
      delete $state_files->{$file};
      $info->{conf}->{$file} = undef;
    }
  }
  return $info;
}

sub config_files_check
{
  my $args = shift;
  my $period = $args->{period};

  my $info;

  my $now = time;

  my $state_files = DBM::Deep->new
  (
    file => catfile(LOG_DIR, 'sysinfo_conf_files.state'),
    autoflush => 1,
  ) or die $!;

  foreach my $file (keys %$state_files)
  {
    if(-e $file)
    {
      my $mtime = (stat $file)[9];

      if(($now - $mtime) < $period) 
      {
        (my $escaped_file = $file) =~ s#([ ()])#\\$1#g;

        if($file eq '/etc/shadow')
        {
          local $/ = "\n";

          my $contents;

          open (SHAD, "</etc/shadow");
          while (<SHAD>)
          {
            s/^([\w\_\.]+)\:([\w\/\\\.\$]{3,})\:/"$1:" . sha256_hex(md5_hex($2))/e;
            $contents .= $_;
          }
          close SHAD;

          $info->{conf}->{$file} = { contents => $contents };
        }
        else
        {
          $info->{conf}->{$file} = { contents => `/bin/cat $escaped_file` || '' };
        }
      }
    }
    else
    {
      delete $state_files->{$file};
      $info->{conf}->{$file} = undef;
    }
  }

  return $info;
}

sub installed_software_check
{
  my $args = shift;

  my $info;

  my $period = $args->{period};
  my $now = time;

  if (-d '/var/db/pkg')
  {
    my $mtime = (stat '/var/db/pkg')[9];
    if(($now - $mtime) < $period)
    {
      $info->{conf}->{installed_software} = { contents => join "\n", sort { $a cmp $b } split /\n/, `find /var/db/pkg/ -mindepth 2 -maxdepth 2 -printf "%P\n"` };
    }
  }
#  elsif (-x '/var/lib/dpkg/status')
#  {
#    my $mtime = (stat '/var/lib/dpkg/status')[9];
#    if(($now - $mtime) < $period)
#    {
#      $info->{conf}->{installed_software} = { contents => join "\n", sort { $a cmp $b } split /\n/, `/bin/rpm -qa` };
#    }
##ii  xz-utils                                              4.999.9beta+20091116-1                                XZ-format compression utilities
##ii  zlib1g                                                1:1.2.3.3.dfsg-15ubuntu1                              compression library - runtime
##root@s04-b001:/var/tmp/snag# dpkg-query --list|wc -l
#
#  }
  elsif ( -r '/var/lib/rpm/Packages')
  {
    my $mtime = (stat '/var/lib/rpm/Packages')[9];
    if(($now - $mtime) < $period)
    {
      $info->{conf}->{installed_software} = { contents => join "\n", sort { $a cmp $b } split /\n/, `/bin/rpm -qa` };
    }
  }

  return $info;
}

sub installed_software_whole
{
  my $info;

  if (-d '/var/db/pkg')
  {
    $info->{conf}->{installed_software} = { contents => join "\n", sort { $a cmp $b } split /\n/, `find /var/db/pkg/ -mindepth 2 -maxdepth 2 -printf "%P\n"` };
  }
  elsif (-e '/bin/rpm')
  {
    $info->{conf}->{installed_software} = { contents => join "\n", sort { $a cmp $b } split /\n/, `/bin/rpm -qa` };
  }

  return $info;
}

sub startup
{
  my $info;

  $info->{conf}->{startup} = { contents => `/sbin/chkconfig --list` } if -e '/sbin/chkconfig';

  return $info;
}

sub portage
{
  my $info;

  $info->{conf}->{portage} = { contents => `/usr/bin/emerge --info 2>&1` } if -e '/usr/bin/emerge';

  return $info;
}

sub static_routes
{
  my $info;

  $info->{conf}->{static_routes} = { contents => `/bin/netstat -rn` };

  return $info;
}

sub bonding
{
  my ($info, $int);

  my $dir = '/proc/net/bonding';

  return unless -d $dir;

  opendir SCRIPTS, $dir;
  foreach my $file (readdir SCRIPTS)
  {
    local $/ = "\n";
    my $contents;
    open BOND, "<$dir/$file";
    while (<BOND>)
    {
      if (/^Bonding Mode:\s+(.*)$/)
      {
        $contents .= $_;
      }
      elsif(/^MII Status:\s+(\S+)/)
      {
        $contents .= $_;
      }
      elsif (/^Link Failure Count:\s+(\d+)/)
      {
      }
      else
      {
        $contents .= $_;
      }
    }
    close BOND;
    $info->{conf}->{$dir.'/'.$file} = { contents => $contents };
  }
  close SCRIPTS;

  return $info;
}

sub smartctl
{                                                                                                                                                                                                                                                                             
  my $info;

  my $args = shift;
  my $lsscsi = dclone $args->{data}->{lsscsi} if defined $args->{data}->{lsscsi};
  #perl -e 'if (-d "/sys/class/scsi_generic") {foreach $d (</sys/class/scsi_generic/sg*>) { print "$d\n"; }} elsif (-d "/sys/block") {foreach $d (</sys/block/[hs]d*>) { print "$d\n"; }}'
  
  {
    local $/ = "\n";
    foreach my $out (`lsscsi -g`)
    {
      chomp $out;
      push @{$info->{lsscsi}}, $out;
    }
  }

  foreach my $out (@{$info->{lsscsi}})
  {
    if ($out =~ m/^\[([\d:]+)\].*(\/dev\/\w+)\s+(\/dev\/sg\d+)\s*$/)
    {
      my ($cp, $drive, $sg) = ($1, $2, $3);
      eval 
      {    
        local $/ = "\n";

        my ($disk, $device, $vendor, $product, $version, $serial, $capacity, $transport, $smart);  
        ($disk, $device, $version, $serial, $capacity, $transport) = '';  
        $smart = 0;

        foreach (`smartctl -i $sg 2>&1`)
        {                                                                                 
          chomp;                                                                          
                                                                                          
          #Device: CSC300GB 10K REFURBISHED  Version: 0123
          #Device: FUJITSU  MAP3735NC        Version: 0108
          if (m/^Device(:)\s+(.*?)Version: (.*)$/i)                                       
          {                                                                               
            $device = $2;                                                                 
            $version = $3;                                                                
          }                                                                               
          #Device Model:     WDC WD30EZRS-00J99B0                                           
          #Device Model:     SAMSUNG HD203WI                                                
          #Device Model:     SAMSUNG HD203WI
          elsif (m/^Device Model:\s+(.*)$/i)                                              
          {                                                                               
            $device = $1;                                                                 
          }                                                                               
	  #Vendor:               CSC300GB
	  #Product:              10K REFURBISHED
	  #Revision:             0123
          elsif (m/^Vendor:\s+(.*)$/i)                                              
          {                                                                               
            $vendor = $1;                                                                 
	    $device = "$vendor $product" if defined $product;
	  }
          elsif (m/^Product:\s+(.*)$/i)                                              
          {                                                                               
            $product = $1;                                                                 
	    $device = "$vendor $product" if defined $vendor;
	  }
          elsif (m/^Revision:\s+(.*)$/i)                                              
          {                                                                               
            $version= $1;                                                                 
          }                                                                               
          #Serial number:                     
          #Serial number: UPE0P49025D2
          #Serial Number:    S1UYJ1YZ600005
          #Serial Number:    WD-WCAWZ0117762                                                
          elsif (m/^Serial Number:\s+(.*)$/i)                                             
          {                                                                               
            $serial = $1;                                                                 
          }                                                                               
          #Firmware Version: 80.00A80                                                       
          #Firmware Version: 1AN10002                                                       
          #Firmware Version: 1AN10002
          elsif (m/^Firmware Version:\s+(.*)$/i)                                          
          {                                                                               
            $version = $1;                                                                
          }                                                                               
          #User Capacity:    3,000,592,982,016 bytes                                        
          #User Capacity:    2,000,398,934,016 bytes                                        
          #User Capacity:    2,000,398,934,016 bytes [2.00 TB]
          elsif (m/^User Capacity:\s+(.*)$/i)                                             
          {                                                                               
            $capacity = $1;                                                               
            $capacity =~ s/,//g;
          }                                                                               
          #ATA Standard is:  Exact ATA specification draft version not indicated                
          #ATA Standard is:  Not recognized. Minor revision code: 0x28                      
          #ATA Version is:   8
          #ATA Standard is:  ATA-8-ACS revision 6
          elsif (m/^ATA Version is:\s+(.*)$/i)                                             
          {
            $transport = "ATA $1";                                                               
          }
          #Transport protocol: Parallel SCSI (SPI-4)
          elsif (m/^Transport protocol:\s+(.*)$/i)                                             
          {
            $transport = "$1";                                                               
          }
          #Device supports SMART and is Enabled
          #Device supports SMART and is Disabled
          #SMART support is: Available - device has SMART capability.
          #SMART support is: Enabled
          elsif (m/^(Device supports SMART and is Enabled|SMART support is: Enabled)/)    
          {                                                                               
            $smart = 1;                                                                 
          }           
        }
        push @{$info->{smartctl}}, { drive => $drive, device => $device, version => $version, serial => $serial, capacity => $capacity||'NA', transport => $transport, smart => $smart };  
      };
      if ($@)
      {
        print STDERR "sysinfo_debug: smartctl error $@\n";
        push @{$info->{smartctl}}, { drive => $drive, device => 'X', version => 'X', serial => 'X', capacity => 'X', transport => 'X', smart => 'X'};  
      }
    }
  }
  return $info;
}

sub arp
{
  my $info;

  my $args = shift;
  delete $args->{state};


  if ( -e '/proc/net/arp')
  {
    local $/ = "\n";
    open (ARP, "</proc/net/arp");
    while(<ARP>)
    { 
      if ( m/^([\d\.]+) \s+ \S+ \s+ \S+ \s+ ([\w\:]+) \s+/x )
      { 
        push @{$info->{arp}}, { remote => $1, mac => $2 };
      }
    }
    close ARP;
  }
  else
  { 
    local $/ = "\n";

    foreach my $line (`/sbin/arp -n`)
    { 
      next if $line =~ /^Address/;
      next if $line =~ /incomplete/;
      my ($ip, $mac) = (split /\s+/, $line)[0, 2];
      push @{$info->{arp}}, { remote => $ip, mac => $mac };
    }
  }

  return $info;
}

my ($bins, $missing_bins);
foreach my $bin (qw (ip ifconfig ethtool))
{
  $bins->{$bin} = which("$bin");
  $missing_bins .= "$bin" unless defined $bins->{$bin};
}

unless(defined $bins->{ethtool})
{
  #$poe_kernel->post('logger' => 'alert' => { Subject => 'SNAG::Source::SystemInfo, ' . HOST_NAME . ', Could not find ethtool on this box!' } );
}

sub system 
{
  my $args = shift;

  my $tags = dclone $args->{data}->{tags};

  local $/ = "\n";

  my $info;

  #$info->{host} = HOST_NAME;
  $info->{entity}->{type} = 'system';

  $info->{SNAG}->{version} = VERSION;
  $info->{SNAG}->{perl} = `$^X -V`;

  $info->{os}->{os} = OS;
  $info->{os}->{os_version} = OSLONG;
  chomp(my $kernel = `/bin/uname -r`);
  $info->{os}->{os_kernel} = $kernel;
  chomp(my $arch = `/bin/uname -m`);
  $info->{os}->{os_arch} = $arch;

  if($tags->{virtual}->{xen}->{guest})
  {
    if(-e '/usr/bin/xenstore-read')
    {
      my $get_uuid = `/usr/bin/xenstore-read vm`;
      my ($uuid) = ($get_uuid =~ m#/vm/([\w\-]+)$#);

      $info->{device}->{uuid} = $uuid;
    }

    $info->{device}->{model} = 'Xen Virtual Platform';
    $info->{device}->{vendor} = 'Xen';
  }

  # prefer system dmidecode over any one we've tried to include
  my $dmi_bin;
  if(-e '/usr/sbin/dmidecode')
  {
    $dmi_bin = '/usr/sbin/dmidecode';
  }
  else
  {
    $dmi_bin = BASE_DIR . '/sbin/dmidecode';
  }
  my $dmi_section;
  my @mem_tot;
  foreach(`$dmi_bin`)
  {
    undef $dmi_section if /^Handle/;
    if(/^\s*(\w+)\s+Information\s*$/)
    {
      $dmi_section = $1;
    }
    elsif(/^\s+Memory Device\s*$/)
    {
      $dmi_section = 'Memory Device';
    }

    if($dmi_section eq 'BIOS')
    {
      if(/Vendor:\s+(.+)\s*/)
      {
        $info->{bios}->{bios_vendor} = $1;
      }

      if(/Version:\s+(.+)\s*/)
      {
        $info->{bios}->{bios_version} = $1;
      }
      
      if(/Release Date:\s+(.+)\s*/)
      {
        $info->{bios}->{bios_date} = $1;
      }
    }
    elsif($dmi_section eq 'System') 
    {
      if(/Manufacturer:\s+(.+)\s*/)
      {
        $info->{device}->{vendor} = $1;
      }

      if(/Product Name:\s+(.+)\s*/)
      {
        my $model = $1;
        if($model =~ s/\s*\-\[(\w+)\]\-//)
        {
          $info->{device}->{model_type} = $1
        }

        $info->{device}->{model} = $model;
      }

      if(/Serial Number:\s+(.+)$/)
      {
        my $serial = $1;
        $serial =~ s/^\s*//g;
        $serial =~ s/\s*$//g;

        $info->{device}->{serial} = $serial unless $serial eq 'Not Specified';
      }

      if(/UUID:\s+(\S+)\s*/)
      {
        $info->{device}->{uuid} = $1;
      }
    }
    elsif($dmi_section eq 'Processor')
    {
      if(/Current Speed:\s+(.+)\s*/)
      {
        $info->{cpumem}->{cpu_speed} = $1;
      }
    }
    elsif($dmi_section eq 'Memory Device')
    {
      if(/^\s*Size:\s+(.+)\s*$/)
      {
        push @mem_tot, $1;
      }
    }
  }

  if(@mem_tot)
  {
    my $total;

    foreach my $val (@mem_tot)
    {
      my ($num, $units) = split /\s+/, $val;

      if($units =~ /^(kb|kilobytes)$/i)
      {
        $num = $num / 1048576;
      }
      elsif($units =~ /^(mb|megabytes)$/i)
      {
        $num = $num / 1024;
      }

      $total += $num;
    }

    $info->{cpumem}->{mem_tot} = sprintf('%.1f', $total) . ' GB';
  }

  if(-e '/proc/cpuinfo')   
  {
    #model name      : Pentium III (Coppermine)
    #stepping        : 3
    #cpu MHz         : 864.003
    #cache size      : 256 KB

    #model name      : Intel(R) Xeon(TM) CPU 3.20GHz
    #stepping        : 5
    #cpu MHz         : 3193.094
    #cache size      : 512 KB

    open CPU, '/proc/cpuinfo';
    
    my $cpu_count;
    while(<CPU>)
    {
      chomp;

      my ($key, $val) = split /\s+:\s+/;

      if($key eq 'model name')
      {
        if($info->{cpumem}->{cpu} && $info->{cpumem}->{cpu} ne $val) 
        {
          print STDERR "More than one cpu type on this host" ;
        }

        $cpu_count++;
        $info->{cpumem}->{cpu} = $val
      }

      if($key eq 'cache size')
      {
        $info->{cpumem}->{cpu_cache} = $val;
      }
    }
    close CPU;

    $info->{cpumem}->{cpu_count} = $cpu_count
  }

  if(-e '/proc/meminfo')
  {
    open MEM, '/proc/meminfo';
    while(<MEM>)
    {
      chomp;

      my ($key, $val) = split /\s*:\s+/;
      if($key eq 'MemTotal')
      {
        my ($num, $units) = split /\s+/, $val;

        if($units =~ /^(kb|kilobytes)$/i)
        {
          $num = $num / 1048576;
          $units = 'GB';
        }
        elsif($units =~ /^(mb|megabytes)$/i)
        {
          $num = $num / 1024;
          $units = 'GB';
        }
 
        $num = sprintf("%.1f", $num);
         
        $info->{cpumem}->{mem} = "$num $units";
      }
    }
    close MEM;
  }

  #[root@filesrv9 root]# cat /proc/scsi/scsi
  #Attached devices:
  #Host: scsi0 Channel: 00 Id: 00 Lun: 00
  #  Vendor: LSILOGIC Model: 1030 IM       IM Rev: 1000
  #  Type:   Direct-Access                    ANSI SCSI revision: 02
  #Host: scsi0 Channel: 00 Id: 08 Lun: 00
  #  Vendor: IBM      Model: 25P3495a S320  1 Rev: 1
  #  Type:   Processor                        ANSI SCSI revision: 02

  my $scsi;
  if(-e '/proc/scsi/scsi')
  {
    my $name;

    open SCSI, '/proc/scsi/scsi';
    while(<SCSI>)
    {
      chomp;
      if(/Host:\s+(\w+)\s+Channel:\s+(\w+)\s+Id:\s+(\w+)\s+Lun:\s+(\w+)/)
      {
        $name = "$1 $2.$3.$4"; 
      }

      elsif(/Vendor:\s+(\w+)\s+Model:\s+(.+?)\s+Rev:\s+(\w+)/)
      {
        $scsi->{$name}->{vendor} = $1;
        $scsi->{$name}->{model} = $2;
        $scsi->{$name}->{rev} = $3;
      }

      elsif(/Type:\s+([\w\-]+)\s+ANSI/)
      {
        $scsi->{$name}->{type} = $1;
      }
    }
    close SCSI;
  }

  foreach my $device (sort keys %$scsi)
  {
    push @{$info->{scsi}}, { device => $device, %{$scsi->{$device}} };
  }

  my ($iface, $name);
  if (defined $bins->{ip})
  {
    my $int;
    foreach (`$bins->{ip} addr`)
    {
 
      #1: lo: <LOOPBACK,UP,LOWER_UP> mtu 16436 qdisc noqueue state UNKNOWN
      #    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
      #    inet 127.0.0.1/8 scope host lo
      #    inet 69.16.128.162/32 scope global lo
      #    inet6 ::1/128 scope host
      #       valid_lft forever preferred_lft forever
      #2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP qlen 1000
      #    link/ether 00:30:48:34:b2:fa brd ff:ff:ff:ff:ff:ff
      #    inet 69.16.128.171/27 scope global eth0
      #    inet 192.168.248.21/24 brd 192.168.248.255 scope global eth0
      #    inet 69.16.128.164/27 brd 69.16.128.191 scope global secondary eth0
      #    inet 69.16.128.183/27 brd 69.16.128.191 scope global secondary eth0
      #    inet6 fe80::230:48ff:fe34:b2fa/64 scope link
      #2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP qlen 100
      if (m/^(\d+):\s(lo|eth\d+|em\d+|bond\d+|tunl\d|tun\d|tap\d):\s(.*)$/ )
      {
        $name = $2;
        $iface->{$name}->{port} = $3;
        $int=0;
      }
      elsif (m/^(\d+):\s/)
      {
        undef $name;
      }
      #    link/ether 00:30:48:c6:70:b6 brd ff:ff:ff:ff:ff:ff
      elsif ( defined $name && m/\s+link\/ether ([\da-f:]+) /i )
      {
        $iface->{$name}->{mac} = lc($1);
      }
      #    inet 69.16.168.98/28 brd 69.16.168.111 scope global eth0
      elsif ( defined $name && m/\s+inet ([\d\.\/]+) .*scope global( | secondary )($name.*)$/ )
      {
        my ($ip,$cidr) = ipv4_parse( "$1" ) or dir $!;
        #$cidr = ipv4_cidr2msk($cidr);
        if ($3 eq $name && $int >= 1)
        {
          $iface->{"$name:$int"}->{ip} = $ip;
          $iface->{"$name:$int"}->{netmask} = ipv4_cidr2msk($cidr) || '';
          $int++;
        }
        else
        {
          $iface->{$3}->{ip} = $ip;
          $iface->{$3}->{netmask} = ipv4_cidr2msk($cidr) || '';
          $int++;
        }
      }
    }

  }
  elsif (defined $bins->{ifconfig})
  {
    foreach(`$bins->{ifconfig} -a`)
    {
      ###eth0      Link encap:Ethernet  HWaddr 00:09:6B:A3:C9:17  
      ###          inet addr:129.219.13.115  Bcast:129.219.13.127  Mask:255.255.255.192
  
      if(/^(lo|eth\d+|em\d+bond\d+|tunl0|tun0|tap0)\s+/)
      {
        $name = $1;
      }
      elsif (m/^\w+/)
      {
        undef $name;
      }
  
  
      if(defined $name && /HWaddr\s+([\w\:]{17})/)
      {
        $iface->{$name}->{mac} = $1;
      }
  
      if(defined $name && /inet addr:\s*([\d\.]+)/)
      {
        $iface->{$name}->{ip} = $1;
      }
  
      if(/defined $name && Mask:\s*([\d\.]+)/)
      {
        $iface->{$name}->{netmask} = $1;
      }
    }
  }

  if($bins->{ethtool})
  {
    foreach my $ifname (sort keys %$iface)
    {
      #[root@sporkdev SNAG]# ethtool eth1
      #Settings for eth1:
      #        Supported ports: [ MII ]
      #        Supported link modes:   10baseT/Half 10baseT/Full
      #                                100baseT/Half 100baseT/Full
      #                                1000baseT/Half 1000baseT/Full
      #        Supports auto-negotiation: Yes
      #        Advertised link modes:  Not reported
      #        Advertised auto-negotiation: No
      #        Speed: 100Mb/s
      #        Duplex: Unknown! (255)
      #        Port: Twisted Pair
      #        PHYAD: 1
      #        Transceiver: internal
      #        Auto-negotiation: off
      #        Supports Wake-on: g
      #        Wake-on: d
      #        Current message level: 0x000000ff (255)
      #        Link detected: yes
      
      foreach my $line (`$bins->{ethtool} $ifname 2>&1`)
      {
        next if $name =~ m/^lo/;

        if($line =~ /^\s+Speed:\s+(\d+|Unknown)/)
        {
          $iface->{$ifname}->{speed} = lc $1;
        }
      	elsif($line =~ /^\s+Duplex:\s+(\w+)/)
      	{
          $iface->{$ifname}->{duplex} = lc $1;
      	}
      	elsif($line =~ /^\s+Auto-negotiation:\s+(\w+)/)
      	{
      	  my $val = $1 eq "on" ? "yes" : "no"; 
          $iface->{$ifname}->{neg} = $val;
      	}
      	elsif($line =~ /^\s+Link detected:\s+(\w+)/)
      	{
      	  my $val = $1 eq "yes" ? "yes" : "no"; 
          $iface->{$ifname}->{neg} = $val;
      	}
      }
    }
  }

  foreach my $ifname (sort keys %$iface)
  {
    push @{$info->{iface}}, { iface => $ifname, %{$iface->{$ifname}} };
  }

  if(-e '/proc/mdstat')
  {
    open MDSTAT, '/proc/mdstat';
    my $dev;
    my $md;
    while(<MDSTAT>)
    {
      if (m/^md(\d+) \s+ : \s+ active \s+ (raid\d+)(.*)/x)                                                                                                                                                                                  
      {                                                                                                                                                                                                                                     
        $md = ();                                                                                                                                                                                                                           
        $dev = "md$1";                                                                                                                                                                                                                      
        ($md->{level}, $md->{members}) = ( $2, join(" ", sort( split(/ /, $3))) );                                                                                                                                                          
        my (%devs) = $md->{members} =~ m/\s+(\w+)\[(\d+)\]/g;                                                                                                                                                                               
        $info->{mdmap}->{$dev} = \%devs;                                                                                                                                                                                                    
        $md->{members} =~ s/^\s+//;                                                                                                                                                                                                         
      }                                                                                                                                                                                                                                     
      if (m/^md(\d+) \s+ : \s+ inactive \s+ (.*)/x)                                                                                                                                                                                         
      {                                                                                                                                                                                                                                     
        $md = ();                                                                                                                                                                                                                           
        $dev = "md$1";                                                                                                                                                                                                                      
        ($md->{members}) = ( $2, join(" ", sort( split(/ /, $2))) );                                                                                                                                                                        
        my (%devs) = $md->{members} =~ m/\s*(\w+)\[(\d+)\]/g;                                                                                                                                                                               
        $info->{mdmap}->{$dev} = \%devs;                                                                                                                                                                                                    
        $md->{members} =~ s/^\s+//;                                                                                                                                                                                                         
      }  
      if (m/\s+ (\d+) \s+ blocks \s/x)
      {
        $md->{blocks} = $1;
        $md->{chunk} = $1 if (m/\s+ (\d+k) \s+ chunk[,s]/ix);
        $md->{devices} = $1 if (m/\s+ \[\d+\/(\d+)\] \s+ \[/x);
      }
      if (m/^\s+$/)
      {
        push @{$info->{md}}, { md => $dev, %{$md} };
      }
    }
    close MDSTAT;
  }

  my $lspci_bin;
  if (-e '/usr/sbin/lspci')
  {
    $lspci_bin = '/usr/sbin/lspci';
  }
  else
  {
    $lspci_bin = BASE_DIR . '/sbin/lspci';
  }
  foreach my $line (sort `$lspci_bin`)
  {
    chomp $line;
    push @{$info->{pci}}, { description => $line };
  }

  return $info;
}

### Get the linux kernel parameters
sub kernel_settings
{
  my $args = shift;

  my $info;

  my $settings = [];
  my $max_length = _get_kernel_settings('/proc/sys', $settings);

  my $output;
  foreach my $ref (@$settings)
  {
    $info->{conf}->{kernel_settings}->{contents} .= sprintf('%-' . $max_length . 's ' . $ref->{val}, $ref->{key});
  }

  return $info;
}

sub vmware_host
{
  local $/ = "\n";

  my $args = shift;

  my ($info, $vmware_uuids);

  #'vmware_uuids_var'	=> { 'period' => 21600, condition => "-e '/var/lib/vm/guests/'" },
  #'vmware_uuids_proc'	=> { 'period' => 21600, condition => "-e '/proc/vmware/vm/'" },

  if(-e '/proc/vmware/vm/')
  {
    #[root@vmware3 vmware]# find /proc/vmware/vm/ -name 'names' -exec grep uuid {} \;
    #vmid=166    pid=4478   cfgFile="/root/vmware/linux/jbossdev.vmx"  uuid="N/A"  displayName="jbossdev"
    #vmid=165    pid=3535   cfgFile="/root/vmware/linux/jbossqa.vmx"  uuid="56 4d 73 b1 f1 a9 c2 ef-89 7a 2d 83 29 23 a9 b9"  displayName="jbossqa"

    find
    (
      sub
      {
        if($_ eq 'names')
        {
  	  open IN, $File::Find::name;
  	  my $line;
  	  while(<IN>)
  	  {
  	    if(/uuid/)
  	    {
              my ($cfg_file) = /cfgFile=\"([^\"]+)\"/;

	      open CFG, $cfg_file;

	      my %config;
	      while(<CFG>)
	      {
	        chomp;
	        my ($key, $val) = split /\s*=\s*/;
	        $val =~ s/\"//g;

	        $config{$key} = $val;
	      }

              push @$vmware_uuids, { display_name => $config{displayName}, uuid => 'VMware-' . $config{'uuid.bios'}};
	    }
	  }
        }
      },
      '/proc/vmware/vm/'
    );
  }
  elsif(-e '/var/lib/vm/guests/')
  {
    find
    (
      sub
      {
        if($_ =~ /\.vmx$/)
        {
          my %config;

	  open IN, $File::Find::name;
	  while(<IN>)
	  {
	    chomp;
	    my ($key, $val) = split /\s*=\s*/;
	    $val =~ s/\"//g;

	    $config{$key} = $val;
	  }

          push @$vmware_uuids, { display_name => $config{displayName}, uuid => 'VMware-' . $config{'uuid.bios'}};
        }
      },
      '/var/lib/vm/guests'
    );
  }

  $info->{vmware_uuids} = $vmware_uuids;

  return $info;
}

sub mounts
{
  local $/ = "\n";

  my $mounts;

  my $seen = time2str("%Y-%m-%d %T", time);

  open IN, '/etc/fstab';
  while(<IN>)
  {
    next if /^\s*#/;
    next if /^none/;
    next if /^\s*$/;

    my ($dev, $mount, $type, $options) = split /\s+/;

    $mounts->{$mount} = { dev => $dev, type => $type, fstab_options => $options, in_fstab => 1 };

    if($dev =~ /^([^:]+):(.+)$/ && $type eq 'nfs')
    {
      my $ip  = nslookup(host => $1, type => 'A');

      $mounts->{$mount}->{nfs_addr} = $ip;
    }
  }
  close IN;

  foreach (`/bin/mount -lv`)
  {
    next if /^none/;
    next if /^\s*$/;
    next if /^rootfs/; # ignore / mounts reporting themselves as type rootfs

    if(/^(\S+) on (\S+) type (\S+) \((\S+)\)( \[(\S*)\])?$/)
    {
      my ($dev, $mount, $type, $options, $label) = ($1, $2, $3, $4, $6);

      if($mounts->{$mount})
      {
        unless($mounts->{$mount}->{type} eq $type)
        {
          print STDERR join REC_SEP, ('events', HOST_NAME, 'sysinfo', 'mount', 'Type conflict between mounted device and fstab', "For device $dev mounted on $mount: mount type is $type, fstab type is $mounts->{$mount}->{type}", '', $seen);
          print STDERR "\n";
        }

        if($mounts->{$mount}->{dev} eq 'LABEL=' . $label)
        {
          $mounts->{$mount}->{dev} = $dev;
        }

        #unless($mounts->{$mount}->{dev} eq $dev)
        #{
        #  print STDERR join REC_SEP, ('events', HOST_NAME, 'sysinfo', 'mount', 'Device conflict between mounted device and fstab', "For device mounted on $mount: mount dev is $dev, fstab dev is $mounts->{$mount}->{dev}", '', $seen);
        #  print STDERR "\n";
        #}

        $mounts->{$mount}->{in_mount} = 1;
        $mounts->{$mount}->{mount_options} = $options;
      }
      else
      {
        $mounts->{$mount} = { dev => $dev, type => $type, mount_options => $options, in_fstab => 0, in_mount => 1 };

        if($mounts->{$mount}->{type} =~ /^ext\d+$/ || $mounts->{$mount}->{type} eq 'nfs' || $mounts->{$mount}->{type} eq 'xfs')
        {
          next if $mount eq '/boot';
          print STDERR join REC_SEP, ('events', HOST_NAME, 'sysinfo', 'mount', 'Mounted device not defined in fstab', "Device: $dev, Mount: $mount, Type: $type, Options: $options", '', $seen);
          print STDERR "\n";
        }
      }

      if($type eq 'nfs' and $options =~ /addr=([\d\.]+)/)
      {
        $mounts->{$mount}->{nfs_addr} = $1;
      }

    }
  }

  foreach my $mount (keys %$mounts)
  {
    unless(defined $mounts->{$mount}->{in_mount})
    {
      $mounts->{$mount}->{in_mount} = 0;

      if($mounts->{$mount}->{type} =~ /^ext\d+$/ || $mounts->{$mount}->{type} eq 'nfs' || $mounts->{$mount}->{type} eq 'xfs')
      {
        next if $mount eq '/boot';
        print STDERR join REC_SEP, ('events', HOST_NAME, 'sysinfo', 'mount', 'Device defined in fstab is not mounted', "Device: $mounts->{$mount}->{dev}, Mount: $mount, Type: $mounts->{$mount}->{type}, Options: $mounts->{$mount}->{fstab_options}", '', $seen);
        print STDERR "\n";
      }
    }
  }

  my $info;

  foreach my $mount (keys %$mounts)
  {
    push @{$info->{mounts}}, { %{$mounts->{$mount}}, mount => $mount };
  }

  return $info;
}

sub iscsi
{
  local $/ = "\n";

  my $seen = time2str("%Y-%m-%d %T", time);

  my $iscsi_ls_bin = '/sbin/iscsi-ls';
  my $iscsi_initiator = '/etc/initiatorname.iscsi';

  unless(-e $iscsi_ls_bin)
  {
    print STDERR join REC_SEP, ('events', HOST_NAME, 'sysinfo', 'iscsi_issue', "Couldn't find $iscsi_ls_bin", '', $seen);
    print STDERR "\n";

    return;
  }

  unless(-e $iscsi_initiator)
  {
    print STDERR join REC_SEP, ('events', HOST_NAME, 'sysinfo', 'iscsi_issue', "Couldn't find $iscsi_initiator", '', $seen);
    print STDERR "\n";

    return;
  }

  my $info;

  ### Get initiator name
  {
    open IN, $iscsi_initiator;
    while(<IN>)
    {
      next if /^\#/;
      if(/^InitiatorName=(\S+)/)
      {
        my ($iname, $name) = split /:/, $1;

        $info->{iscsi}->{iname} = $iname;
        $info->{iscsi}->{name} = $name;
      }
    }
  }

  my ($lun, $status);
  foreach my $line (`$iscsi_ls_bin -l 2>/dev/null`)
  {
    ##DEVICE DETAILS:
    ##---------------
    ##LUN ID : 0
    ##  Vendor: NETAPP   Model: LUN              Rev: 0.2
    ##  Type:   Direct-Access                    ANSI SCSI revision: 04
    ##  page83 type3: 60a98000486e5374584a43684272506e
    ##  page80: 486e5374584a43684272506e0a
    ##  Device: /dev/sdb
    ##*******************************************************************************
    if($line =~ /^LUN ID : (\d+)/)
    {
      $lun = $1;
      push @{$info->{iscsi_lun}}, {'id' => $1};
    }
    elsif($line =~ /\s+page83 type3: (\S+)/)
    {
      ${$info->{iscsi_lun}->[ $#{$info->{iscsi_lun}} ]}{page83_type3} =  $1;
    }
    elsif($line =~ /\s+page80: (\S+)0a$/)
    {
      ${$info->{iscsi_lun}->[ $#{$info->{iscsi_lun}} ]}{page80} =  $1;
    }
    elsif($line =~ /\s+Device: (\S+)/)
    {
      ${$info->{iscsi_lun}->[ $#{$info->{iscsi_lun}} ]}{device} =  $1;
    }
    elsif($line =~ /\s+Vendor:\s+(\S+)\s+ Model:\s+(\S+)/)
    {
      ${$info->{iscsi_lun}->[ $#{$info->{iscsi_lun}} ]}{vendor} =  $1;
      ${$info->{iscsi_lun}->[ $#{$info->{iscsi_lun}} ]}{model} =  $2;
    }
    ##*******************************************************************************
    ##SFNet iSCSI Driver Version ...4:0.1.11-6(03-Aug-2007)
    ##*******************************************************************************
    ##TARGET NAME             : iqn.1992-08.com.netapp:sn.50404989
    ##TARGET ALIAS            :
    ##HOST ID                 : 1               | HOST NO                 : 4
    ##BUS ID                  : 0               | BUS NO                  : 0
    ##TARGET ID               : 0
    ##TARGET ADDRESS          : 10.106.140.253:3260,2000
    ##SESSION STATUS          : ESTABLISHED AT Thu May 15 03:30:49 MST 2008
    ##SESSION ID              : ISID 00023d000001 TSIH 38b
    ##
    elsif($line =~ /SFNet iSCSI Driver Version [\. ]{0,4}(\S+)/)
    {
      $info->{iscsi}->{driver_version} = $1;
    }
    elsif($line =~ /^TARGET NAME\s+:\s+(\S+)/)
    {
      my ($target_iname, $target_name) = split /:/, $1;

      $info->{iscsi}->{target_iname} = $target_iname;
      $info->{iscsi}->{target_name} = $target_name;
    }
    elsif($line =~ /^HOST (ID|NO)\s+:\s+(\S+)/)
    {
      $info->{iscsi}->{host_id} = $2;
    }
    elsif($line =~ /^BUS (ID|NO)\s+:\s+(\S+)/)
    {
      $info->{iscsi}->{bus_id} = $2;
    }
    elsif($line =~ /^TARGET ID\s+:\s+(\S+)/)
    {
      $info->{iscsi}->{target_id} = $1;
    }
    elsif($line =~ /^TARGET ADDRESS\s+:\s+(\S+)/)
    {
      my ($address, $ports) = split /:/, $1;
      $info->{iscsi}->{target_address} = $address;
      $info->{iscsi}->{target_ports} = $ports;
    }
    elsif($line =~ /^SESSION STATUS\s+:\s+(\S+)/)
    {
      $info->{iscsi}->{session_status} = $status = $1;

      unless($status eq 'ESTABLISHED')
      {
        chomp $line;
        print STDERR join REC_SEP, ('events', HOST_NAME, 'sysinfo', 'iscsi_status', 'iscsi client connection down', $line, '', $seen);
        print STDERR "\n";
      }
    }
    elsif($line =~ /^SESSION ID\s+:\s+(.*)/)
    {
      $info->{iscsi}->{session_id} = $1;
    }
  }

  if($status)
  {
    return $info;
  }
  else
  {
    print STDERR join REC_SEP, ('events', HOST_NAME, 'sysinfo', 'iscsi_status', 'iscsi client connection down', 'iscsi client appears to be turned off', '', $seen);
    print STDERR "\n";
 
    return;
  }
}

######################################################################################
####################### HELPER SUBS ##################################################
######################################################################################

sub _get_kernel_settings
{
  my ($path, $settings) = @_;
  my $max_length;

  if(-f $path)
  {
    open IN, $path or die "Cannot open $path";

    (my $key = $path) =~ s#^/proc/sys/##;
    $key =~ s/\//\./g;

    while(<IN>)
    {
      chomp;
      push @$settings, { key => $key, val => $_ };

      my $length = length $key;
      $max_length = $length unless $max_length > $length;
    }
  }
  elsif(-d $path)
  {
    opendir PATH, $path or die "Cannot opendir $path: $!";

    for my $name (readdir PATH)
    {
      next if $name eq "." or $name eq "..";
      my $length = _get_kernel_settings("$path/$name", $settings);
      $max_length = $length unless $max_length > $length;
    }

    closedir PATH;
  }
  else
  {
    warn "$path is neither a file nor a directory\n";
  }

  return $max_length;
}
1;
