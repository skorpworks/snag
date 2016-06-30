package SNAG::Source::SystemStats::SunOS;

use SNAG;
use POE;
use POE::Wheel::Run;
use POE::Filter::Line;
use Time::Local;
use URI::Escape;
use Data::Dumper;
use strict;

my $del =  ':';
my $host = HOST_NAME;
my $rrd_step   = $SNAG::Source::SystemStats::rrd_step || 60;
my $rrd_min    = $rrd_step/60;
my $stat_quanta = 58;
my $stat_loops  = $rrd_min + 1;



#-[~:#]- zpool iostat 58 2
               #capacity     operations    bandwidth
#pool         used  avail   read  write   read  write
#----------  -----  -----  -----  -----  -----  -----
#zpool01     58.5T  1.49T  2.34K    265  18.7M  3.54M
#zsystem     2.99G   405G      0      0    847  2.86K
#----------  -----  -----  -----  -----  -----  -----
#zpool01     58.5T  1.49T  2.45K    129  19.4M  1.82M
#zsystem     2.99G   405G      0      1     88  4.65K
#----------  -----  -----  -----  -----  -----  -----

sub run_zpool
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{zpool_data} = {}; 

  $heap->{zpool_wheel} = POE::Wheel::Run->new 
  (  
    Program      => [ '/usr/sbin/zpool', 'iostat', $stat_quanta, $stat_loops ],
    StdioFilter  => POE::Filter::Line->new(),    
    StderrFilter => POE::Filter::Line->new(),    
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_zpool_child_stdio',       
    StderrEvent  => 'supp_zpool_child_stderr',       
    CloseEvent   => "supp_zpool_child_close",
  );
}


sub supp_zpool_child_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

  next unless $output =~ /^zpool/;

  my @fields = split /\s+/, $output;

  $heap->{zpool_data}->{used} = $fields[1];
  $heap->{zpool_data}->{avail} = $fields[2];
  $heap->{zpool_data}->{op_read} = $fields[3];
  $heap->{zpool_data}->{op_write} = $fields[4];
  $heap->{zpool_data}->{bw_read} = $fields[5];
  $heap->{zpool_data}->{bw_write} = $fields[6];
}

sub supp_zpool_child_stderr
{
}

sub supp_zpool_child_close
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

  my $time = time;
  
  my $zpool_total;

  while (my ($key, $val) = each %{$heap->{zpool_data}})
  {
    my ($num, $unit) = ( $val =~ /^([\d\.]+)([KMGT]*)$/ ); 

    if($unit)
    {
      foreach my $u ('K', 'M', 'G', 'T')
      {
        $num *= 1024; 
        last if $u eq $unit;
      }
    }

    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'zpool_' . $key, '1g', $time, $num) );

    $zpool_total += $num if ($key eq 'used' || $key eq 'avail');
  }

  $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'zpool_total', '1g', $time, $zpool_total) );

  delete $heap->{running_states}->{run_zpool};
  delete $heap->{zpool_wheel};
}



#Server nfs:
#calls     badcalls  
#484642990 2504083   
#Version 3: (477366101 calls)
#null          getattr       setattr       lookup        access        
#52 0%         6272768 1%    835866 0%     4045706 0%    6645416 1%    
#readlink      read          write         create        mkdir         
#0 0%          395579786 82% 57207867 11%  474233 0%     0 0%          
#symlink       mknod         remove        rmdir         rename        
#0 0%          0 0%          99364 0%      0 0%          0 0%          
#link          readdir       readdirplus   fsstat        fsinfo        
#0 0%          0 0%          0 0%          189644 0%     33 0%         
#pathconf      commit        
#2 0%          6015364 1%    
#********************************************************************************
#
#Server nfs:
#calls     badcalls  
#3156      0         
#Version 3: (3141 calls)
#null          getattr       setattr       lookup        access        
#0 0%          35 1%         0 0%          11 0%         36 1%         
#readlink      read          write         create        mkdir         
#0 0%          3057 97%      0 0%          0 0%          0 0%          
#symlink       mknod         remove        rmdir         rename        
#0 0%          0 0%          0 0%          0 0%          0 0%          
#link          readdir       readdirplus   fsstat        fsinfo        
#0 0%          0 0%          0 0%          2 0%          0 0%          
#pathconf      commit        
#0 0%          0 0%          
#********************************************************************************

