package SNAG::Source::iptables;

use Modern::Perl;
use Config::General;
use File::Spec;
use POE qw(Component::Client::TCP);
use Data::Dumper;
use URI::Escape;
use SNAG;

use base qw/SNAG::Source/;

sub new 
{
	my $package = shift;

	$package->SUPER::new(@_);

	my %params = @_;
	my $alias = delete $params{Alias};
	my $debug = $SNAG::flags{debug};

	my $shared_data = $SNAG::Dispatch::shared_data;

	POE::Session->create
	(
		inline_states => 
		{
			_start => sub 
			{
				my ($kernel, $heap) = @_[KERNEL, HEAP];

				$heap->{epoch} = int(time() + 1);
				$heap->{next_time} = $heap->{epoch};
				while (++$heap->{next_time} % 60) { };
 
				$kernel->alias_set($alias);
				$kernel->alarm('iptables' => $heap->{next_time});
			},

			iptables => sub 
			{
				my ($kernel, $heap) = @_[KERNEL, HEAP];

				$heap->{next_time} += 60;
				$kernel->alarm($_[STATE] => $heap->{next_time});

				return if $SNAG::Dispatch::shared_data->{control}->{iptables};

				my $time = time;

				foreach my $bin ('iptables', 'ip6tables')
				{
					next unless defined $SNAG::Dispatch::shared_data->{binaries}->{$bin};
					my $path = $SNAG::Dispatch::shared_data->{binaries}->{$bin};

					if( -e $path )
					{
						my $wheel = POE::Wheel::Run->new
						(
							Program      => [ $path, '-L', '-w', '-nxv' ],
							StdioFilter  => POE::Filter::Line->new(),
							StderrFilter => POE::Filter::Line->new(),
							StdoutEvent  => 'iptables_stdout',
							StderrEvent  => 'iptables_stderr',
							CloseEvent   => 'iptables_close',
						);

                        			$heap->{wheels}->{ $wheel->ID } = { wheel => $wheel, bin => $bin, epoch => $time };

                        			$kernel->sig_child( $wheel->PID, 'sig_child' );
					}
				}
			},

			iptables_stdout => sub
			{
				my ($kernel, $heap, $result, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

				my $bin = $heap->{wheels}->{$wheel_id}->{bin};
				my $epoch = $heap->{wheels}->{$wheel_id}->{epoch};
				my $prefix = $bin eq 'ip6tables' ? 'ip6t' : 'ipt';

				if ($result =~ m/^\s{0,}(\d+)\s+(\d+)\s+.*\s+snag:([\w\d\~\-\_]+)\s+/)
				{
					$kernel->post('client' => 'sysrrd' => 'load' => join ':', (HOST_NAME, $prefix . "~$3_p", '1d', $epoch, $1));
					$kernel->post('client' => 'sysrrd' => 'load' => join ':', (HOST_NAME, $prefix . "~$3_b", '1d', $epoch, $2));
				}
			},

			iptables_stderr => sub
			{
				my ($kernel, $heap, $result, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
			},

			iptables_close => sub
			{
				my ($kernel, $heap, $wheel_id) = @_[KERNEL, HEAP, ARG0];

				delete $heap->{wheels}->{$wheel_id};
			},

			sig_child => sub
			{
				my ($kernel, $heap, $not_sure, $pid, $status) = @_[KERNEL, HEAP, ARG0, ARG1, ARG2];
				#print STDERR "unrar pid $pid exited with status $status.\n" if $args->{debug};
			},
		}
	);
}

1;
