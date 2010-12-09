package SNAG::BP;

use base 'ToolSet';
our @EXPORT_OK = qw ( %opt );
our $id;


BEGIN
{
  ToolSet->use_pragma( 'strict' );         # use strict;
  ToolSet->use_pragma( 'warnings' );         # use strict;

  use Getopt::Long qw(:config pass_through);
  use Sys::Hostname;
  use Sys::Syslog;
  use Proc::ProcessTable;
  use Data::Dumper::Concise;
  use Date::Format;
  use Date::Parse;
  use Digest::MD5 qw(md5_hex);
  use Cwd;
  use POE::Kernel { loop => 'POE::XS::Loop::Poll' };
  use POE;
  use POE::Filter::Reference;
  use POE::Wheel::Run;
  use Mail::Sendmail;
  use FindBin qw($Bin);
  use SNAG;
  use SNAG::Client;

  ToolSet->export(
    'Data::Dumper::Concise' => undef,   
    'Mail::Sendmail'        => undef,   
    'POE::Kernel'           => undef,
    'POE'                   => undef,
    'SNAG'                  => undef,
    'SNAG::Client'          => undef,
    'Date::Format'          => undef,
    'Date::Parse'           => undef,
    'Sys::Syslog'           => undef,
  );

  my ($args) = join ' ', @ARGV;
  %opt = ();
  GetOptions(\%opt, 'snag', 'debug', 'verbose', 'allowdup');

  $SIG{__DIE__} = sub
  {
    #found in one cron.... not sure of the purpose
    #return if $_[0] =~ /locate Encode\/ConfigLocal/;

    die @_ if $^S;
    my $host = HOST_NAME;

    my %mail = (
                 smtp    => SMTP,
                 To      => SENTDO,
                 From    => SENDTO,
                 Subject => "Whoops! $0 died on $host!",
                 Message => $_[0],
               );
    sendmail(%mail) unless $opt{debug};
    print "ERROR: " . $_[0]  . "\n" if $opt{debug};
    exit;
  };
  
  $SNAG::flags{debug} = 1 if $opt{debug};
  $SNAG::flags{verbose} = 1 if $opt{verbose};

  unless ( $opt{allowdup} )
  {
    my @res = grep {$_->pid == $$} @{(new Proc::ProcessTable)->table};
    exit(0) if grep { @res &&  $_->cmndline eq $res[0]->cmndline && $_->pid != $$ } @{(new Proc::ProcessTable)->table};
  }

  $id = md5_hex("$0 $args" . time() . int(rand(127)) );
  openlog("SNAGBP[$$]", '', 'user');
  syslog('notice', "program started => $0, args => '$args', id => $id, user => " . getlogin() . ", pwd => " . getcwd() . ", path => $Bin");
  closelog();
} # End BEGIN

END 
{
  openlog("SNAGBP[$$]", '', 'user');
  syslog('notice', "program ended => $0, id => $id");
  closelog();
}

my ($login,$pass,$uid,$gid) = getpwnam('snagsys'); if ( defined $uid )
{
  $) = $gid;
  $> = $uid;
}

logger();

my $confin = CONF;

my $client;
if(ref ($confin->{client}) eq 'HASH')
{
  $client = [$confin->{client}];
}
else
{
  $client = $confin->{client};
}

SNAG::Client->new( $client );

$SIG{INT} = $SIG{TERM} = $SIG{HUP} = sub
{
  $poe_kernel->call('logger' => 'log' => "Killed");
  my $session = $poe_kernel->get_active_session();
  my $heap = $session->get_heap();
  print Dumper $heap;

# TODO: verify cleanup of all workers
# foreach my $wheel_id (keys %{$heap->{job_wheels}})
# {
#   $heap->{job_wheels}->{$wheel_id}->kill() || $heap->{job_wheels}->{$wheel_id}->kill(9);
# }
# exit(0);

  exit;

};