sub run_nfsstat
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{nfsstat_data} = {}; 
  $heap->{nfsstat_keys} = []; 

  $heap->{nfsstat_wheel} = POE::Wheel::Run->new 
  (  
    Program      => [ "/usr/bin/nfsstat", '-n', '-s', '-v 3', $stat_quanta, $stat_loops ],
    StdioFilter  => POE::Filter::Line->new(),    
    StderrFilter => POE::Filter::Line->new(),    
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_nfsstat_child_stdio',       
    StderrEvent  => 'supp_nfsstat_child_stderr',       
    CloseEvent   => "supp_nfsstat_child_close",
  );
}


sub supp_nfsstat_child_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

  return if $output =~ /^Server nfs/;
  return if $output =~ /^Version/;

  if($output =~ /^[a-z]/)
  {
    $heap->{nfsstat_keys} = [ split /\s+/, $output ];
  }
  elsif($output =~ /^\d/)
  {
    my @values = grep { /^\d+$/ } split /\s+/, $output;

    if(scalar @{$heap->{nfsstat_keys}} == scalar @values)
    {
      for ( my $i = 0; $i < $#values; $i++)
      {
        $heap->{nfsstat_data}->{ $heap->{nfsstat_keys}->[$i] } = $values[$i];
      }
    }
    else
    {
      print STDERR "key and value count mismatch :(";
    }
  }
  elsif($output =~ /^\*\*\*/)
  {
    if(++$heap->{nfsstat_data}->{sep} >= 2)
    {
      my $time = time;

      while (my ($key, $val) = each %{$heap->{nfsstat_data}})
      {
	next if $key eq 'calls';
	next if $key eq 'sep';

	$kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'nfs3_' . $key, '1g', $time, $val) );
      }

      kill 'TERM', $heap->{nfsstat_wheel}->PID;

      delete $heap->{running_states}->{run_nfsstat};
      delete $heap->{nfsstat_wheel};
    }
  }
}

sub supp_nfsstat_child_stderr
{
}

sub supp_nfsstat_child_close
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

  delete $heap->{running_states}->{run_nfsstat};
  delete $heap->{nfsstat_wheel};
}

######################################################################################
############  IOSTAT IO  ############################################################
#####################################################################################

sub run_iostat_io
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{iostat_io_count} = (); 
  $heap->{iostat_io_wheel} = POE::Wheel::Run->new 
  (  
    Program      => [ "/usr/bin/iostat", '-x', $stat_quanta, $stat_loops ],
    StdioFilter  => POE::Filter::Line->new(),    
    StderrFilter => POE::Filter::Line->new(),    
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_iostat_io_child_stdio',       
    StderrEvent  => 'supp_iostat_io_child_stderr',       
    CloseEvent   => "supp_iostat_io_child_close",
  );
}

sub supp_iostat_io_child_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

  ## iostat -xnmp 2 2
  #                    extended device statistics              
  #    r/s    w/s   kr/s   kw/s wait actv wsvc_t asvc_t  %w  %b device
  #    0.3   23.8    7.4  198.7  0.0  0.3    0.0   13.3   0  16 d0
  #    0.6   23.8   15.0  199.0  0.0  0.4    1.7   14.7   4  18 d1 (/)
  #    0.1    0.0    0.5    3.2  0.0  0.0    0.0   48.0   0   0 d2
  #    0.1    0.0    1.0    3.2  0.0  0.0    0.4   35.2   0   0 d3
  #    0.3   23.8    7.5  198.6  0.0  0.2    0.0    7.9   0  14 d4
  #    0.1    0.0    0.5    3.2  0.0  0.0    0.0   27.3   0   0 d5
  #    0.0    0.0    0.0    0.0  0.0  0.0    0.0    0.0   0   0 c0t6d0
  #   30.5   29.3  205.9  238.1  0.0  0.4    0.4    7.3   0  16 c6t101d0
  #    8.2    7.8   53.5   63.7  0.0  0.1    0.4    7.3   0   5 c6t101d0s0 (/cyrus1a)
  #
  #     1      2      3      4    5    6      7      8    9  10 11            12


