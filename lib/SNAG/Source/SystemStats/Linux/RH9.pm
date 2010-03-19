package SNAG::Source::SystemStats::Linux::RH9;
use base qw/SNAG::Source::SystemStats::Linux/;

use POE;
use SNAG;

my $host = HOST_NAME;
my $del = ':';

sub supp_vmstat_child_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

  #[root@webmail1 SNAG]# vmstat 5 5
  #   procs                      memory      swap          io     system      cpu
  # r  b  w   swpd   free   buff  cache   si   so    bi    bo   in    cs us sy id
  # 1  0  0  82528  12188 165056 1260564    0    0    12    14   10    17 13  4 18
  # 4  2  1  82540  13436 165060 1260868   17   19    34   194 1210  2349 43 14 43
  # 1  2  3    4      5      6       7    8    9     10    11   12    13 14 15 16 17

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