sub new
{
  my ($package, $params);

  $package = shift @_;
  $params  = shift @_;
  $config  = $params->{config};
  $picker  = $params->{picker};
  $poller  = $params->{poller};
  $process = $params->{process} || sub {return;};
  $pre     = $params->{pre}     || sub {return;};
  $post    = $params->{post}    || sub {return;};

  my $debug   = $SNAG::flags{debug};
  my $verbose = $SNAG::flags{verbose};

  $config->{manage}      = 5 unless defined $config->{manage};
  $config->{min_wheels}  = 1 unless defined $config->{min_wheels};
  $config->{max_wheels}  = 2 unless defined $config->{max_wheels};
  $config->{poll_period} = 60 unless defined $config->{poll_period};
  $config->{poll_expire} = 55 unless defined $config->{poll_expire};

  my $alias = $config->{name} || 'Manager';

  ## Move these to logger?
  print "min_wheels: $config->{min_wheels}\n" if $debug;
  print "max_wheels: $config->{max_wheels}\n" if $debug;
  print "poll period: $config->{poll_period}\n" if $debug;
  print "poll expire: $config->{poll_expire}\n" if $debug;
  print "tasks per: $config->{tasks_per}\n" if $debug;

  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->alias_set($alias);
        $kernel->post("logger" => "log" =>  "$alias: DEBUG: starting.\n") if $debug;

        $kernel->sig_child(CHLD => "job_close");

        $kernel->yield('pre');

	@{$heap->{jobs}} = ();

        my ($epoch, $target_epoch);
        $epoch = time();

        $target_epoch = $epoch;
        while( ++$target_epoch % 60 ){};
        $heap->{next_time} = int ( $target_epoch );
	$kernel->alarm('stats_update' => $heap->{next_time});

        $target_epoch = $epoch;
        while(++$target_epoch % $config->{poll_period}){};
        $heap->{next_time} = int ( $target_epoch );

        unless ($config->{poll_period} == 0)
        {
          $kernel->alarm('job_maker' => $heap->{next_time});
          $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_maker firing off in " . ($heap->{next_time} - $epoch) . " seconds.\n") if $debug;
        }
        else
        {
          $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_maker firing off now seconds.\n") if $debug;
          $kernel->delay('job_maker' => 1);
        }

      },

      stats_update => sub
      {
        my ($heap, $kernel) = @_[ HEAP, KERNEL ];
        my ($epoch, $uptime);

        $epoch = time();
        $kernel->alarm($_[STATE] => $epoch + 60);

        $uptime = $epoch - $heap->{start};
        $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, (HOST_NAME, "bp_$alias~uptime", '1g', $epoch, $uptime));
        while (my ($key,$value) = each %{$heap->{snagstat}})
        {
          $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, (HOST_NAME, "bp_$alias~$key", '1g', $epoch, $value));
          $heap->{snagstat}->{$key} = 0;
        }
      },

      cya => sub 
      {
        exit;
      },

      job_manager => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        my ($epoch) = time();
        my $alias = $heap->{alias};
        $heap->{epoch} = $epoch;

        $heap->{snagstat}->{jobs} = int scalar @{$heap->{jobs}} || 0;
        $heap->{snagstat}->{wheels} = int scalar keys %{$heap->{job_wheels}} || 0;
        $heap->{snagstat}->{runningwheels} = int scalar keys %{$heap->{job_running_jobs}} || 0;

        $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_manager: currently $heap->{snagstat}->{jobs} jobs, $heap->{snagstat}->{wheels} wheels, $heap->{snagstat}->{runningwheels} running\n") if $debug;

        ## If we have no jobs queued, and no running jobs for greater than 60 seconds, close yourself
        if($heap->{snagstat}->{jobs} == 0 && $heap->{snagstat}->{runningwheels} == 0)
        {
          if($heap->{snagstat}->{done})
          {
            if(($heap->{epoch} - $heap->{snagstat}->{done}) > 60)
            {
              $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_manager: No jobs queued or running for one minute.  Goodbye!") if $debug;
              foreach my $wheel_id (keys %{$heap->{job_wheels}})
              {  
                $heap->{job_wheels}->{$wheel_id}->kill() || $heap->{job_wheels}->{$wheel_id}->kill(9);
                $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_manager: wheel($wheel_id) killed\n") if $debug;
              }
              $kernel->delay(cya => 10);
            }
          }
          else
          {
            $heap->{snagstat}->{done} = $heap->{epoch};
          }
        }
        else
        {
          delete $heap->{snagstat}->{done};
        }
        while (
               (! defined $heap->{job_wheels})
               || ( $heap->{snagstat}->{wheels} < $config->{min_wheels} )
               || ( ($heap->{snagstat}->{jobs} > $heap->{snagstat}->{wheels} - $heap->{snagstat}->{runningwheels}) && ($heap->{snagstat}->{wheels} < $config->{max_wheels}) )
              )
        {
          $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_manager: currently $heap->{snagstat}->{wheels} wheels... starting job wheel\n") if $debug;
          my $wheel;
          $wheel = POE::Wheel::Run->new
          (
             Program => \&$poller,
             StdioFilter  => POE::Filter::Reference->new(),
             CloseOnCall  => 1,
             StdoutEvent  => 'job_stdouterr',
             StderrEvent  => 'job_stdouterr',
             CloseEvent   => 'job_close',
          );
          $heap->{job_wheels}->{$wheel->ID} = $wheel;
          $heap->{job_busy}->{$wheel->ID} = 0;
          $heap->{job_busy_time}->{$wheel->ID} = '9999999999';

          $heap->{snagstat}->{jobs} = int scalar @{$heap->{jobs}} || 0;
          $heap->{snagstat}->{wheels} = int scalar keys %{$heap->{job_wheels}} || 0;
          $heap->{snagstat}->{runningwheels} = int scalar keys %{$heap->{job_running_jobs}} || 0;
        }

        foreach my $wheel_id (keys %{$heap->{job_wheels}})
        {
          if ($heap->{job_busy}->{$wheel_id} == 1)
          {
            $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_manager: wheel($wheel_id) busy (" . ($heap->{epoch} - $heap->{job_busy_time}->{$wheel_id}) ." seconds) with $heap->{job_running_jobs}->{$wheel_id}->{text}\n") if $debug;

            if ($config->{poll_expire} > 0 && $heap->{job_busy_time}->{$wheel_id} <= ($heap->{epoch} - $config->{poll_expire}))
            {
              $heap->{snagstat}->{killedwheels}++;
              $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_manager: wheel($wheel_id): kill busy wheel: $heap->{job_running_jobs}->{$wheel_id}->{text}\n") if $debug;
              $heap->{job_wheels}->{$wheel_id}->kill() || $heap->{job_wheels}->{$wheel_id}->kill(9);
              delete $heap->{job_busy}->{$wheel_id};
              delete $heap->{job_busy_time}->{$wheel_id};
              delete $heap->{job_wheels}->{$wheel_id};
              delete $heap->{job_running_jobs}->{$wheel_id};
            }
            next;
          }
          my $job;
          next unless ($job = shift @{$heap->{jobs}});
          $heap->{job_busy}->{$wheel_id} = 1;
          $heap->{job_busy_time}->{$wheel_id} = $heap->{epoch};
          $heap->{job_running_jobs}->{$wheel_id} = $job;
          $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_manager: wheel($wheel_id): sending ". $job->{text} ."\n") if $debug;
          $heap->{job_wheels}->{$wheel_id}->put($job);
        }
        $kernel->delay($_[STATE] => $config->{manage});
			},
      job_close => sub
      {
        my ($heap, $wheel_id) = @_[HEAP, ARG0];

        $kernel->post("logger" => "log" =>  "$alias: DEBUG: Child ", $wheel_id, " has finished.\n") if $debug;
        $heap->{snagstat}->{closedwheels}++;
        delete $heap->{job_wheels}->{$wheel_id};
        delete $heap->{job_busy}->{$wheel_id};
        delete $heap->{job_busy_time}->{$wheel_id};
        delete $heap->{job_running_jobs}->{$wheel_id};
      },
      job_stdouterr => sub
      {
        my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
        my $alias = $heap->{alias};

        if ($output->{status} =~ m/^(JOBFINISHED|ERROR)$/)
        {
          $heap->{snagstat}->{finishedwheels}++ if $output->{status} eq 'JOBFINISHED';
          $heap->{snagstat}->{erroredwheels}++ if $output->{status} eq 'ERROR';
          $kernel->post("logger" => "log" => "$alias: DEBUG: job_stdouterr: wheel($wheel_id): $output->{status}: $output->{message}\n") if $debug;
          $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_stdouterr: $output->{status}: $heap->{job_running_jobs}->{$wheel_id}->{text}: $output->{message}\n") if $verbose;
	  if (defined $output->{stats})
	  {
	    while ( my ($key, $value) = each(%{$output->{stats}}) ) 
	    {
	      $heap->{snagstat}->{$key} += $value;
	    }
	  }
          if (my $job =  shift @{$heap->{jobs}})
          {
            $heap->{job_busy}->{$wheel_id} = 1;
            $heap->{job_busy_time}->{$wheel_id} = $heap->{epoch};
            $heap->{job_running_jobs}->{$wheel_id} = $job;
            $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_stdouterr: wheel($wheel_id): sending ". $job->{text} ."\n") if $debug;
            $heap->{job_wheels}->{$wheel_id}->put($job);
          }
          else
          {
            $heap->{job_busy}->{$wheel_id} = 0;
            $heap->{job_busy_start}->{$wheel_id} = '9999999999';
            delete $heap->{job_running_jobs}->{$wheel_id};
          }
        }
	elsif ($output->{status} eq 'DEBUGOBJ')
        {
          print Dumper ($output);
        }
	elsif ($output->{status} eq 'PROCESS')
        {
          $kernel->yield('process', $output);
        }
        elsif ($output->{status} eq 'DEBUG')
        {
          $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_stdouterr: wheel($wheel_id): $output->{message}\n") if $debug;
        }
        else 
        {  
          print Dumper ($output) if $verbose;
        }                
      },
      job_maker => \&$picker,
      process => \&$process,
      pre => \&$pre,
      post => \&$post,
    }
  );
}

1;
