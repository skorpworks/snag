package SNAG::Source::;
use base qw/SNAG::Source/;

use strict;
use warnings;

use SNAG;
use POE;
use Storable qw/dclone store retrieve/;
use FreezeThaw  qw/freeze thaw/;
use Date::Format;
use URI::Escape;

#################################
sub new
#################################
{
  my $package = shift;
  $package->SUPER::new(@_);

  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        $kernel->sig( CHLD => 'catch_sigchld' );

        $kernel->delay('vserver_stat' => 5);
      },

      vserver_stat => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        local $/ = "\n";
				
				if(-e '/usr/sbin/vserver-stat')
				{
          foreach (`/usr/sbin/vserver-stat`)
          {
    				my @stats = split /[' ']+/, $output;
						next if $stats[7] =~ /^root/;
						$kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, ($host, 'processes_' . $stats[7], "1g", $time, $stats[1]));
						$kernel->post('client' => 'master' => 'heartbeat' => { source  => SCRIPT_NAME, host => $stats[7] , seen => time2str("%Y-%m-%d %T", time) } );
          }
  			} 
        $kernel->delay($_[STATE] => 60);
      },
    }
  );
}

1;

