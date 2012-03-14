package SNAG::Source::iptables;

use Modern::Perl;
use Config::General;
use File::Spec;
use POE qw(Component::Client::TCP);
use Data::Dumper;
use URI::Escape;
use SNAG;

use base qw/SNAG::Source/;

sub new {
    my $package = shift;

    $package->SUPER::new(@_);

    my %params = @_;
    my $alias  = delete $params{Alias};
    my $debug  = $SNAG::flags{debug};


    POE::Session->create(
        inline_states => {
            _start => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];

                $heap->{epoch}     = int(time() + 1);
                $heap->{next_time} = $heap->{epoch};
                while (++$heap->{next_time} % 60) { };
 
                $kernel->alias_set($alias);
                $kernel->alarm('iptables' => $heap->{next_time});
            },

            iptables => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];

                $heap->{next_time} += 60;
                $kernel->alarm($_[STATE] => $heap->{next_time});

                my $time = time;

                #   74318 572652901 NNTP       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0           tcp spt:8000 /* snag:ipt_nntp_p_s_8000 */
                #   29010 163993962 NNTP       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0           tcp spt:9000 /* snag:ipt_nntp_p_s_9000 */
                #
                #Chain NNTP (22 references)
                #    pkts      bytes target     prot opt in     out     source               destination
                #39253428 81025601206 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0           /* snag:ipt_nntp */
                #
                #Chain NNTPS (10 references)
                #    pkts      bytes target     prot opt in     out     source               destination
                #35228491 73888281945 RETURN     all  --  *      *       0.0.0.0/0            0.0.0.0/0           /* snag:ipt_nntps */
                my ($pkts, $bytes, $proto, $sessions);
                
		            foreach (`iptables -L -nxv`)
                {
                  if (m/^\s{0,}(\d+)\s+(\d+)\s+.*\s+snag:([\w\d\~\-\_]+)\s+/)
                  {
		                $kernel->post('client' => 'sysrrd' => 'load' => join ':', (HOST_NAME, "ipt~$3_p", '1d', $time, $1));
		                $kernel->post('client' => 'sysrrd' => 'load' => join ':', (HOST_NAME, "ipt~$3_b", '1d', $time, $2));
                  }
                }
            }
	      }
    );
}

1;
