package SNAG::Source::Manager; 
use base qw/SNAG::Source/;

use strict;
no strict "refs";

use 5.10.0;
use feature qw(switch);

use SNAG;

use POE;
use Carp qw(carp croak);
use DBM::Deep;
use XML::Simple;
use File::Spec::Functions qw/splitpath splitdir catfile rootdir catdir catpath/;
use Data::Dumper;
use FreezeThaw qw/freeze thaw /;
use Date::Format;

my ($debug, $verbose, $alias);

$debug = $SNAG::flags{debug};
$verbose = $SNAG::flags{verbose};

my ($config, $state, $timings);

$timings = 
{
  'min_wheels'  => 5,
  'max_wheels'  => 25,
  'poll_period' => 60,
  'poll_expire' => 35,
  'tasks_per'   => 5,
};

my $delta_check;
$debug = 1;
#######################################
sub new
#######################################
{
  my $package = shift;
  $package->SUPER::new(@_);

  my $mi = $package . '->new()';

  croak "$mi requires an even number of parameters" if (@_ & 1);
  my %params = @_;

  croak "$mi needs an Alias parameter" unless exists $params{Alias};

  $alias = delete $params{Alias};
  my $options = delete $params{Options};

  foreach my $p (keys %params)
  {
    warn "Unknown parameter $p";
  }

  my $module = $package;
  $module =~ s/\:\:/\//g;
  $module .= '.pm';

  my $type = $package;
  $type =~ s/\:\:/\./g;
  $type =~ s/\:\:/\./g;
  #DEBUG: module: SNAG/Source/Manager/fping.pm
  #DEBUG: package: SNAG::Source::Manager::fping
  #DEBUG: type: SNAG.Source.Manager.fping

  eval
  {

    $state = new DBM::Deep( file => LOG_DIR . "/$type-$alias.state", autoflush => 1 ) or die "Could not open state file $type-$alias.state: $!";
  
    if ( -r CFG_DIR . "/$type-$alias.xml")
    {
      $config = XMLin(CFG_DIR . "/$type-$alias.xml") or die "Could not open $type-$alias.xml: $!"; #config file must be: <this files name>.xml
  
      $timings->{min_wheels}  = $config->{timings}->{min_wheels}  || $timings->{min_wheels};
      $timings->{max_wheels}  = $config->{timings}->{max_wheels}  || $timings->{max_wheels};
      $timings->{poll_period} = $config->{timings}->{poll_period} || $timings->{poll_period};
      $timings->{poll_expire} = $config->{timings}->{poll_expire} || $timings->{poll_expire};
      $timings->{tasks_per} = $config->{timings}->{tasks_per} || $timings->{tasks_per};
    }
  };
  if($@)
  {
    die "$package - $alias: error loading defaults: $@";
  }

  eval
  { 
    require $module;
  }; 
  if($@)
  {
    die "$package - $alias: Problem loading $module: $@";
  }
  
  print "Loaded $package!\n" if $debug;

  my ($picker, $poller, $process);
  $picker = $package . "::picker";
  $poller = $package . "::poller";
  $process = $package . "::process";

  print ref  \&$process;

  POE::Session->create
  (
    inline_states=>
    {
      _start => sub
      {
        my ($heap, $kernel) = @_[ HEAP, KERNEL ];

        $heap->{alias} = $alias;
        $heap->{stat_source} = $package;
        $heap->{stat_source} =~ s/\:\:/-/g;
        $heap->{stat_source} =~ s/\:\:/-/g;
        $heap->{stat_source} .=  "-";
        $heap->{stat_source} .= $alias || 'na';
        $kernel->alias_set($heap->{stat_source});

        $heap->{state}   = $state;
        $heap->{timings} = $timings;
        $heap->{config}  = $config;

        my $epoch = time();
        my $target_epoch = $epoch;
        while(++$target_epoch % $heap->{timings}->{poll_period}){}

        $heap->{next_time} = int ( $target_epoch );
        $heap->{start} = $heap->{next_time};
        $kernel->alarm('job_maker' => $heap->{next_time});
        $kernel->alarm('stats_update' => $heap->{next_time} + 58);
        $kernel->post("logger" => "log" =>  "$alias: DEBUG: Polling in " . ($heap->{next_time} - $epoch) . " seconds.\n") if $debug;
      },

      stats_update => sub
      {
        my ($heap, $kernel) = @_[ HEAP, KERNEL ];
        my ($epoch, $uptime);
        $epoch = time();
        $uptime = $epoch - $heap->{start};
        $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, (HOST_NAME, "snagstat_uptime~" . $heap->{stat_source}, '1g', $epoch, $uptime));
        my ($key,$value);
        while (($key,$value) = each %{$heap->{snagstat}})
        {
          $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, (HOST_NAME, "snagstat_" . $key . "~" . $heap->{stat_source}, '1g', $epoch, $value));
          $heap->{snagstat}->{$key} = 0;
        }
        $kernel->alarm_set($_[STATE] => $epoch + 60);
      },

      job_maker => \&$picker,
      #job_maker => \&$process,

      job_manager => sub
      { 
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        my ($epoch) = time();
        my $alias = $heap->{alias};
        $heap->{epoch} = $epoch;

        $kernel->sig_child(CHLD => "job_close");

        $heap->{snagstat}->{jobs} = int scalar @{$heap->{jobs}} || 0;
        $heap->{snagstat}->{wheels} = int scalar keys %{$heap->{job_wheels}} || 0;
        $heap->{snagstat}->{runningwheels} = int scalar keys %{$heap->{job_running_jobs}} || 0;

        $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_manager: currently $heap->{snagstat}->{jobs} jobs, $heap->{snagstat}->{wheels} wheels, $heap->{snagstat}->{runningwheels} running\n") if $debug;
        while (
               (! defined $heap->{job_wheels})
               || ( (scalar keys %{$heap->{job_wheels}}) < $heap->{timings}->{min_wheels} )
               || ( ($heap->{snagstat}->{jobs} > $heap->{snagstat}->{wheels} - $heap->{snagstat}->{runningwheels}) && ($heap->{snagstat}->{wheels} < $heap->{timings}->{max_wheels}) )
              )
        { 
          $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_manager: currently " . (scalar keys %{$heap->{job_wheels}}) . " wheels... starting job wheel\n") if $debug;
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
          $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_manager: currently $heap->{snagstat}->{jobs} jobs, $heap->{snagstat}->{wheels} wheels, $heap->{snagstat}->{runningwheels} running\n") if $debug;
        }

        foreach my $wheel_id (keys %{$heap->{job_wheels}})
        { 
          if ($heap->{job_busy}->{$wheel_id} == 1)
          { 
            $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_manager: job_wheel($wheel_id) busy (" . ($heap->{epoch} - $heap->{job_busy_time}->{$wheel_id}) ." seconds) with $heap->{job_running_jobs}->{$wheel_id}->{text}\n") if $debug;

            if ($heap->{job_busy_time}->{$wheel_id} <= ($heap->{epoch} - $heap->{timings}->{poll_expire}))
            { 
              $heap->{snagstat}->{killedwheels}++;
              $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_manager: kill busy wheel[$wheel_id]:processing $heap->{job_running_jobs}->{$wheel_id}->{text}\n") if $debug;
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
          $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_manager: sending ". $job->{text} ." to poller($wheel_id)\n") if $debug;
          $heap->{job_wheels}->{$wheel_id}->put($job);
        }
        $kernel->delay($_[STATE] => 10);
      },

      job_close => sub
      {
        my ($kernel, $heap, $wheel_id) = @_[KERNEL, HEAP, ARG0];

        $kernel->post("logger" => "log" => "Child $wheel_id has closed.");
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

        $Data::Dumper::Pad = "DEBUG:" if $verbose;

        print Dumper ($output) if $verbose;
        
        given($output->{status})
        {
          when(/^(JOBFINISHED|ERROR)$/)
          {
            $heap->{snagstat}->{finishedwheels}++ if $output->{status} eq 'JOBFINISHED';
            $heap->{snagstat}->{erroredwheels}++ if $output->{status} eq 'ERROR';
            $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_stdouterr: JOBFINISHED:$output->{status}:$heap->{job_running_jobs}->{$wheel_id}->{text}:$output->{message}\n") if $debug;
            if (my $job =  shift @{$heap->{jobs}})
            {
              $heap->{job_busy}->{$wheel_id} = 1;
              $heap->{job_busy_time}->{$wheel_id} = $heap->{epoch};
              $heap->{job_running_jobs}->{$wheel_id} = $job;
              $kernel->post("logger" => "log" =>  "$alias: DEBUG: job_manager: sending ". $job->{text} ." to poller($wheel_id)\n") if $debug;
              $heap->{job_wheels}->{$wheel_id}->put($job);
            }
            else
            {
              $heap->{job_busy}->{$wheel_id} = 0;
              $heap->{job_busy_start}->{$wheel_id} = '9999999999';
              delete $heap->{job_running_jobs}->{$wheel_id};
            }
          }
          when('STATS')
          {
            foreach my $statistic (@{$output->{message}})
            {
              $kernel->post('client' => 'sysrrd' => 'load' => $statistic);
              $kernel->post('logger' => 'log' => "DEBUG: $statistic") if $verbose;
            }
          }
          #rrd it
          when('LBSTATS')
          {
            my (@tuple, $stall_tuple); 
            foreach my $statistic (@{$output->{message}})
            {
              @tuple = split /:/, $statistic;
              #$host, $ds, $type, $time, $value) = split /:/, $row;
              #    0    1      2      3       4
              if( scalar @tuple == 5 )
              {
                if ($tuple[2] !~ /\d[cdCD]$/) ## always send gauges (not counter/derive)
                {
                  $kernel->post('client' => $output->{server} => 'load' => $statistic);
                  $kernel->post('logger' => 'log' => "DEBUG: $statistic") if $verbose;
                }

                elsif ( defined $delta_check->{$output->{status}}->{"$tuple[0]$tuple[1]"}->{"data"} )
                {
                  $delta_check->{$output->{status}}->{"$tuple[0]$tuple[1]"}->{"stall"} = 0;
                  $delta_check->{$output->{status}}->{"$tuple[0]$tuple[1]"}->{"sent"}  = $tuple[3];
                  $delta_check->{$output->{status}}->{"$tuple[0]$tuple[1]"}->{"data"}  = $tuple[4];
                  $kernel->post('client' => $output->{server} => 'load' => $statistic);
                  $kernel->post('logger' => 'log' => "DEBUG: $statistic") if $verbose;
                }
  
                elsif ($tuple[4] == $delta_check->{$output->{status}}->{"$tuple[0]$tuple[1]"}->{"data"})
                {
                    $delta_check->{$output->{status}}->{"$tuple[0]$tuple[1]"}->{"stall"} = 1;
                    $delta_check->{$output->{status}}->{"$tuple[0]$tuple[1]"}->{"sent"} = $tuple[3];
                }

                else
                {
                  if ( $delta_check->{$output->{status}}->{"$tuple[0]$tuple[1]"}->{"stall"} == 1
                  && $tuple[3] > $delta_check->{$output->{status}}->{"$tuple[0]$tuple[1]"}->{"sent"} )
                  {
                    $delta_check->{$output->{status}}->{"$tuple[0]$tuple[1]"}->{"stall"} = 0;
                    $stall_tuple  = "$tuple[0]:$tuple[1]:$tuple[2]:";
                    $stall_tuple .= $delta_check->{$output->{status}}->{"$tuple[0]$tuple[1]"}->{"sent"} . ":";
                    $stall_tuple .= $delta_check->{$output->{status}}->{"$tuple[0]$tuple[1]"}->{"data"};
                    $kernel->post("logger" => "log" => "stall: send $stall_tuple");
                    $kernel->post('client' => $output->{server} => 'load' => $stall_tuple);
                    $kernel->post('client' => $output->{server} => 'load' => $statistic);
                    $kernel->post('logger' => 'log' => "DEBUG: $statistic") if $verbose;
                  }
                  else
                  {
                    $delta_check->{$output->{status}}->{"$tuple[0]$tuple[1]"}->{"sent"}  = $tuple[3];
                    $delta_check->{$output->{status}}->{"$tuple[0]$tuple[1]"}->{"data"}  = $tuple[4];
                    $kernel->post('client' => $output->{server} => 'load' => $statistic);
                    $kernel->post('logger' => 'log' => "DEBUG: $statistic") if $verbose;
                  }
                }
              }
            }
          }
          #rrd it to $snagalias server
          when('CONFIG')
          {
            if(my $ref = delete $output->{dashboard})
            {
              foreach my $alert (@$ref)
              {
                $kernel->post('client' => 'dashboard' => 'load' => $alert);
              }
            }
            delete $output->{status};
            $Data::Dumper::Pad = "DEBUG: $alias:" if $verbose;
            print Dumper ($output) if $verbose;
            $kernel->post('client' => 'sysinfo' => 'load' => freeze($output));
          }
          #sysinfo it
          when('DEBUG')
          {
            $kernel->post("logger" => "log" =>  "$alias: DEBUG: $output->{message}\n") if $debug;
          }
          #log it
          when('STATUS')
          {
            $kernel->post("logger" => "log" =>  "$alias: DEBUG: host finished: $output->{host}:$output->{hostname}\n") if $debug;
            $kernel->post('client' => 'master' => 'heartbeat' => { source  => SCRIPT_NAME, host => $output->{hostname}, queue_mode => 'replace', 
               seen => time2str('%Y-%m-%d %T', time) } );
            $heap->{job_running_jobs}->{$wheel_id}->{text} =~ s/$output->{host}//;
            $heap->{job_running_jobs}->{$wheel_id}->{text} =~ s/::/:/g;
            $heap->{job_running_jobs}->{$wheel_id}->{text} =~ s/^://g;
          }
          when('DEBUGOBJ')
          {
            $Data::Dumper::Pad = "DEBUG";
            print Dumper ($output);
          }
          #dump it
          when('ALERT')
          {
            foreach my $statistic (@{$output->{message}})
            {
              $kernel->post('client' => 'sysrrd' => 'load' => $statistic);
              $kernel->post('logger' => 'log' => "DEBUG: $statistic") if $verbose;
            }
          }
          when('PROCESS')
          {
            &$process($output->{message});
          }
          when('HEARTBEAT')
          {
            foreach my $statistic (@{$output->{message}})
            {
              $kernel->post('client' => 'master' => 'heartbeat' => { source => SCRIPT_NAME, queue_mode => 'replace', host => HOST_NAME, seen => time2str('%Y-%m-%d %T', time) } );
              $kernel->post('logger' => 'log' => "DEBUG: heartbeat") if $verbose;
            }
          }
          #dashboard it
          when('DASHBOARD')
          {
            foreach my $alert (@{$output->{message}})
            {
              $kernel->post('client' => 'dashboard' => 'load' => $alert);
            }
          }
          #alert it
          when('SPAZD')
          {
            foreach my $insert (@{$output->{message}})
            {
              $kernel->post('client' => 'spazd' => 'load' => $insert);
              $kernel->post('logger' => 'log' => "DEBUG: $insert") if $verbose;
            }
          }
          when('DB')
          {
            foreach my $tuple (@{$output->{message}})
            {
              $kernel->post('logger' => 'log' => "INSERT[$output->{post}]: $tuple") if $verbose;
              $kernel->post('client' => "$output->{post}" => 'load' => $tuple);
            }
          }
          #netdisco it
          default
          {
            $Data::Dumper::Pad = "DEBUG" if $verbose;
            print Dumper ($output) if $verbose;
          }
          #log it
        }
      },
    }
  );
}

1;