#              extended device statistics                 
#device    r/s    w/s   kr/s   kw/s wait actv  svc_t  %w  %b 
#md10      0.0    0.0    0.0    0.0  0.0  0.0    0.0   0   0 
#md11      0.0    0.0    0.0    0.0  0.0  0.0    0.0   0   0 
#md13      0.0    0.6    0.0    3.0  0.0  0.0    0.3   0   0 
#md14      0.0    0.0    0.0    0.0  0.0  0.0    0.0   0   0 
#md20      0.0    0.0    0.0    0.0  0.0  0.0    0.0   0   0 
#md21      0.0    0.0    0.0    0.0  0.0  0.0    0.0   0   0 
#md23      0.0    0.6    0.0    3.0  0.0  0.0    0.3   0   0 
#md24      0.0    0.0    0.0    0.0  0.0  0.0    0.0   0   0 
#md30      0.0    0.0    0.0    0.0  0.0  0.0    0.0   0   0 
#md31      0.0    0.0    0.0    0.0  0.0  0.0    0.0   0   0 
#md33      0.0    0.6    0.0    3.0  0.0  0.0    0.4   0   0 
#md34      0.0    0.0    0.0    0.0  0.0  0.0    0.0   0   0 
#sd0       0.0    0.0    0.0    0.0  0.0  0.0    0.0   0   0 
#sd2       0.1    1.7    0.0    7.8  0.0  0.0    0.9   0   0 
#sd3     271.9    2.5  545.4    4.3  1.3  1.4    9.9  22  41 
#sd4     274.6    2.4  544.1    4.3  0.6  2.5   11.4  11  41 
#sd5     278.7    1.7  572.0    2.7  1.8  1.0    9.8  30  42 
#sd6     277.4    1.7  571.0    2.7  1.3  1.9   11.2  20  44 
#sd7     254.5    0.8  510.9    1.7  1.1  1.1    8.4  21  38 

 
  if ($output =~ /^(\w+)\s+([\w\.]+)\s+([\w\.]+)\s+([\w\.]+)\s+([\w\.]+)\s+([\w\.]+)\s+([\w\.]+)\s+([\w\.]+)\s+([\w\.]+)\s+([\w\.]+)\s*$/ && $heap->{iostat_io_count}->{$1}++ >= 1)
  {
    my $time = time;
    my $data = { dev => $1, iors => $2, iows => $3, iorkbs => $4, iowkbs => $5, 'wait' => $6, actv => $7, svc_t => $8, pwait => $9, pbusy => $10 };
    my $dev = delete $data->{dev};

    while ( my ($field, $val) = each %$data)
    {
      $val = 0 if $val eq '0.0';
      $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, $field . '_' . $dev, '1g', $time, $val) );
    }
  }
}


sub supp_iostat_io_child_stderr
{
}

sub supp_iostat_io_child_close
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  delete $heap->{running_states}->{run_iostat_io};
  delete $heap->{iostat_io_wheel};
}



#####################################################################################
############  IOSTAT CPU  ############################################################
#####################################################################################

sub run_iostat_cpu
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{iostat_cpu_count} = 0; 
  $heap->{iostat_cpu_wheel} = POE::Wheel::Run->new 
  (  
    Program      => [ "/usr/bin/iostat", "-c", $stat_quanta, $stat_loops ],
    StdioFilter  => POE::Filter::Line->new(),    
    StderrFilter => POE::Filter::Line->new(),    
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_iostat_cpu_child_stdio',       
    StderrEvent  => 'supp_iostat_cpu_child_stderr',       
    CloseEvent   => "supp_iostat_cpu_child_close",
  );
}

sub supp_iostat_cpu_child_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

# /usr/bin/iostat -c 2 2
#     cpu
# us sy wt id
#  2  1  0 97
#  0  0  0 100

  if ($output =~ /^\s+\d/ && $heap->{iostat_cpu_count}++ >= 1)
  {
    my $EpochTime = time();
    my ($Blank,$User,$Sys,$Wait,$Idle) = split /\s+/, $output;
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'cpuuser', '1g', $EpochTime, $User));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'cpusys', '1g', $EpochTime, $Sys));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'cpuiow', '1g', $EpochTime, $Wait));
  }
}

