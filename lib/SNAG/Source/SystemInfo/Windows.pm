package SNAG::Source::SystemInfo::Windows;
use base 'Exporter';

      ### Alert on !Running state and !OK status of the following services (by 'DisplayName')
      #MSSQLSERVER 
      #SQLSERVERAGENT ?
      #TSM-Acceptor
      #IIS Admin Service
      #NetApp ?
      #DNS Client ?

      ## Maybe baseline the Running/Stopped ratio of all services, and alert if it goes down when the ratio is over a certain threshhold?

### Any of these?
#Own Process OK "M:\Program Files\Citrix\Server Resource Management\CPU Utilization Management\bin\ctxcpubal.exe" Stopped Citrix CPU Utilization Mgmt/CPU Rebalancer - LocalSystem Manual Own Process OK "M:\Program Files\Citrix\Server Resource Management\CPU Utilization Management\bin\ctxcpusched.exe" Stopped Citrix CPU Utilization Mgmt/Resource Mgmt - LocalSystem Manual Own Process OK "M:\Program Files\Citrix\Server Resource Management\CPU Utilization Management\bin\ctxcpuusync.exe" Stopped Citrix CPU Utilization Mgmt/User-Session Sync - LocalSystem Manual Own Process OK "M:\Program Files\Citrix\system32\CpSvc.exe" Running Citrix Print Manager Service - .\Ctx_SmaUser Auto Own Process OK "M:\Program Files\Citrix\Sma\SmaService.exe" Running Citrix SMA Service - .\Ctx_SmaUser Auto Own Process OK "M:\Program Files\Citrix\System Monitoring\Agent\Core\rscorsvc.exe" Running Citrix System Monitoring Agent - LocalSystem Auto Own Process OK "M:\Program Files\Citrix\Server Resource Management\Memory Optimization Management\Program\CtxSFOSvc.exe" Stopped Citrix Virtual Memory Optimization - LocalSystem Manual Own Process OK "M:\Program Files\Citrix\system32\citrix\WMI\ctxwmisvc.exe" Running Citrix WMI Service - LocalSystem Manual Own Process OK "M:\Program Files\Citrix\XTE\bin\XTE.exe" -k runservice -n "CitrixXTEServer" -f "conf/httpd.conf" Running Citrix XTE Server - NT AUTHORITY\NetworkService Manual Own Process OK M:\Program Files\Citrix\system32\cdmsvc.exe Running Client Network

      ### This services starts and stops too frequently

#use strict; ## strict kills the forked process for some reason
use Data::Dumper;
use SNAG;
use POE;
use File::Spec::Functions qw/catfile/;
use Date::Format;
use Net::Ping;
use Storable qw/store retrieve/;

our @EXPORT = qw/system config_info service_monitor iscsi/; 
our %EXPORT_TAGS = ( 'all' => \@EXPORT ); 

our $config =
{
#  'listening_ports'     => { 'period' => 300, data => $SNAG::Dispatch::shared_data },
  'tags'                => { 'period' => 300, data => $SNAG::Dispatch::shared_data },
  'service_monitor'     => { 'period' => 300 },
  'iscsi'               => { 'period' => 300, if_tag => 'storage.iscsi.client' },

  'config_info'         => { 'period' => 7200 },
  'system'              => { 'period' => 21600 },
};

#our @EXPORT = keys %$config;
#our %EXPORT_TAGS = ( 'all' => \@EXPORT );

