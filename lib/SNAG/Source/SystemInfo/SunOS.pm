package SNAG::Source::SystemInfo::SunOS;
use base 'Exporter';

use strict;
use SNAG;
use DBM::Deep;
use File::Spec::Functions qw/catfile/;
use Proc::ProcessTable;
use Storable qw/store retrieve/;
use Date::Format;
use Digest::SHA qw(sha256_hex);
use Digest::MD5 qw(md5_hex);
use Net::Nslookup;

our @EXPORT = qw/config_files_check startup arp system config_files_whole installed_software getconf static_routes service_monitor mounts/; 
our %EXPORT_TAGS = ( 'all' => \@EXPORT ); 

our $config =
{
  'listening_ports'     => { 'period' => 300, data => $SNAG::Dispatch::shared_data },
  'tags'                => { 'period' => 300, data => $SNAG::Dispatch::shared_data },
  'service_monitor'     => { 'period' => 300 },

  'config_files_check' 	=> { 'period' => 600 },
  'mounts'              => { 'period' => 600 },

  'startup'             => { 'period' => 3600 },

  'arp'                 => { 'period' => 7200 },

  'system' 		=> { 'period' => 21600 },
  'config_files_whole' 	=> { 'period' => 21600 },
  'apache_version'      => { 'period' => 21600, if_tag => 'service.web.apache' },

  installed_software    => { 'period' => 43200 },
  getconf		=> { 'period' => 43200 },

  'static_routes'       => { 'period' => 21600 },
};

#our @EXPORT = keys %$config;
#our %EXPORT_TAGS = ( 'all' => \@EXPORT );

######## Default files to track
my %default_config_files = 
(
  '/etc/group' => 1,
  '/etc/hosts' => 1,
  '/etc/krb5.conf' => 1,
  '/etc/krb.conf' => 1,
  '/etc/pam.d/su' => 1,
  '/etc/ssh/sshd_config' => 1,
  '/etc/motd' => 1,
  '/etc/inittab' => 1,
  '/etc/pam.d/system-auth' => 1,
  '/etc/profile' => 1,
  '/etc/resolv.conf' => 1,
  '/etc/services' => 1,
  '/etc/sysctl.conf' => 1,
  '/etc/syslog.conf' => 1,
  '/etc/system' => 1,
  '/etc/passwd' => 1,
  '/etc/shadow' => 1,
  '/usr/vice/etc/cacheinfo' => 1,
  '/etc/init.d/afs.rc' => 1,
  '/etc/sudoers' => 1,
  '/proc/vmware/version' => 1,
  '/etc/sysconfig/network' => 1,
  '/platform/sun4u/boot.conf' => 1,
  '/etc/nsswitch.conf' => 1,
  '/etc/defaultrouter' => 1,
  '/etc/vfstab' => 1,
  '/etc/netmasks' => 1,
  '/etc/inet/ipnodes' => 1,
  '/etc/.login' => 1,
  '/etc/auto_master' => 1,
  '/etc/shells' => 1,
  '/etc/inetd.conf' => 1,
  '/kernel/drv/sd.conf' => 1,
  '/etc/ssh2/sshd2_config' => 1,
  '/etc/mail/sendmail.cf' => 1,
);

$default_config_files{LOG_DIR . '/snag.uuid'} = 1;

#### Add some more files at runtime
sub build_config_file_list
{
  my %config_files = map { $_ => 1 } grep { -e $_ } keys %default_config_files;

  my $host = HOST_NAME;

  if( $host =~ /^general\d$/
      || $host =~ /^research\d$/
      || $host =~ /^medusa\d$/
    )
  {
    ### ignore auth files on interactive machines, too noisy
    delete $config_files{'/etc/passwd'};
    delete $config_files{'/etc/group'};
    delete $config_files{'/etc/shadow'};
  }
  
  my $cron_dir = '/var/spool/cron/crontabs/';

  opendir(my $crons_dir, $cron_dir);
  foreach my $name (grep { $_ ne '.' && $_ ne '..' } readdir $crons_dir)
  {
    next if $name eq 'core';

    my $file = $cron_dir . $name;
    $config_files{$cron_dir . $name} = 1;
  }
  closedir $crons_dir;

  return \%config_files;
}