sub supp_iostat_cpu_child_stderr
{
}

sub supp_iostat_cpu_child_close
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  delete $heap->{running_states}->{run_iostat_cpu};
  delete $heap->{iostat_cpu_wheel};
}




#####################################################################################
############  VMSTAT  ############################################################
#####################################################################################

sub run_vmstat
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{vmstat_count} = 0;
  $heap->{vmstat_wheel} = POE::Wheel::Run->new
  (
    Program      => [ "/usr/bin/vmstat", '-S', $stat_quanta, $stat_loops ],
    StdioFilter  => POE::Filter::Line->new(),
    StderrFilter => POE::Filter::Line->new(),
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_vmstat_child_stdio',
    StderrEvent  => 'supp_vmstat_child_stderr',
    CloseEvent   => "supp_vmstat_child_close",
  );
}

sub supp_vmstat_child_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

  # vmstat -S 10 2
  # procs     memory            page            disk          faults      cpu
  # r b w   swap  free  si  so pi po fr de sr dd dd m0 m1   in   sy   cs us sy id
  # 0 0 0 2712216 747048 0   0  0  0  0  0  0  3  1  1  2    1  201   80  2  1 97
  # 0 0 0 2707144 741928 0   0  0  0  0  0  0  1  1  1  1  313  132   82  1  0 98
  # 1 2 3    4      5    6   7  8  9 10 11 12               -6  -5    -4 -3 -2 -1

  if ($output =~ /^\s+\d/ && $heap->{vmstat_count}++ >= 1)
  {
    my $EpochTime = time;
    my @stats = split /\s+/, $output;

    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'memswap', '1g', $EpochTime, $stats[4]));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'memfree', '1g', $EpochTime, $stats[5]));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'swapin', '1g', $EpochTime, $stats[6]));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'swapout', '1g', $EpochTime, $stats[7]));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'pagein', '1g', $EpochTime, $stats[8]));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'pageout', '1g', $EpochTime, $stats[9]));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'intrpts', '1g', $EpochTime, $stats[-6]));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'contxts', '1g', $EpochTime, $stats[-4]));
  }
}

sub supp_vmstat_child_stderr
{
}

sub supp_vmstat_child_close
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  delete $heap->{running_states}->{run_vmstat};
  delete $heap->{vmstat_wheel};
}


#####################################################################################
############  UPTIME  ############################################################
#####################################################################################

sub run_uptime
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{uptime_wheel} = POE::Wheel::Run->new
  (
    Program      => [ "/usr/bin/uptime" ],
    StdioFilter  => POE::Filter::Line->new(),
    StderrFilter => POE::Filter::Line->new(),
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_uptime_child_stdio',
    StderrEvent  => 'supp_uptime_child_stderr',
    CloseEvent   => "supp_uptime_child_close",
  );
}

sub supp_uptime_child_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  # uptime
  # 4:37pm  up 157 day(s),  3:40,  1 user,  load average: 0.02, 0.04, 0.05
  # 4:50pm  up 15:04,  1 user,  load average: 0.13, 0.20, 0.35
  # 10:39am  up 300 day(s), 49 min(s),  3 users,  load average: 0.06, 0.07, 0.12
  # 10:51am  up 300 day(s), 1 hr(s),  3 users,  load average: 0.07, 0.07, 0.10

  if($output =~ /up\s+(.+?),\s+\d+\s+user.+?load average:\s*([\d\.]+),\s*([\d\.]+),\s*([\d\.]+)/)
  {
    my $time = time;
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'lavg1', $rrd_min . "g", $time, $2));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'lavg5', $rrd_min . "g", $time, $3));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'lavg15', $rrd_min . "g", $time, $4));

    my $seconds;
    my $uptime = $1;
    if($uptime =~ /(\d+) day/)
    {
      $seconds += ($1 * 86400);
    }

    if($uptime =~ /(\d+) hr/)
    {
      $seconds += ($1 * 3600);
    }

    if($uptime =~ /(\d+) min/)
    {
      $seconds += ($1 * 60);
    }

    if($uptime =~ /(\d+):(\d+)/)
    {
      $seconds += (($1 * 3600) + ($2 * 60));
    }

    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'uptime', $rrd_min . "g", $time, $seconds));
  }
}

