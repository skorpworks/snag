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
use SNAG::Source::SystemStats qw/supp_netstat_child_stdio 
																 supp_netstat_child_stderr
																 supp_netstat_child_close/;
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
				$kernel->delay('vserver_netstat' => 10);
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
						next if $stats[7] =~ /^root/;
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


			vserver_netstat => sub
			{
				my ($kernel, $heap) = @_[KERNEL, HEAP];
				delete $heap->{wheelmap};
				foreach my $vs (@{$SNAG::Dispatch::shared_data->{vservers}})
				{
					$heap->{$vs} = POE::Wheel::Run->new
					(
						Program => [ "echo 'vs: $vs'; /usr/sbin/vserver $vs exec /bin/netstat -an --tcp" ],
						StdioFilter => POE::Filter::Line->new(),
						StderrFilter => POE::Filter::Line->new(),
						Conduit => 'pipe',
						StdoutEvent => 'supp_netstat_child_stdio',
						StderrEvent => 'supp_netstat_child_stderr',
						CloseEvent => 'supp_netstat_child_close',
					);
				}
			},
    }
  );
}

sub supp_netstat_child_stdio
{
	my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  return if $output =~ /^Active Internet connections/;
  return if $output =~ /^Proto/;

	if($output =~ m/^vs: (\w+)/)
	{
		$heap->{wheelmap}->{$wheel_id} = $1;
		next;
	}

  my @fields = split /\s+/, $output;

  my ($state, $remote, $local) = @fields[-1, -2, -3];

  $remote =~ s/^::ffff://;
  $local =~ s/^::ffff://;

  $local =~ s/^(::1|::|0.0.0.0)/\*/;

  my ($local_ip, $local_port) = split /:/, $local;


  if($state eq 'LISTEN')
  {
		if($local_port eq '80' || $local_port eq '443')
		{
			my $vs = $heap->{wheelmap}->{$wheel_id};
			push @{$SNAG::Dispatch::shared_data->{apache}}, $SNAG::Dispatch::shared_data->{vs}->{$vs}->{ip};
		}
  }
}

sub supp_netstat_child_stderr
{
}

sub supp_netstat_child_close
{
  my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
  my $vs = $heap->{wheelmap}->{$wheel_id};
  delete $heap->{$vs};
}

1;