sub config_files_whole
{
  my $args = shift;

  my $info;

  #Add any new files that might have popped up
  my $config_files = build_config_file_list();

  my $state_files = new DBM::Deep
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
      if($file eq '/etc/shadow')
      {
        local $/ = "\n";

        my $contents;

        open my $shadow, '<', "/etc/shadow";
        while (<$shadow>)
        {
          s/^([\w\_\.]+)\:([\w\/\\\.\$]{9,})\:/"$1:" . sha256_hex(md5_hex($2))/e;
          $contents .= $_;
        }
        close $shadow;

        $info->{conf}->{$file} = { contents => $contents };
      }
      else
      {
        $info->{conf}->{$file} = { contents => `/bin/cat $file` || '' };
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

  my $state_files = new DBM::Deep
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
        if($file eq '/etc/shadow')
        {
          local $/ = "\n";

          my $contents;

          open my $shadow, '<', "/etc/shadow";
          while (<$shadow>)
          {
            s/^([\w\_\.]+)\:([\w\/\\\.\$]{3,})\:/"$1:" . sha256_hex(md5_hex($2))/e;
            $contents .= $_;
          }
          close $shadow;

          $info->{conf}->{$file} = { contents => $contents };
        }
        else
        {
          $info->{conf}->{$file} = { contents => `/bin/cat $file` || '' };
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

sub static_routes
{
  #IRE Table: IPv4
  #  Destination             Mask           Gateway          Device Mxfrg  Rtt  Ref Flg  Out  In/Fwd
  #-------------------- --------------- -------------------- ------ ----- ----- --- --- ----- ------
  #129.219.10.64        255.255.255.192 129.219.10.70        dmfe0   1500*    0   1 U   110113     0
  #224.0.0.0            240.0.0.0       129.219.10.70        dmfe0   1500*    0   1 U        0     0
  #default              0.0.0.0         129.219.10.65                1500*    0   1 UG  11586295     0
  #127.0.0.1            255.255.255.255 127.0.0.1            lo0     8232*    0   1 UH    3364     0

  local $/ = "\n";

  my @lines = `netstat -rnv`;

  my $contents;

  while(my $first = shift @lines)
  {
    $contents .= $first;
    last if $first =~ /IRE Table/;
  }

  my $headers = shift @lines;
  $headers =~ /^(\s+\w+\s+\w+\s+\w+\s+\w+)/;
  $contents .= "$1\n";

  foreach my $line (@lines)
  {
    chomp $line;

    #$line =~ /^([\d\.]+\s+[\d\.]+\s+\[\d\.]+\s+\w+)/;
    if($line =~ /^(\S+\s+\S+\s+\S+\s+\S+)/)
    {
      my $stuff = $1;
      if($stuff =~ /^default/)
      {
        $stuff =~ s/\S+$//;
      }

      $contents .= "$stuff\n";
    }
  }

  my $info;
  $info->{conf}->{static_routes} = { contents => $contents };

  return $info;
}

sub installed_software
{
  my $info;

  $info->{conf}->{installed_software} = { contents => `/usr/bin/pkginfo -x` };

  return $info;
}

sub getconf
{
  my $args = shift;

  my $info;

  $info->{conf}->{getconf} = { contents => `/usr/bin/getconf -a | /usr/bin/sort` };

  return $info;
}

sub arp
{
  local $/ = "\n";

  my $info;

  my $start;
  foreach my $line (`/usr/sbin/arp -a`)
  {
    if($line =~ /^\-\-\-/)
    {
      $start++;
      next;
    }
    next unless $start;
    my ($host, $mac) = (split /\s+/, $line)[1, -1];

    push @{$info->{arp}}, { remote => $host, mac => $mac };
  }

  return $info;
}


### Find ethtool on this box, it varies
my $ethtool_bin;
my @ethtool_paths = ('/sbin/ethtool', '/usr/sbin/ethtool');
foreach (@ethtool_paths)
{
  if(-e $_)
  {
    $ethtool_bin = $_;
    last;
  }
}

unless($ethtool_bin)
{
  #$poe_kernel->call('logger' => 'alert' => { Subject => 'SNAG::Source::SystemInfo, ' . HOST_NAME . ', Could not find ethtool on this box!' } );
}

sub startup
{
  my ($contents, %valid_runlevels, $stuff, $max_length);

  opendir(my $init_dir, '/etc/init.d') or die $!;
  my @inits = readdir $init_dir;
  closedir $init_dir;

  foreach my $init (@inits)
  {
    next if $init eq '..' || $init eq '.';
    $max_length = length $init unless $max_length > length $init;
    $stuff->{$init} = undef;
  }

  foreach my $i ((0 .. 6), 'S')
  {
    my $dir = "/etc/rc$i.d/";
    next unless -e $dir;

    $valid_runlevels{$i} = 1;

    opendir(my $scripts_dir, $dir) or die $!;
    my @scripts = readdir $scripts_dir;
    closedir $scripts_dir;

    foreach my $script (@scripts)
    {
      if($script =~ /^S\d\d(.+)$/)
      {
        my $name = $1;
        $max_length = length $name unless $max_length > length $name;
        $stuff->{$name}->{$i} = 1;
      }
    }
  }

  foreach my $script (sort keys %$stuff)
  {
    $contents .= sprintf('%-' . $max_length . "s\t", $script);

    foreach my $rl (sort keys %valid_runlevels)
    {
      if($stuff->{$script}->{$rl})
      {
        $contents .= "$rl:on\t";
      }
      else
      {
        $contents .= "$rl:off\t";
      }
    }

    $contents .= "\n";
  }

  my $info;
  $info->{conf}->{startup} = { contents => $contents };
  return $info;
}

sub system
{
  my $args;

  local $/ = "\n";

  my $info;

  #$info->{host} = HOST_NAME;
  $info->{entity}->{type} = 'system';

  $info->{SNAG}->{version} = VERSION;
  $info->{SNAG}->{perl} = `$^X -V`;

  $info->{os}->{os} = OS;
  $info->{os}->{os_version} = OSLONG;

  chomp(my $arch = `/bin/uname -m`);
  $info->{os}->{os_arch} = $arch;

  ## psrinfo -v
  #Status of processor 0 as of: 09/24/05 12:00:16
  #  Processor has been on-line since 06/18/05 00:44:01.
  #  The sparcv9 processor operates at 1015 MHz,
  #        and has a sparcv9 floating point processor.
  my $cpu_count;
  foreach (`/usr/sbin/psrinfo -v`)
  {
    chomp;

    if(/The (\w+) processor operates at (.+),/)
    {
      my ($model, $speed) = ($1, $2);

      if($info->{cpumem}->{cpu} && $info->{cpumem}->{cpu} ne $model)
      {
        print STDERR "More than one cpu type on this host" ;
      }

      $cpu_count++;

      $info->{cpumem}->{cpu} = $model;
      $info->{cpumem}->{cpu_speed} = $speed;
    }
  }

  $info->{cpumem}->{cpu_count} = $cpu_count;

  foreach (`uname -X`)
  {
    chomp;

    if(/Serial\s+=\s+(.+)$/)
    {
      my $serial = $1;
      unless($serial =~ /unknown/)
      {
        $info->{device}->{serial} = $serial;
      }
    }
    elsif(/KernelID\s+=\s+(.+)$/)
    {
      $info->{os}->{os_kernel} = $1;
    }
  }

  ## /sbin/ifconfig -a
  #lo0: flags=849<UP,LOOPBACK,RUNNING,MULTICAST> mtu 8232
  #        inet 127.0.0.1 netmask ff000000
  #hme0: flags=863<UP,BROADCAST,NOTRAILERS,RUNNING,MULTICAST> mtu 1500
  #        inet 129.219.107.194 netmask ffffffe0 broadcast 129.219.107.223
  #        ether 8:0:20:d0:e7:8d

  ## ifconfig -a
  #lo0: flags=1000849<UP,LOOPBACK,RUNNING,MULTICAST,IPv4> mtu 8232 index 1
  #        inet 127.0.0.1 netmask ff000000
  #dmfe0: flags=1000843<UP,BROADCAST,RUNNING,MULTICAST,IPv4> mtu 1500 index 2
  #        inet 129.219.117.245 netmask ffffffc0 broadcast 129.219.117.255
  #        ether 0:3:ba:13:af:fd
  #dmfe0:1: flags=1000843<UP,BROADCAST,RUNNING,MULTICAST,IPv4> mtu 1500 index 2
  #        inet 129.219.117.253 netmask ffffffc0 broadcast 129.219.117.255

  my ($iface, $name, $device, $instance);
  foreach (`/sbin/ifconfig -a`)
  {
    if(/^(\S+):\s+/)
    {
      $name = $1;
    }

    next if $name =~ /^lo/;

    if(/inet\s+([\d\.]+)/)
    {
      $iface->{$name}->{ip} = $1;
    }

    if(/ether\s+([\w\:]+)/)
    {
      my $mac = $1;
      $mac =~ s/\b(\w)\b/0$1/g;
      $iface->{$name}->{mac} = $mac;
    }

    if(/netmask\s+([0-9a-f]+)/)
    {
      my $packed = sprintf('%08s', $1);
      my $netmask = join '.', unpack 'C4', pack 'H*', $packed;
      $iface->{$name}->{netmask} = $netmask;
    }
  }

  foreach my $name (sort keys %$iface)
  {
    if($name =~ /^(dmfe|eri|hme|qfe|ge|ce|bge)(\d+)/)
    {
      $device   = $1;
      $instance = $2;
    }
    else
    {
      #print STDERR "Unsupported iface driver for ndd stats ($name)\n";
      next;
    }


    if($device =~ /(dmfe|bge)/)
    {
      $device .= $instance;
    }

    `/usr/sbin/ndd -set /dev/$device instance $instance`;

    my $link_status;
    chomp($link_status = `/usr/sbin/ndd /dev/$device link_status`);
    if(!$link_status || $link_status =~ /failed/)
    {
      next;  ## EITHER LINK IS DOWN, OR NDD ISN'T INSTALLED
    }

    my $link_speed;
    chomp($link_speed = `/usr/sbin/ndd /dev/$device link_speed`);
    chomp(($link_speed) = split (/\n/, $link_speed));
    unless ($device =~ /bge|dmfe/)
    {
      $link_speed = 100 if $link_speed eq 1;
      $link_speed = 10 if $link_speed eq 0;
    }
    $iface->{$name}->{speed} = $link_speed;

    my $link_mode;
    if ($device =~ /bge/i)
    {
      chomp($link_mode = `/usr/sbin/ndd /dev/$device link_duplex`);
    }
    else
    {
      chomp($link_mode = `/usr/sbin/ndd /dev/$device link_mode`);
    }
    $iface->{$name}->{duplex} = $link_mode ? "full" : "half";

    my $link_neg;
    if ($device eq "ge")
    {
      chomp($link_neg = `/usr/sbin/ndd /dev/$device adv_1000autoneg_cap`);
    }
    else
    {
      chomp($link_neg = `/usr/sbin/ndd /dev/$device adv_autoneg_cap`);
    }
    $iface->{$name}->{neg} = $link_neg ? "yes" : "no";
  }

  foreach my $ifname (sort keys %$iface)
  {
    push @{$info->{iface}}, { iface => $ifname, %{$iface->{$ifname}} };
  }

  my $platform = `uname -i`;
  chomp $platform;
  $info->{device}->{model} = $platform;
  #========================= IO Cards =========================
  #
  #     Bus   Freq
  #Brd  Type  MHz   Slot        Name                              Model
  #---  ----  ----  ----------  --------------------------------  ----------------------
  # 0   PCI    33     On-Board  network-SUNW,hme
  # 0   PCI    33     On-Board  scsi-glm/disk (block)             Symbios,53C875

  #========================= HW Revisions =======================================
  #
  #System PROM revisions:
  #----------------------
  #OBP 4.5.21 2003/02/24 17:23

  my ($iocards, $iocard_id, $section, $subsection, $field_count, $contents);
  foreach (`/usr/platform/$platform/sbin/prtdiag -v`)
  {
    $contents .= $_;

    chomp;
    next if /^\s+$/;

    s/\s+$//;
    s/^\s+//;

    #System Configuration:  Sun Microsystems  sun4u Sun Fire V100 (UltraSPARC-IIe 500MHz)/)
    #System Configuration: Sun Microsystems     Sun Fire X4540
    if(/System Configuration:\s+(\w+\s+\w+)\s+\w+\s+(.+)$/)
    {
      $info->{device}->{vendor} = $1;

      my $model = $2;
      $model =~ s/\s*\(.+?\)//g;
      $info->{device}->{model} = $model;
    }

    if(/Memory\s+size:\s+(\d+)\s?(\w+)/)
    {
      my ($num, $units) = ($1, $2);

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

    if(/===\s+([\w\s]+)\s+===/)
    {
      $section = $1;
    }

    if(/^([\w\s]+):\s*$/)
    {
      $subsection = $1;
    }

    if($section eq 'IO Cards' || $section eq 'IO Devices')
    {
      if(/^\-\-/)
      {
        s/^\s+//g;
        s/\s+$//g;

        $field_count = scalar(split /\s+/, $_);
        $subsection = 'cards';
        next;
      }

      if($subsection eq 'cards')
      {
        my @fields = split /\s+/, $_;
        next unless scalar @fields >= $field_count;

        push @{$info->{pci}}, { description => $_ };
      }
    }

    if($section eq 'HW Revisions' && $subsection eq 'System PROM revisions')
    {
      my @data = split /\s+/, $_;

      if(scalar @data >= 4)
      {
        $info->{bios}->{bios_vendor} = 'Sun Microsystems';

        if($info->{bios}->{bios_version})
        {
          $info->{bios}->{bios_version} .= ", $data[0] $data[1]";
        }
        else
        {
          $info->{bios}->{bios_version} = "$data[0] $data[1]";
        }

        if($info->{bios}->{bios_date})
        {
          $info->{bios}->{bios_date} .= ", $data[2] $data[3]";
        }
        else
        {
          $info->{bios}->{bios_date} = "$data[2] $data[3]";
        }
      }
    }
  }

  unless( $info->{cpumem}->{mem} )
  {
    foreach (`/usr/sbin/prtconf`)
    {
      if(/Memory\s+size:\s+(\d+)\s?(\w+)/)
      {
	my ($num, $units) = ($1, $2);

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
  }

  #$info->{conf}->{prtdiag} = { contents => $contents }; ### Too noisy, refine and maybe use later


  # /usr/bin/iostat -En
  #c1t3d0          Soft Errors: 0 Hard Errors: 0 Transport Errors: 0
  #Vendor: SEAGATE  Product: ST318404LSUN18G  Revision: 4203 Serial No: 3BT25CF500007127
  # -or-
  #Model: ST340016A        Revision: 3.10     Serial No: 3HS48WDH
  #Size: 18.11GB <18110967808 bytes>
  #Media Error: 0 Device Not Ready: 0 No Device: 0 Recoverable: 0
  #Illegal Request: 0 Predictive Failure Analysis: 0

  #sd65            Soft Errors: 0 Hard Errors: 21 Transport Errors: 0
  #Vendor: STK      Product: OPENstorage D240 Revision: 0612 Serial No: 1T42157847
  #Size: 23.62GB <23620222976 bytes>
  #Media Error: 0 Device Not Ready: 0 No Device: 21 Recoverable: 0
  #Illegal Request: 0 Predictive Failure Analysis: 0

  my ($disk, $ddevice, $type);
  foreach (`/usr/bin/iostat -En`)
  {
    if(/(\w+)\s+Soft\s+Errors/)
    {
      $ddevice = $1;
      if($ddevice =~ /^s/)
      {
        $type = 'scsi';
      }
      else
      {
        $type = 'disk';
      }
    }

    if(/Vendor:\s+(.+?)\s+Product:\s+(.+?)\s+Revision:\s+(.+?)\s+Serial\s+No:\s+(.+)$/)
    {

      $disk->{$type}->{$ddevice}->{vendor} = $1;
      $disk->{$type}->{$ddevice}->{model} = $2;
      $disk->{$type}->{$ddevice}->{rev} = $3;

      my $serial = $4;
      $serial = $serial =~ /^[\w\-\s\/\\]+$/ ? $serial : '';
      $disk->{$type}->{$ddevice}->{serial} = $serial;
    }


    if(/Model:\s+(.+?)\s+Revision:\s+(.+?)\s+Serial No: (.+)$/)
    {
      $disk->{$type}->{$ddevice}->{model} = $1;
      $disk->{$type}->{$ddevice}->{rev} = $2;

      my $serial = $3;
      $serial = $serial =~ /^[\w\-\s\/\\]+$/ ? $serial : '';
      $disk->{$type}->{$ddevice}->{serial} = $serial;
    }

    if(/Size:\s+([\w\.]+)/)
    {
      $disk->{$type}->{$ddevice}->{size} = $1;
    }
  }

  foreach my $scsiname ( sort keys %{$disk->{scsi}} )
  {
    push @{$info->{scsi}}, { device => $scsiname, %{$disk->{scsi}->{$scsiname}} };
  }

  foreach my $diskname ( sort keys %{$disk->{disk}} )
  {
    push @{$info->{disk}}, { device => $diskname, %{$disk->{disk}->{$diskname}} };
  }

  return $info;
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
  while( my ($pid, $ref) = each %$process_list)
  {
    ### Ignore any process owned by SNAGc.pl
    if($process_list->{ $ref->{ppid} }->{fname} =~ m/SNAGc\.pl/)
    {
      #print "Skipping $ref->{fname} because owned by SNAGc.pl\n";
      next;
    }

    next if $ref->{state} eq 'defunct';
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
  }

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

    my $new_ratio
      = ( ( $old_ratio * $samples ) + $running_flag ) / ( $samples + 1 );

    ### keep only a window of the last week
    $samples = $samples >= 10080 ? 10080 : ($samples + 1);
    $service_monitor->{$proc}->{samples} = $samples;
  }

  store($service_monitor, $state_file) or die "Could not store $state_file";

  return {};
}

sub mounts
{
  local $/ = "\n";

  my $mounts;

  my $seen = time2str("%Y-%m-%d %T", time);

  open my $in, '<', '/etc/vfstab';
  while(<$in>)
  {
    next if /^\s*#/;
    next if /^\s*$/;

    my ($dev, $fsck_dev, $mount, $type, $fsck_pass, $fsck_boot, $options) = split /\s+/;

    next if $mount eq '-';

    $mounts->{$mount} = { dev => $dev, type => $type, fstab_options => $options, in_fstab => 1 };

    if($dev =~ /^([^:]+):(.+)$/ && $type eq 'nfs')
    {
      my $ip  = nslookup(host => $1, type => 'A');

      $mounts->{$mount}->{nfs_addr} = $ip;
    }
  }
  close $in;

  foreach (`/sbin/mount -v`)
  {
    next if /^\s*$/;

    if(/^(\S+) on (\S+) type (\S+) (\S+)/)
    {
      my ($dev, $mount, $type, $options) = ($1, $2, $3, $4);

      if($mounts->{$mount})
      {
        unless($mounts->{$mount}->{type} eq $type)
        {
          print STDERR join REC_SEP, ('events', HOST_NAME, 'sysinfo', 'mount', 'Type conflict between mounted device and fstab', "For device $dev mounted on $mount: mount type is $type, fstab type is $mounts->{$mount}->{type}", '', $seen);
          print STDERR "\n";
        }

        $mounts->{$mount}->{in_mount} = 1;
        $mounts->{$mount}->{mount_options} = $options;

      }
      else
      {
        $mounts->{$mount} = { dev => $dev, type => $type, mount_options => $options, in_fstab => 0, in_mount => 1 };

        if($dev =~ /^([^:]+):(.+)$/ && $type eq 'nfs')
        {
          my $ip  = nslookup(host => $1, type => 'A');

          $mounts->{$mount}->{nfs_addr} = $ip;
        }

        if($mounts->{$mount}->{type} =~ /^ext\d+$/ || $mounts->{$mount}->{type} eq 'nfs')
        {
          print STDERR join REC_SEP, ('events', HOST_NAME, 'sysinfo', 'mount', 'Mounted device not defined in fstab', "Device: $dev, Mount: $mount, Type: $type, Options: $options", '', $seen);
          print STDERR "\n";
        }
      }
    }
  }

  foreach my $mount (keys %$mounts)
  {
    unless(defined $mounts->{$mount}->{in_mount})
    {
      $mounts->{$mount}->{in_mount} = 0;

      if($mounts->{$mount}->{type} =~ /^ext\d+$/ || $mounts->{$mount}->{type} eq 'nfs')
      {
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

1;