sub supp_uptime_child_stderr
{
}

sub supp_uptime_child_close
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  delete $heap->{running_states}->{run_uptime};
  delete $heap->{uptime_wheel};
}

#####################################################################################
############  PRTCONF  ############################################################
#####################################################################################

sub run_prtconf
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{prtconf_wheel} = POE::Wheel::Run->new
  (
    Program      => [ "/usr/sbin/prtconf -v | head -2" ],
    StdioFilter  => POE::Filter::Line->new(),
    StderrFilter => POE::Filter::Line->new(),
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_prtconf_child_stdio',
    StderrEvent  => 'supp_prtconf_child_stderr',
    CloseEvent   => "supp_prtconf_child_close",
  );
}

sub supp_prtconf_child_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

  ## prtconf -v | head -2
  #System Configuration:  Sun Microsystems  sun4u
  #Memory size: 4096 Megabytes

  if($output =~ /Memory size: (\d+) (\w+)/)
  {
    my ($count, $units) = ($1, $2);
    my $kb;
    my $time = time;

    if($units eq 'Megabytes')
    {
      $kb = $count * 1024;
    }
    elsif($units eq 'Gigabytes')
    {
      $kb = $count * 1048576;
    }

    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'memtot', '1g', $time, $kb));
  }
}

sub supp_prtconf_child_stderr
{
}

sub supp_prtconf_child_close
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  delete $heap->{running_states}->{run_prtconf};
  delete $heap->{prtconf_wheel};
}

#####################################################################################
############  NETSTAT  ############################################################
#####################################################################################

sub run_netstat
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{netstat_wheel} = POE::Wheel::Run->new
  (
    Program      => [ "/usr/bin/netstat -an -f inet -P tcp" ],
    StdioFilter  => POE::Filter::Line->new(),
    StderrFilter => POE::Filter::Line->new(),
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_netstat_child_stdio',
    StderrEvent  => 'supp_netstat_child_stderr',
    CloseEvent   => "supp_netstat_child_close",
  );
}

sub supp_netstat_child_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

  #TCP: IPv4
  #   Local Address        Remote Address    Swind Send-Q Rwind Recv-Q  State
  #-------------------- -------------------- ----- ------ ----- ------ -------
  #      *.22                 *.*                0      0 24576      0 LISTEN
  #129.219.19.30.2510         *.*                0      0 24576      0 LISTEN
  #129.219.19.30.2500   129.219.117.206.53436 16080      0 24616      0 ESTABLISHED
  #129.219.19.30.2500   129.219.117.231.40189 16080      0 24616      0 ESTABLISHED

  $output =~ s/^\s+//;

  return if $output =~ /^\s*$/;
  return if $output =~ /^TCP: IP/;
  return if $output =~ /^\s*Local Address/;
  return if $output =~ /^\-\-\-/;

  my @fields = split /\s+/, $output;

  my ($state, $local_ip, $remote_ip)  = @fields[-1, 0, 1];

  $local_ip =~ s/\.(\d+)$//;
  my $local_port = $1;

  $heap->{netstat_states}->{$state}++;

  if($state eq 'LISTEN')
  {
    $heap->{listening_ports}->{$local_port}->{$local_ip}++;
  }
  elsif($state eq 'ESTABLISHED')
  {
    $remote_ip =~ s/\.(\d+)$//;
    my $remote_port = $1;

    if(my $host = $SNAG::Dispatch::shared_data->{remote_hosts}->{ips}->{$remote_ip})
    {
      ### Only look at activity on listening ports, Ignore SSH and SNAG connections, and ignore connections to the same host
      if( $SNAG::Dispatch::shared_data->{remote_hosts}->{ports}->{$remote_port}
          && $remote_port ne '22'
          && $local_port ne '22'
          && $remote_port !~ /^133[3-5]\d$/
          && !$heap->{listening_ports}->{$local_port}
          && $host ne HOST_NAME
        )
      {
        $heap->{netstat_remote_cons}->{ $host }->{$remote_port}++;
      }
    }

    if($heap->{listening_ports}->{$local_port} && $local_port ne '22' && $local_ip ne $remote_ip)
    {
      $heap->{netstat_local_cons}->{$local_port}++;
    }
  }
}