sub system
{
  require Win32::OLE;
  import Win32::OLE qw/in/;

  binmode(STDOUT);

  my $wmi = Win32::OLE->GetObject ("winMgmts:{(Security)}!//");

  my $info;

  $info->{entity}->{type} = 'system';

  $info->{SNAG}->{version} = VERSION;
  $info->{SNAG}->{perl} = sprintf("%vd", $^V);

  $info->{os}->{os} = OS;

  my $get_os = $wmi->ExecQuery('select * from Win32_OperatingSystem');
  foreach my $ref ( in $get_os )
  {
    $info->{os}->{os_version} = $ref->{Caption} . ' ' . $ref->{'CSDVersion'};
    $info->{os}->{os_kernel} = $ref->{Version};
    #$info->{os}->{os_arch} = $ref->{OSArchitecture};
    $info->{os}->{os_arch} = $ENV{'PROCESSOR_ARCHITECTURE'};
  }

  my $get_bios = $wmi->ExecQuery('select * from Win32_BIOS');
  foreach my $ref ( in $get_bios )
  {
    $info->{bios}->{bios_date} = $ref->{ReleaseDate};
    $info->{bios}->{bios_version} = $ref->{Name};
    $info->{bios}->{bios_vendor} = $ref->{Manufacturer};
  }

  my $get_system_product = $wmi->ExecQuery('select * from Win32_ComputerSystemProduct');
  foreach my $ref ( in $get_system_product )
  {
    $info->{device}->{uuid} = $ref->{UUID};
    $info->{device}->{serial} = $ref->{IdentifyingNumber};
  }

  my $get_system = $wmi->ExecQuery('select * from Win32_ComputerSystem');
  foreach my $ref ( in $get_system )
  {
    $info->{device}->{vendor} = $ref->{Manufacturer};

    my $model;

    if($ref->{Manufacturer} =~ /^\s*Xen\s*$/)
    {
      $model = 'Xen Virtual Platform';
    }
    else
    {
      $model = $ref->{Model};
      $model =~ s/(^\s+)|(\s+$)//g;

      if($model =~ s/\s*\-\[(\w+)\]\-//)
      {
        $info->{device}->{model_type} = $1
      }
    }

    $info->{device}->{model} = $model;

    $info->{cpumem}->{cpu_count} = $ref->{NumberOfProcessors};

    my $mem = $ref->{TotalPhysicalMemory};
    $mem = $mem / 1073741824;
    $mem = sprintf("%.1f", $mem);
    $info->{cpumem}->{mem} = $mem . " GB";
  }

  my $get_proc = $wmi->ExecQuery('select * from Win32_Processor');
  foreach my $ref ( in $get_proc )
  {
    (my $cpu = $ref->{Name}) =~ s/(^\s+)|(\s+$)//g;

    $info->{cpumem}->{cpu} = $cpu;
    $info->{cpumem}->{cpu_speed} = $ref->{MaxClockSpeed} . ' MHz';
    $info->{cpumem}->{cpu_cache} = $ref->{L2CacheSize} . ' KB';
  }

  my $adapters;
  my $get_adapters = $wmi->ExecQuery('select * from Win32_NetworkAdapterConfiguration');
  foreach my $ref ( in $get_adapters )
  {
    next if $ref->{ServiceName} eq 'msloop';

    my ($iface_name, $iface_name_type, $key);
    if($key = $ref->{InterfaceIndex})
    {
      $iface_name = $key;
      $iface_name_type = 'InterfaceIndex';
    }
    elsif($key = $ref->{ServiceName})
    {
      $iface_name = $key;
      $iface_name_type = 'ServiceName';
    }

    for(my $i=0; $i <= $#{$ref->{IPAddress}}; $i++)
    {
      $key = $iface_name;

      if($i > 0)
      {
        $key .= ":$i";
      }

      push @$adapters,
      {
        iface => $key,
        iface_name_type => $iface_name_type,
        mac => lc($ref->{MACAddress}),
        ip => $ref->{IPAddress}->[$i],
        netmask => $ref->{IPSubnet}->[$i],
      };
    }
  }

  foreach my $iface (@$adapters)
  {
    my $iface_name_type = delete $iface->{iface_name_type};

    if($iface->{ip} && $iface->{mac})
    {
      my $get_settings = $wmi->ExecQuery("select * from Win32_NetworkAdapter where $iface_name_type = '$iface->{iface_name}' ");

      if($get_settings)
      {
        foreach my $settings ( in $get_settings )
        {
          $iface->{speed} = $settings->{Speed};
          $iface->{duplex} = $settings->{MaxSpeed};
          $iface->{neg} = $settings->{AutoSense};
        }
      }
    }
    else
    {
      next;
    }

    push @{$info->{iface}}, $iface;
  }

  my $get_disks = $wmi->ExecQuery('select * from Win32_DiskDrive');
  foreach my $ref ( in $get_disks )
  {
    next unless $ref->{Size};

    my %disk;
    $disk{size} = sprintf("%.1f GB", $ref->{Size} / 1073741824);
    ($disk{device}) = ($ref->{DeviceID} =~ /(\w+)/);
    $disk{vendor} = $ref->{Manufacturer};
    $disk{model} = $ref->{Model};

    push @{$info->{disk}}, \%disk;
  }

  my $get_pci = $wmi->ExecQuery('select * from Win32_OnBoardDevice');
  foreach my $ref ( in $get_pci )
  {
    push @{$info->{pci}}, { description => "$ref->{Tag}: $ref->{Description}" };
  }

  return $info;
}

sub iscsi
{
  binmode(STDOUT);

  my $info;
  my $section;

  my $session_data = {};

  $/ = "\n\n";

  foreach my $chunk (`iscsicli sessionlist`)
  {
    chomp $chunk;

    if($chunk =~ /^Session Id/ || $chunk =~ /^The operation completed successfully/)
    {
      push @$info, $session_data if %$session_data;

      $session_data = {};
      $section = 'session';
    }

    next unless $section;

    if($chunk =~ s/^\s+Connections:\s*$//m)
    {
      $section = 'connections';
    }
    elsif($chunk =~ s/^\s+Devices:\s*$//m)
    {
      $section = 'devices';
    }

    my ($ref, $previous_key);

    foreach my $line (split /\n/, $chunk)
    {
      next if $line =~ /^\s*$/;

      if(my ($key, $val) = split /\s+:\s*/, $line, 2)
      {
        if($previous_key eq 'volume_path_names' && !$val)
        {
          $val = $key;
          $key = $previous_key;
        }

        $key =~ s/^\s+//;
        $key =~ s/\s+$//;

        $val =~ s/^\s+//;
        $val =~ s/\s+$//;

        $key =~ s/\s/_/g;
        $key = lc($key);

        $ref->{$key} = $val;

        $previous_key = $key;
      }
    }

    if($section eq 'session')
    {
      $session_data = $ref;
    }
    else
    {
      push @{$session_data->{$section}}, $ref;
    }
  }

  my $total_connections = 0;
  my $seen = time2str("%Y-%m-%d %T", time);
  foreach my $session (@$info)
  {
    $total_connections += $session->{number_connections};

    if($session->{connections})
    {
      my $ping_failure_flag;

      my $p = Net::Ping->new('icmp');
      foreach my $ref (@{$session->{connections}})
      {
        (my $ip = $ref->{target_portal}) =~ s#/\d+$##;
        my $ping_status = $p->ping($ip, 1);

        unless($ping_status)
        {
          $ping_failure_flag = 1;

          print STDERR join REC_SEP, ('events', HOST_NAME, 'sysinfo', 'iscsi', 'Ping to filer failed', "Ping to filer at $ip failed", '', $seen);
          print STDERR "\n";
        }
      }
      $p->close();

      unless($ping_failure_flag)
      {
        foreach my $line (`iscsicli reportluns $session->{session_id}`)
        {  
          chomp $line;

          unless($line =~ /ScsiStatus\s+:\s+0x0\s+/)
          {  
            print STDERR join REC_SEP, ('events', HOST_NAME, 'sysinfo', 'iscsi', 'Unexpected return from iscsicli reportluns', $line, '', $seen);
            print STDERR "\n";
          }
        }
      }
    }
  }

  if($total_connections == 0)
  {
    my $seen = time2str("%Y-%m-%d %T", time);

    print STDERR join REC_SEP, ('events', HOST_NAME, 'sysinfo', 'iscsi', 'iscsi client connection down', '0 total connections to filer', '', $seen);
    print STDERR "\n";
  }

  return $info;
}

sub config_info
{
  require Win32::OLE;
  import Win32::OLE qw/in/;

  binmode(STDOUT);

  my $wmi = Win32::OLE->GetObject ("winMgmts:{(Security)}!//");

  my $info;

  my $confs =
  {
    'scheduled_jobs' =>
    {
      'columns' => [ qw/Command JobId InstallDate StartTime UntilTime ElapsedTime RunRepeatedly DaysOfWeek DaysOfMonth InteractWithDesktop Owner/ ],
      'class' => 'Win32_ScheduledJob',
      'sort' => 'JobId',
    },

    'local_groups' =>
    {
      'columns' => [ qw/Name SID Status/ ],
      'sort' => 'Name',
      'query_override' => "select * from Win32_Group where LocalAccount = 'TRUE'",
    },

    'services' =>
    {
      'columns' => [ qw/DisplayName PathName ServiceType StartMode StartName DesktopInteract/ ],
      'class' => 'Win32_Service',
      'sort' => 'DisplayName',
    },

    'static_routes' =>
    {
      'columns' => [ qw/InterfaceIndex Mask NextHop Destination/ ],
      'class' => 'Win32_IP4RouteTable',
      'sort' => 'InterfaceIndex',
    },

    'installed_software' =>
    {
      'columns' => [ qw/Name Vendor Version InstallDate IdentifyingNumber InstallState/ ],
      'class' => 'Win32_Product',
      'sort' => 'Name',
    },

    'hotfixes' =>
    {
      'columns' => [ qw/HotFixID Description InstalledOn InstalledBy ServicePackInEffect FixComments/ ],
      'class' => 'Win32_QuickFixEngineering',
      'sort' => 'HotFixID',
    },

    'logical_disks' =>
    {
      'columns' => [ qw/DeviceID FileSystem MediaType Description Size/ ],
      'class' => 'Win32_LogicalDisk',
      'sort' => 'DeviceID',
    },
  };

  ### Do not query_wmi local users if this box is a domain controller
  my $check_domain_role = $wmi->ExecQuery('select * from Win32_ComputerSystem');
  foreach my $ref ( in $check_domain_role )
  {
    unless($ref->{DomainRole} == 4 || $ref->{DomainRole} == 5)
    {
      $confs->{'local_users'} =
      {
        'columns' => [ qw/Name FullName SID Status Disabled PasswordRequired PasswordExpires PasswordChangeable Lockout/ ],
        'query_override' => "select * from Win32_UserAccount where LocalAccount = 'TRUE'",
        'sort' => 'Name',
      };
    }
  }

  while( my ($conf, $ref) = each %$confs)
  {
    my $data;

    my $query_string;
    if($ref->{query_override})
    {
      $query_string = $ref->{query_override};
    }
    else
    {
      $query_string = "select * from $ref->{class}";
    }

    my $get_conf = $wmi->ExecQuery($query_string);

    foreach my $element ( in $get_conf )
    {
      push @$data, { map { $_ => $element->{$_} } @{$ref->{columns}} };
    }

    if($data)
    {
      $info->{conf}->{ $conf }->{contents} = &format( { columns => $ref->{columns}, data => $data, 'sort' => $ref->{'sort'} } );
    }
  }

  return $info;
}


sub service_monitor
{
  require Win32::OLE;
  import Win32::OLE qw/in/;

  binmode(STDOUT);

  my $wmi = Win32::OLE->GetObject ("winMgmts:{(Security)}!//");

  my $state_file = catfile(LOG_DIR, 'service_monitor.state');
  my $service_monitor;

  if(-e $state_file)
  {
    $service_monitor = retrieve($state_file) or die "Could not open $state_file";
  }
 
  my $info;

  my $get_services = $wmi->ExecQuery("select * from Win32_Service");
  foreach my $ref ( in $get_services )
  {
    my ($service, $status, $state) = @$ref{'DisplayName', 'Status', 'State'};

    unless($status eq 'OK')
    {
      my $seen = time2str("%Y-%m-%d %T", time);
      $poe_kernel->post('client' => 'dashboard' => 'load' => join REC_SEP, ('events', HOST_NAME, 'sysinfo', 'service_state', 'service state change', "service $service status not 'OK': $status", '', $seen) );  
    }

    my $running_flag = $state eq 'Running' ? 1 : 0;

    my ($old_ratio, $samples) = (0, 0);

    if($service_monitor->{$service})
    {
      $old_ratio = $service_monitor->{$service}->{run_ratio};
      $samples = $service_monitor->{$service}->{samples};
    }

    if($samples > 40 && !$running_flag && $old_ratio > .95)
    {
      my $pct = sprintf('%.0f', $old_ratio * 100);
      my $seen = time2str("%Y-%m-%d %T", time);

      $poe_kernel->post('client' => 'dashboard' => 'load' => join REC_SEP, ('events', HOST_NAME, 'sysinfo', 'service_state', 'service state change', "service $service is not running.  usual run rate is $pct%", '', $seen) );
    }

    my $new_ratio
      = ( ( $old_ratio * $samples ) + $running_flag ) / ( $samples + 1 );

    $service_monitor->{$service}->{run_ratio} = $new_ratio;
    $service_monitor->{$service}->{samples}++;
  }

  store($service_monitor, $state_file) or die "Could not store $state_file";

  return {};
}
   

sub format
{
  my $args = shift;

  my $columns = $args->{columns};
  my $data = $args->{data};
  my $sort = $args->{sort};

  my $del = '  ';
  my %col_width;

  foreach my $col (@$columns)
  {
    $col_width{$col} = length $col;
  }

  foreach my $row (@$data)
  {
    while(my ($col, $val) = each %$row)
    {
      my $length = length $val;
      $col_width{$col} = $length if $length > $col_width{$col};
    }
  }

  $data = [ sort { $a->{$sort} cmp $b->{$sort} } @$data ];

  my $formatted;

  foreach my $col (@$columns)
  {
    $formatted .= sprintf("%-$col_width{$col}s", $col) . $del;
  }
  $formatted .= "\n";

  foreach my $col (@$columns)
  {
    $formatted .= '-' x $col_width{$col} . $del;
  }
  $formatted .= "\n";

  foreach my $row (@$data)
  {
    foreach my $col (@$columns)
    {
      $formatted .= sprintf("%-$col_width{$col}s", $row->{$col} || '-') . $del;
    }
    $formatted .= "\n";
  }

  return $formatted;
}

1;

