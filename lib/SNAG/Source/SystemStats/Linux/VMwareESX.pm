package SNAG::Source::SystemStats::Linux::VMwareESX;
use base qw/SNAG::Source::SystemStats::Linux/;

use POE;
use SNAG;
use URI::Escape;

my $host = HOST_NAME;
my $del = ':';

sub supp_vmstat_child_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

  #[root@idsmon SystemStats]# vmstat 5 5
  #   procs                      memory    swap          io     system         cpu
  # r  b  w   swpd   free   buff  cache  si  so    bi    bo   in    cs  us  sy  id
  # 2  0  0 635452   9580 131844 380616   2   3     2     1    2     0   1   2   2
  # 2  0  0 635452  10068 130272 382576   2  66  1402   316  317   314  73   8  19
  #
  # 1  2  3   4       5     6       7     8  9    10     11   12    13  14  15  16

  if ($output =~ /^\s+\d/ && $heap->{vmstat_count}++ >= 1)
  {
    my $time = time();
    my @stats = split /\s+/, $output;
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'memfree', "1g", $time, $stats[5]));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'membuff', "1g", $time, $stats[6]));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'memcache', "1g", $time, $stats[7]));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'swapin', "1g", $time, $stats[8]));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'swapout', "1g", $time, $stats[9]));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'blockin', "1g", $time, $stats[10]));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'blockout', "1g", $time, $stats[11]));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'intrpts', "1g", $time, $stats[12]));
    $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($host, 'contxts', "1g", $time, $stats[13]));
  }
}

my $stat_quanta = $SNAG::Source::SystemStats::Linux::stat_quanta;
my $stat_loops = $SNAG::Source::SystemStats::Linux::stat_loops;

sub run_iostat_io
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{iostat_io_count} = ();
  $heap->{iostat_io_wheel} = POE::Wheel::Run->new
  (
    Program      => [ BASE_DIR . "/iostat", "-x", $stat_quanta, $stat_loops ],
    StdioFilter  => POE::Filter::Line->new(),
    StderrFilter => POE::Filter::Line->new(),
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_iostat_io_child_stdio',
    StderrEvent  => 'supp_iostat_io_child_stderr',
    CloseEvent   => "supp_iostat_io_child_close",
  );
}

sub run_iostat_cpu
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{iostat_cpu_count} = 0;
  $heap->{iostat_cpu_wheel} = POE::Wheel::Run->new
  (
    Program      => [ BASE_DIR . "/iostat", "-c", $stat_quanta, $stat_loops ],
    StdioFilter  => POE::Filter::Line->new(),
    StderrFilter => POE::Filter::Line->new(),
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_iostat_cpu_child_stdio',
    StderrEvent  => 'supp_iostat_cpu_child_stderr',
    CloseEvent   => "supp_iostat_cpu_child_close",
  );
}


sub supp_iostat_io_child_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

  #
  #avg-cpu:  %user   %nice    %sys   %idle
  #           1.85    0.04    1.22   96.89
  #Device:  rrqm/s wrqm/s   r/s   w/s  rsec/s  wsec/s avgrq-sz avgqu-sz   await  svctm  %util
  #sda        0.01   1.53  0.13  0.77    1.12   18.62    21.94     0.00   21.27  12.25   0.11
  #sda1       0.00   0.00  0.00  0.00    0.00    0.00     4.39     0.00 2241.66 1148.55   0.00
  #sda2       0.00   0.29  0.05  0.06    0.44    2.83    29.82     0.01   73.95 167.08   0.18
  #sda3       0.01   1.24  0.07  0.72    0.68   15.78    20.84     0.01   39.70  19.14   0.15
  #sdb        0.89  10.60  0.67  5.19   12.49  127.35    23.89     0.01    2.45   1.35   0.08
  #sdb1       0.89  10.60  0.67  5.19   12.49  127.35    23.89     0.01    2.45   1.35   0.08


  #if ($output =~ /^(\w+\d+)\s+\d+\.\d+\s+/ && $heap->{iostat_io_count}->{$1}++ >= 1)
  if ($output =~ /^(\w+)\s+\d+\.\d+\s+/ && $heap->{iostat_io_count}->{$1}++ >= 1)
  {
    my $time = time();
    my @stats = split /\s+/, $output;

    ### Only look at the mounted partitions, and send the mountpoint instead of the device
    if($SNAG::Dispatch::shared_data->{mounts}->{$stats[0]})
    {
      my $mp = uri_escape( $SNAG::Dispatch::shared_data->{mounts}->{$stats[0]}->{mount} );

      $kernel->post('client' => 'sysrrd' => 'load' => join $del, ("$host\[$mp\]", 'iors', "1g", $time, $stats[3]));
      $kernel->post('client' => 'sysrrd' => 'load' => join $del, ("$host\[$mp\]", 'iows', "1g", $time, $stats[4]));
      #$kernel->post('client' => 'sysrrd' => 'load' => join $del, ("$host\[$mp\]", 'avgrqsz', "1g", $time, $stats[7]));
      #$kernel->post('client' => 'sysrrd' => 'load' => join $del, ("$host\[$mp\]", 'avgqusz', "1g", $time, $stats[8]));
      $kernel->post('client' => 'sysrrd' => 'load' => join $del, ("$host\[$mp\]", 'await', "1g", $time, $stats[9]));
      $kernel->post('client' => 'sysrrd' => 'load' => join $del, ("$host\[$mp\]", 'svctm', "1g", $time, $stats[10]));
    }
  }
}

1;