sub supp_netstat_child_stderr
{
}

sub supp_netstat_child_close
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
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

  foreach my $host (keys %{$heap->{netstat_remote_cons}})
  {
    while( my ($port, $count) = each %{$heap->{netstat_remote_cons}->{$host}})
    {
      $kernel->post('client' => 'sysrrd' => 'load' => join $del, (HOST_NAME, 'rcon_' . $host . '_' . $port, "1g", $time, $count));
    }
  }
  delete $heap->{netstat_remote_cons};

  $SNAG::Dispatch::shared_data->{listening_ports} = delete $heap->{listening_ports};

  delete $heap->{running_states}->{run_netstat};
  delete $heap->{netstat_wheel};
}

#####################################################################################
############  DF  ############################################################
#####################################################################################

sub run_df
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{df_wheel} = POE::Wheel::Run->new
  (
    Program      => sub
                    {
                      foreach my $dev (keys %{$SNAG::Dispatch::shared_data->{mounts}})
                      {
                        next if $SNAG::Dispatch::shared_data->{mounts}->{$dev}->{type} =~ /nfs/i;
                        my $mount = $SNAG::Dispatch::shared_data->{mounts}->{$dev}->{mount};
                        my @df_output = `/usr/bin/df -k $mount`;

                        shift @df_output;

                        foreach my $df_line (@df_output)
                        {
                          print "$df_line";
                        }
                      }
                    },
    StdioFilter  => POE::Filter::Line->new(),
    StderrFilter => POE::Filter::Line->new(),
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_df_child_stdio',
    StderrEvent  => 'supp_df_child_stderr',
    CloseEvent   => "supp_df_child_close",
    CloseOnCall  => 1,
  );
}

sub run_df_nfs
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{df_nfs_wheel} = POE::Wheel::Run->new
  (
    Program      => sub
                    {
                      foreach my $dev (keys %{$SNAG::Dispatch::shared_data->{mounts}})
                      {
                        next unless $SNAG::Dispatch::shared_data->{mounts}->{$dev}->{type} =~ /nfs/i;
                        my $mount = $SNAG::Dispatch::shared_data->{mounts}->{$dev}->{mount};
                        my @df_output = `/usr/bin/df -k $mount`;

                        shift @df_output;

                        foreach my $df_line (@df_output)
                        {
                          print "$df_line";
                        }
                      }
                    },
    StdioFilter  => POE::Filter::Line->new(),
    StderrFilter => POE::Filter::Line->new(),
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_df_child_stdio',
    StderrEvent  => 'supp_df_child_stderr',
    CloseEvent   => "supp_df_nfs_child_close",
    CloseOnCall  => 1,
  );
}

sub supp_df_child_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

  ## /usr/bin/df -k
  #Filesystem            kbytes    used   avail capacity  Mounted on
  #/dev/md/dsk/d1       18217994 2421329 15614486    14%    /
  #/proc                      0       0       0     0%    /proc
  #fd                         0       0       0     0%    /dev/fd
  #mnttab                     0       0       0     0%    /etc/mnttab
  #swap                 2502456      16 2502440     1%    /var/run
  #swap                 2610160  107720 2502440     5%    /tmp
  #/dev/md/dsk/d7       18217994 6918417 11117398    39%    /backup
  #AFS                  9000000       0 9000000     0%    /afs

  my $time = time;

  my @fields = split /\s+/, $output;

  my $mount = URI::Escape::uri_escape($fields[5]);
  $fields[4] =~ s/\%//;

  $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host . "[$mount]", 'dsk_cap', '1g', $time, $fields[1]));
  $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host . "[$mount]", 'dsk_used', '1g', $time, $fields[2]));
  $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host . "[$mount]", 'dsk_pct', '1g', $time, $fields[4]));
}

