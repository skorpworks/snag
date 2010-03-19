package SNAG::Source::SystemStats::Windows;

use strict;

use SNAG;
use POE;
use POE::Filter::Line;
use Time::Local;
use URI::Escape;
use Data::Dumper;
use Win32::OLE qw/in/;

my $del = ':';

my $wmi = Win32::OLE->GetObject ("winMgmts:{(Security)}!//");

#####################################################################################
############  NETSTAT  ##############################################################
#####################################################################################

sub run_netstat
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

#F:\systems\SNAG\SNAG-windows>netstat -an
#
#Active Connections
#
#  Proto  Local Address          Foreign Address        State
#  TCP    0.0.0.0:135            0.0.0.0:0              LISTENING
#  TCP    0.0.0.0:445            0.0.0.0:0              LISTENING
#  TCP    0.0.0.0:1030           0.0.0.0:0              LISTENING
#  TCP    10.254.254.253:139     0.0.0.0:0              LISTENING
#  TCP    10.254.254.253:139     129.219.80.69:1040     ESTABLISHED
#  TCP    127.0.0.1:1079         0.0.0.0:0              LISTENING
#  TCP    129.219.80.69:139      0.0.0.0:0              LISTENING
#  TCP    129.219.80.69:1040     10.254.254.253:139     ESTABLISHED
#  TCP    129.219.80.69:1081     129.219.100.13:1025    ESTABLISHED
#  TCP    129.219.80.69:1273     129.219.12.221:1676    ESTABLISHED
#  TCP    129.219.80.69:2663     129.219.13.87:13356    ESTABLISHED
#  TCP    129.219.80.69:2664     129.219.13.77:13354    ESTABLISHED
#  TCP    129.219.80.69:2665     129.219.15.200:13351   ESTABLISHED
#  TCP    129.219.80.69:2666     129.219.15.200:13349   ESTABLISHED
#  TCP    129.219.80.69:3032     129.219.12.227:14361   ESTABLISHED
#  TCP    129.219.80.69:3766     129.219.10.140:3389    ESTABLISHED
#  TCP    129.219.80.69:4066     129.219.10.212:3268    CLOSE_WAIT

  foreach my $output (`netstat -an`)
  {
    next if $output =~ /Active Connections/;
    next if $output =~ /^\s*$/;
    next if $output =~ /^\s*Proto/;
    next if $output =~ /^\s*UDP/;

    my @fields = split /\s+/, $output;

    my ($state, $remote, $local)  = @fields[-1, -2, -3];

    my ($local_ip, $local_port) = split /:/, $local;

    $heap->{netstat_states}->{$state}++;

    if($state eq 'LISTENING')
    {
      $heap->{listening_ports}->{$local_port}->{$local_ip}++;
    }
    elsif($state eq 'ESTABLISHED')
    {
      my ($remote_ip, $remote_port) = split /:/, $remote;

      #if(my $host = $SNAG::Dispatch::shared_data->{remote_hosts}->{ips}->{$remote_ip})
      #{
	##### Only look at activity on listening ports, Ignore SSH and SNAG connections, and ignore connections to the same host
	#if( $SNAG::Dispatch::shared_data->{remote_hosts}->{ports}->{$remote_port}
	    #&& $remote_port ne '22'
	    #&& $local_port ne '22'
	    #&& $remote_port !~ /^133[3-5]\d$/
	    #&& !$heap->{listening_ports}->{$local_port}
	    #&& $host ne HOST_NAME
	  #)
	#{
	  #$heap->{netstat_remote_cons}->{ $host }->{$remote_port}++;
	#}
      #}

      if($heap->{listening_ports}->{$local_port} && $local_port ne '22' && $local_ip ne $remote_ip)
      {
	      $heap->{netstat_local_cons}->{$local_port}++;
      }
    }
  }

  my $time = time();

  while(my ($state, $count) = each %{$heap->{netstat_states}})
  {
    $state = $SNAG::Source::SystemStats::netstat_states{$state} || $state;
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME, 'net_' . $state, "1g", $time, $count));
  }
  delete $heap->{netstat_states};

  while(my ($port, $count) = each %{$heap->{netstat_local_cons}})
  {
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME, 'lp_' . $port, "1g", $time, $count));
  }
  delete $heap->{netstat_local_cons};

  #foreach my $host (keys %{$heap->{netstat_remote_cons}})
  #{
    #while( my ($port, $count) = each %{$heap->{netstat_remote_cons}->{$host}})
    #{
      #$kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME, 'rcon_' . $host . '_' . $port, "1g", $time, $count));
    #}
  #}
  #delete $heap->{netstat_remote_cons};

  $SNAG::Dispatch::shared_data->{listening_ports} = delete $heap->{listening_ports};

  delete $heap->{running_states}->{run_netstat};
}

#####################################################################################
############  WMI  ##################################################################
#####################################################################################

