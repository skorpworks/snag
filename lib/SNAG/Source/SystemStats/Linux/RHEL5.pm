package SNAG::Source::SystemStats::Linux::RHEL5;
use base qw/SNAG::Source::SystemStats::Linux/;

use POE;
use SNAG;
use URI::Escape;

my $host = HOST_NAME;

sub run_netstat
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  $heap->{netstat_wheel} = POE::Wheel::Run->new
  (
    Program      => [ "netstat -anT --tcp" ],
    StdioFilter  => POE::Filter::Line->new(),
    StderrFilter => POE::Filter::Line->new(),
    Conduit      => 'pipe',
    StdoutEvent  => 'supp_netstat_child_stdio',
    StderrEvent  => 'supp_netstat_child_stderr',
    CloseEvent   => "supp_netstat_child_close",
  );
}

sub supp_iostat_io_child_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

=cut
####################################################################################################
Linux 2.4.21-27.0.4.ELsmp (spork2)      07/17/2005

avg-cpu:  %user   %nice    %sys %iowait   %idle
0.00    0.00    0.20    0.60   99.20

Device:    rrqm/s wrqm/s   r/s   w/s  rsec/s  wsec/s    rkB/s    wkB/s avgrq-sz avgqu-sz   await  svctm  %util
sda          0.00   2.00  0.00  1.20    0.00   27.20     0.00    13.60    22.67     0.03   21.67  10.00   1.20
sda1         0.00   0.00  0.00  0.00    0.00    0.00     0.00     0.00     0.00     0.00    0.00   0.00   0.00
sda2         0.00   0.00  0.00  0.00    0.00    0.00     0.00     0.00     0.00     0.00    0.00   0.00   0.00
sda3         0.00   1.40  0.00  0.40    0.00   14.40     0.00     7.20    36.00     0.01   25.00  25.00   1.00
sda4         0.00   0.00  0.00  0.00    0.00    0.00     0.00     0.00     0.00     0.00    0.00   0.00   0.00
sda5         0.00   0.60  0.00  0.80    0.00   12.80     0.00     6.40    16.00     0.02   20.00  15.00   1.20
   0            1      2     3     4       5       6        7        8        9       10      11     12     13
####################################################################################################
####################################################################################################
[root@sporkdev SystemStats]# iostat -x 10 2
Linux 2.6.9-11.ELsmp (sporkdev)         10/28/2005

avg-cpu:  %user   %nice    %sys %iowait   %idle
           0.02    0.00    0.02    0.27   99.68

Device:    rrqm/s wrqm/s   r/s   w/s  rsec/s  wsec/s    rkB/s    wkB/s avgrq-sz avgqu-sz   await  svctm  %util
sda          0.00   0.40  0.00  2.50    0.00   23.20     0.00    11.60     9.28     0.07   27.00   4.36   1.09
  0             1      2     3     4       5       6        7        8        9       10      11     12     13
####################################################################################################
####################################################################################################
[root@javaprod21 ~]# /opt/local/SNAG/bin/iostat -x 10 2
Linux 2.6.18-92.el5 (javaprod21)        01/22/2009

avg-cpu:  %user   %nice %system %iowait  %steal   %idle
          25.66    0.00    0.66    0.00    0.00   73.69

Device:         rrqm/s   wrqm/s   r/s   w/s   rsec/s   wsec/s avgrq-sz avgqu-sz   await  svctm  %util
sda               0.00    11.08  0.00  3.73     0.00   118.43    31.78     0.00    0.89   0.08   0.03
dm-0              0.00     0.00  0.00 14.80     0.00   118.43     8.00     0.01    0.63   0.02   0.03
dm-1              0.00     0.00  0.00  0.00     0.00     0.00     0.00     0.00    0.00   0.00   0.00  
   0                 1        2     3     4        5        6        7        8       9     10     11

####################################################################################################
=cut

  if ($output =~ /^(\w+)\s+\d+\.\d+\s+/ && $heap->{iostat_io_count}->{$1}++ >= 1)
  {
    my $time = time();
    my @stats = split /\s+/, $output;

    my $mp;
    if($SNAG::Dispatch::shared_data->{mounts}->{$stats[0]})
    {
      $mp = uri_escape( $SNAG::Dispatch::shared_data->{mounts}->{$stats[0]}->{mount} );
    }
    else
    {
      $mp = uri_escape( $stats[0] );
    }

    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'iors', "1g", $time, $stats[3]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'iows', "1g", $time, $stats[4]));
    #$kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'iorkbs', "1g", $time, $stats[7]));
    #$kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'iowkbs', "1g", $time, $stats[8]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'avgrqsz', "1g", $time, $stats[7]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'avgqusz', "1g", $time, $stats[8]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'await', "1g", $time, $stats[9]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'svctm', "1g", $time, $stats[10]));
  }
}

1;
