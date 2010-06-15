package SNAG::Source::vserver;
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

        $kernel->delay('vserver_stat' => 1);
				$kernel->delay('vserver_info' => 1);
      },

      vserver_stat => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        local $/ = "\n";
				
				if(-e '/usr/sbin/vserver-stat')
				{
          foreach (`/usr/sbin/vserver-stat`)
          {
    				my @stats = split (/[' ']+/, $_);
						next if $stats[7] =~ /[^(root|NAME)]/;
						$kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, (HOST_NAME, 'processes_' . $stats[7], "1g", time(), $stats[1]));
						$kernel->post('client' => 'master' => 'heartbeat' => { source  => SCRIPT_NAME, host => $stats[7] , seen => time2str("%Y-%m-%d %T", time) } );
						push @{$SNAG::Dispatch::shared_data->{vservers}}, $stats[7];
          }
  			} 
        $kernel->delay($_[STATE] => 60);
      },

			vserver_info => sub
			{
				my ($kernel, $heap) = @_[KERNEL, HEAP];
				if(-e '/usr/sbin/vserver')
				{
					foreach my $vs (@{$SNAG::Dispatch::shared_data->{vservers}})
					{
						foreach (`/usr/sbin/vserver $vs exec ifconfig -a`)
						{
							my $name;
							if(/^([\w:]+)\s+/)
							{
								$name = $1;
							}
							next unless $name =~ /.*0$/; # we want en0 or eth0 or whatever our primary is
							
							if(/inet addr:\s+([\d.]+)/)
							{
								$SNAG::Dispatch::shared_data->{vs}->{$vs}->{ip} = $1;
							}
						}
					}
				}

				$kernel->delay($_[STATE] => 3600);
			},
		}
  );
}

1;