sub supp_df_child_stderr
{
}

sub supp_df_child_close
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  delete $heap->{running_states}->{run_df};
  delete $heap->{df_wheel};
}
sub supp_df_nfs_child_close
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  delete $heap->{running_states}->{run_df_nfs};
  delete $heap->{df_nfs_wheel};
}

#####################################################################################
############  NETWORK DEVS  ############################################################
#####################################################################################

sub run_network_dev
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{network_dev_wheel} = POE::Wheel::Run->new
  (
    Program      => [ "/usr/bin/netstat -i" ],
    StdioFilter  => POE::Filter::Line->new(),
    StderrFilter => POE::Filter::Line->new(),
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_network_dev_stdio',
    StderrEvent  => 'supp_network_dev_stderr',
    CloseEvent   => "supp_network_dev_close",
  );
}

sub supp_network_dev_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

  #-[root@ezthumper-09]-[0.25/0.27/0.28]-49d21h35m-2010-03-05T09:00:59-
  #-[~:#]- netstat -i
  #Name  Mtu  Net/Dest      Address        Ipkts  Ierrs Opkts  Oerrs Collis Queue 
  #lo0   8232 loopback      localhost      257    0     257    0     0      0     
  #e1000g0 16298ezthumper-09  ezthumper-09   3850326760 0     853274461 0     0      0     
  #e1000g1 16298ezthumper-09-ja ezthumper-09-ja 215340647 0     14494  0     0      0     
  #e1000g2 16298ezthumper-09-jb ezthumper-09-jb 215340656 0     14461  0     0      0  
  # 0         1                    2               3      4       5    6     7      8
  #-9        -8                   -7              -6     -5      -4   -3    -2     -1

  if($output =~ /^(\S+)/)
  {
    my $int = $1;
    return if $int eq 'Name';

    my $time = time;
    my @stats = split /\s+/, $output;

    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ("$host\[$int\]", 'inpkts', $rrd_min . "d", $time, $stats[-6]));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ("$host\[$int\]", 'inerr', $rrd_min . "d", $time, $stats[-5]));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ("$host\[$int\]", 'outpkts', $rrd_min . "d", $time, $stats[-4]));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ("$host\[$int\]", 'outerr', $rrd_min . "d", $time, $stats[-3]));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ("$host\[$int\]", 'outcoll', $rrd_min . "d", $time, $stats[-2]));
  }
}

sub supp_network_dev_stderr
{
}

sub supp_network_dev_close
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  delete $heap->{running_states}->{run_network_dev};
  delete $heap->{network_dev_wheel};
}

#####################################################################################
############  PROCESS COUNT  ############################################################
#####################################################################################

sub run_proc
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  if(-e '/proc')
  {
    my $time = time;

    opendir(my $queue, "/proc");
    my @contents = readdir $queue;
    closedir $queue;
    my $count = scalar @contents - 2;

    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'proc', '1g', $time, $count));
  }

  delete $heap->{running_states}->{run_proc};
}

#####################################################################################
############  PROCESS COUNT  ############################################################
#####################################################################################

sub run_swap
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{swap_wheel} = POE::Wheel::Run->new
  (
    Program      => [ '/usr/sbin/swap -s' ],
    StdioFilter  => POE::Filter::Line->new(),
    StderrFilter => POE::Filter::Line->new(),
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_swap_stdio',
    StderrEvent  => 'supp_swap_stderr',
    CloseEvent   => "supp_swap_close",
  );
}

sub supp_swap_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

  ## swap -s
  #total: 262536k bytes allocated + 5696k reserved = 268232k used, 2572880k available

  my $time = time;

  if($output =~ /(\d+)(\w+) used, (\d+)(\w+) available/)
  {
    my ($used, $used_unit, $free, $free_unit) = ($1, $2, $3, $4);

    my $tot = $used + $free; 

    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'swaptot', $rrd_min . 'g', $time, $tot));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'swapfree', $rrd_min . 'g', $time, $free));
  }
}

sub supp_swap_stderr
{
}

sub supp_swap_close
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  delete $heap->{running_states}->{run_swap};
  delete $heap->{swap_wheel};
}


1;
