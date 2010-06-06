package SNAG::Source::apache;
use base qw/SNAG::Source/;

use strict;
use SNAG;

use FreezeThaw qw/freeze/;
use LWP::UserAgent;
use Date::Format;

use POE;
use POE::Wheel::Run;
use Carp qw(carp croak);
use Data::Dumper;

my %scoreboard_keys =
(
  '_' => 'web_sb_waiting',
  'S' => 'web_sb_starting',
  'R' => 'web_sb_reading',
  'W' => 'web_sb_sending',
  'K' => 'web_sb_keepalive',
  'D' => 'web_sb_dns',
  'C' => 'web_sb_closing',
  'L' => 'web_sb_logging',
  'G' => 'web_sb_graceful',
  'I' => 'web_sb_idlecleanup',
  '\.' => 'web_sb_open',
);

#################################
sub new
#################################
{
  my $package = shift;
  $package->SUPER::new(@_);

  my $mi = $package . '->new()';

  croak "$mi requires an even number of parameters" if (@_ & 1);
  my %params = @_;

  croak "$mi needs an Alias parameter" unless exists $params{Alias};
  my $alias = delete $params{Alias};

  ## Set this flag if there are multiple web servers on this host
  ##   If set, the host/port string will be sent as a 'multi' to the rrd server
  my $multi_flag = delete $params{Multiple};

  foreach my $key (keys %params)
  {
    warn "Unknown parameter $key";
  }

  my $debug = $SNAG::flags{debug};

  my $rrd_dest = HOST_NAME;
  if($multi_flag)
  {
    $rrd_dest .= '[' . $alias . ']';
    $rrd_dest =~ s/:/_/g;
  }

  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        $heap->{ua} = LWP::UserAgent->new;
        $heap->{ua}->agent('SNAG Client ' . VERSION);

        $kernel->sig( CHLD => 'catch_sigchld' );

        $kernel->yield('server_stats');
        $kernel->yield('server_info');
      },

      server_stats => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->delay($_[STATE] => 60);

        if($heap->{server_stats_wheel})
        {
          $kernel->post("logger" => "log" =>  "SNAG::Source::apache: server_stats is still running, skipping");
        }
        else
        {
					$heap->{server_stats_wheel} = POE::Wheel::Run->new
					(
						Program => sub
						{
							$0 = "snagc_apache";
							my $status_url = "http://$alias/server-status?auto";
							my $get_status = $heap->{ua}->request( HTTP::Request->new(GET => $status_url) );

							if($get_status->is_success)
							{
							  my $content = $get_status->content;
								print "$content\n";
							}
							else
							{
								print STDERR "could not get $status_url\n";
							}
						},
						StdioFilter  => POE::Filter::Line->new(),
						StderrFilter => POE::Filter::Line->new(),
						StdoutEvent  => 'server_stats_stdio',
						StderrEvent  => 'stderr',
						CloseEvent   => "server_stats_close",
						CloseOnClose => 1,
          );
        }
      },

      server_stats_stdio => sub
      {
        my ($kernel, $heap, $input) = @_[KERNEL, HEAP, ARG0];

				my ($key, $val) = ($input =~ /^([\w\s]+): (.+)$/);

        my $time = time;

				if($key && $val)
				{
					if($key eq 'Total Accesses')
					{
						$kernel->post("client" => "sysrrd" => "load" => join ':', ($rrd_dest, 'web_accesses', '1d', $time, $val));
					}
					elsif($key eq 'Total kBytes')
					{
						$kernel->post("client" => "sysrrd" => "load" => join ':', ($rrd_dest, 'web_kbytes', '1d', $time, $val));
					}
					elsif($key eq 'Uptime')
					{
						$kernel->post("client" => "sysrrd" => "load" => join ':', ($rrd_dest, 'web_uptime', '1g', $time, $val));
					}
					elsif($key eq 'BusyWorkers' || $key eq 'BusyServers')
					{
						$kernel->post("client" => "sysrrd" => "load" => join ':', ($rrd_dest, 'web_busy', '1g', $time, $val));
					}
					elsif($key eq 'IdleWorkers' || $key eq 'IdleServers')
					{
						$kernel->post("client" => "sysrrd" => "load" => join ':', ($rrd_dest, 'web_idle', '1g', $time, $val));
					}
					elsif($key eq 'Scoreboard')
					{
						while( my ($key, $rrd) = each %scoreboard_keys)
						{
							my $count;
							$count++ while $val =~ /$key/g;

							if($count)
							{
								$kernel->post("client" => "sysrrd" => "load" => join ':', ($rrd_dest, $rrd, '1g', $time, $count));
							}
						}
					}
				}
			},

      stderr => sub
      {
        my ($kernel, $heap, $input) = @_[KERNEL, HEAP, ARG0];

        $kernel->post("logger" => "log" =>  "SNAG::Source::apache: $input");
      },

      server_stats_close => sub
      {
        my ($kernel, $heap, $input) = @_[KERNEL, HEAP, ARG0];

        delete $heap->{server_stats_wheel};
      },

      server_info => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->delay($_[STATE] => 3600);

        if($heap->{server_info_wheel})
        {
          $kernel->post("logger" => "log" =>  "SNAG::Source::apache: server_info is still running, skipping");
        }
        else
        {
					$heap->{server_info_wheel} = POE::Wheel::Run->new
					(
						Program => sub
						{
							$0 = "snagc_apache";
              my $info_url = "http://$alias/server-info";
              my $get_info = $heap->{ua}->request( HTTP::Request->new(GET => $info_url) );

							if($get_info->is_success)
							{
								my $content = $get_info->content;
								$content =~ s/\<[^\>]+\>//gm;
								print "$content\n";
							}
							else
							{
								print STDERR "could not get $info_url\n";
							}
						},
						StdioFilter  => POE::Filter::Line->new(),
						StderrFilter => POE::Filter::Line->new(),
						Conduit      => 'pipe',
						StdoutEvent  => 'server_info_stdio',
						StderrEvent  => 'stderr',
						CloseEvent   => "server_info_close",
						CloseOnCall  => 1,
					);
				}
      },

      server_info_stdio => sub
      {
        my ($kernel, $heap, $input) = @_[KERNEL, HEAP, ARG0];
   
        $heap->{info_content} .= "$input\n";
      },

      server_info_close => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP ];

        my $key;

        if($multi_flag)
        {
          $key = $alias . '_apache_server_info';
        }
        else
        {
          $key = 'apache_server_info';
        }


        if($heap->{info_content} ne $heap->{apache_data}->{$key})
        {
          my $info;

          $info->{host} = HOST_NAME;
          $info->{seen} = time2str("%Y-%m-%d %T", time);

          $info->{conf}->{$key} = { 'contents' => $heap->{info_content} };

          $heap->{apache_data}->{$key} = $heap->{info_content};
          ## Populate meta-info
          if($heap->{info_content} =~ m/Config File: (.*\.conf)/)
          {
            $heap->{apache_conf} = $1;
          }

          $kernel->post('client' => 'sysinfo' => 'load' => freeze($info));
        }

        delete $heap->{apache_conf};
        delete $heap->{info_content};
        delete $heap->{server_info_wheel};
      },

      catch_sigchld => sub
      {
      },

    }
  );
}


1;
