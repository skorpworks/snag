package SNAG::Source::SystemStats::Linux::Ubuntu;
use base qw/SNAG::Source::SystemStats::Linux/;

use POE;
use SNAG;
use URI::Escape;

my $host = HOST_NAME;

sub supp_iostat_io_child_stdio
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

=cut
####################################################################################################
# 2.6.25-gentoo-r7 #3 SMP Wed Feb 25 18:16:56 UTC 2009 x86_64 Intel(R) Xeon(R) CPU L5430 @ 2.66GHz GenuineIntel GNU/Linux 
Device:         rrqm/s   wrqm/s     r/s     w/s   rsec/s   wsec/s avgrq-sz avgqu-sz   await  svctm  %util
sda               0.00     0.08    0.00    0.36     0.04     6.15    17.31     0.01   41.42   9.02   0.32
0                 1        2       3       4        5        6       7         8      9       10     11

Device:         rrqm/s   wrqm/s     r/s     w/s   rsec/s   wsec/s avgrq-sz avgqu-sz   await  svctm  %util
sda              35.82     0.00   95.52    4.48  9209.95    35.82    92.46     1.03   10.47   4.54  45.37
md1               0.00     0.00    0.00    0.00     0.00     0.00     0.00     0.00    0.00   0.00   0.00

Device:         rrqm/s   wrqm/s     r/s     w/s   rsec/s   wsec/s avgrq-sz avgqu-sz   await  svctm  %util
sda            1245.71    12.97   32.93    2.79 10229.14   129.34   289.92     0.29    8.25   5.14  18.36
sdb             958.88    44.91   25.55    3.39  8076.65   389.62   292.52     0.30   10.73   5.63  16.29

####################################################################################################
=cut

  if ($output =~ /^(\w+) \s+ \d+\.\d+ \s+ \d+\.\d+ \s+/x && $heap->{iostat_io_count}->{$1}++ >= 1)
  {
    my $time = time();
    my @stats = split /\s+/, $output;

    if($SNAG::Dispatch::shared_data->{mounts}->{$stats[0]})
    {
      $mp = uri_escape( $SNAG::Dispatch::shared_data->{mounts}->{$stats[0]}->{mount} );
    }
    else
    {
      $mp = uri_escape( '/dev/' . $stats[0] );
    }

    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'iors', "1g", $time, $stats[3]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'iows', "1g", $time, $stats[4]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'iorss', "1g", $time, $stats[5]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'iowss', "1g", $time, $stats[6]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'avgrqsz', "1g", $time, $stats[7]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'avgqusz', "1g", $time, $stats[8]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'await', "1g", $time, $stats[9]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'svctm', "1g", $time, $stats[10]));
    $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ("$host\[$mp\]", 'pct_util', "1g", $time, $stats[11]));
  }
}

1;
