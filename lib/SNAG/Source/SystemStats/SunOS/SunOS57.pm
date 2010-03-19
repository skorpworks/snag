package SNAG::Source::SystemStats::SunOS::SunOS57;
use base qw/SNAG::Source::SystemStats::SunOS/;

use POE;
use Data::Dumper;

### SunOS 5.7 doesn't support iostat -xnmp to show mount points
sub run_iostat_io
{
  my ($kernel, $heap) = @_[KERNEL, HEAP];

  delete $heap->{running_states}->{run_iostat_io};
}

1;