sub run_wmi
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  my $time = time;

  my $get_cpu_stats = $wmi->ExecQuery('select * from Win32_PerfFormattedData_PerfOS_Processor');
  foreach my $ref ( in $get_cpu_stats )
  {
    next unless $ref->{Name} eq '_Total';  

    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME, 'cpuuser', '1g', $time, $ref->{PercentUserTime} || '0') );
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME, 'cpusys', '1g', $time, $ref->{PercentPrivilegedTime} || '0') );
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME, 'cpuiow', '1g', $time, $ref->{PercentInterruptTime} || '0') );
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME, 'intrpts', '1g', $time, $ref->{InterruptsPersec} || '0') );
  }

  my $get_system_stats = $wmi->ExecQuery('select * from Win32_PerfFormattedData_PerfOS_System');
  foreach my $ref ( in $get_system_stats )
  {
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME, 'contxts', '1g', $time, $ref->{ContextSwitchesPersec} || 0 ) );
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME, 'proc', '1g', $time, $ref->{Processes}) );
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME, 'uptime', '1g', $time, $ref->{SystemUpTime}) );
  }

  my $get_mem_tot = $wmi->ExecQuery('select * from Win32_ComputerSystem');
  foreach my $ref ( in $get_mem_tot )
  {
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME, 'memtot', '1g', $time, $ref->{TotalPhysicalMemory} / 1024) );
  }

  my $get_mem_stats = $wmi->ExecQuery('select * from Win32_PerfFormattedData_PerfOS_Memory');
  foreach my $ref ( in $get_mem_stats )
  {
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME, 'memfree', '1g', $time, $ref->{AvailableBytes} / 1024) );
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME, 'memcache', '1g', $time, $ref->{CacheBytes} / 1024) );
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME, 'memcom', '1g', $time, $ref->{CommittedBytes} / 1024) );
  }

  my $disk_labels;
  my $get_disk_stats = $wmi->ExecQuery('select * from Win32_PerfFormattedData_PerfDisk_LogicalDisk');
  foreach my $ref ( in $get_disk_stats )
  {
    next if $ref->{Name} eq '_Total';
    (my $label = $ref->{Name}) =~ s/://g; 
    next unless $label;

    $disk_labels->{$label}++;

    my $multi = URI::Escape::uri_escape($label);

    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME . "[$multi]", 'iors', '1g', $time, $ref->{DiskReadsPersec} || 0) );
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME . "[$multi]", 'iows', '1g', $time, $ref->{DiskWritesPersec} || 0) );

    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME . "[$multi]", 'iorkbs', '1g', $time, $ref->{DiskReadBytesPersec} / 1024 ) );
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME . "[$multi]", 'iowkbs', '1g', $time, $ref->{DiskWriteBytesPersec} / 1024 ) );

    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME . "[$multi]", 'avgrqsz', '1g', $time, $ref->{AvgDisksecPerTransfer}) );
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME . "[$multi]", 'avgqusz', '1g', $time, $ref->{AvgDiskQueueLength}) );
  }

  my $get_disk_cap = $wmi->ExecQuery('select * from Win32_LogicalDisk');
  foreach my $ref ( in $get_disk_cap )
  {
    (my $label = $ref->{Name}) =~ s/://g; 
    next unless $disk_labels->{$label};

    my $multi = URI::Escape::uri_escape($label);

    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME . "[$multi]", 'dsk_cap', '1g', $time, $ref->{Size} / 1024) );
    
    my $disk_used = $ref->{Size} - $ref->{FreeSpace};
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME . "[$multi]", 'dsk_used', '1g', $time, $disk_used / 1024) );

    next unless $ref->{Size}; ## No divide by zero
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME . "[$multi]", 'dsk_pct', '1g', $time, sprintf('%.0f', ($disk_used / $ref->{Size}) * 100)) );
  }

                      ### DEFER TO NETSTAT OUTPUT FOR THIS STUFF
                      #my $get_tcp_stats = $wmi->ExecQuery('select * from Win32_PerfFormattedData_Tcpip_TCP');
                      #foreach my $ref ( in $get_tcp_stats )
                      #{
                      #  print join $del, (HOST_NAME, 'net_fail', '1g', $time, $ref->{ConnectionFailures});  print "\n";
		#	print join $del, (HOST_NAME, 'net_actv', '1g', $time, $ref->{ConnectionsActive});  print "\n";
		#	print join $del, (HOST_NAME, 'net_est', '1g', $time, $ref->{ConnectionsEstablished});  print "\n";
		#	print join $del, (HOST_NAME, 'net_pass', '1g', $time, $ref->{ConnectionsPassive});  print "\n";
		#	print join $del, (HOST_NAME, 'net_reset', '1g', $time, $ref->{ConnectionsReset});  print "\n";
                #      }

  ################### INTERFACE STATS ######################
  #while (my ($desc, $iface) = each %ifaces)
  #{
  #  my $iface_stats = query_wmi($wmi, 'Win32_PerfFormattedData_Tcpip_NetworkInterface', { Name => $desc } );
#
#    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host . "[$iface]", 'inbytepsec', '1g', $time, $iface_stats->{BytesReceivedPersec})) if $iface_stats->{BytesReceivedPersec};
#    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host . "[$iface]", 'inpktspsec', '1g', $time, $iface_stats->{PacketsReceivedPersec})) if $iface_stats->{PacketsReceivedPersec};
#
#    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host . "[$iface]", 'outbytepsec', '1g', $time, $iface_stats->{BytesSentPersec})) if $iface_stats->{BytesSentPersec};
#    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host . "[$iface]", 'outpktspsec', '1g', $time, $iface_stats->{PacketsSentPersec})) if $iface_stats->{PacketsSentPersec};
#
#    ### These are counters
#    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host . "[$iface]", 'inerr', '1d', $time, $iface_stats->{PacketsReceivedErrors})) if $iface_stats->{PacketsReceivedErrors};
#    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host . "[$iface]", 'indrop', '1d', $time, $iface_stats->{PacketsReceivedDiscarded})) if $iface_stats->{PacketsReceivedDiscarded};
#
#    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host . "[$iface]", 'outerr', '1d', $time, $iface_stats->{PacketsOutboundErrors})) if $iface_stats->{PacketsOutboundErrors};
#    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host . "[$iface]", 'outdrop', '1d', $time, $iface_stats->{PacketsOutboundDiscarded})) if $iface_stats->{PacketsOutboundDiscarded};
#  }
  delete $heap->{running_states}->{run_wmi};
}

1;
