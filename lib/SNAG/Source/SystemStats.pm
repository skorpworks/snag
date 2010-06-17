package SNAG::Source::SystemStats;
use base qw/SNAG::Source/;

use SNAG;
use POE;
use Data::Dumper;
use Carp qw(carp croak);

#use Time::HiRes qw(time);
use strict;

our $rrd_step; # must be 300|60
$rrd_step = $SNAG::Dispatch::shared_data->{systemstats_step};

my $run_states;
my $debug = $SNAG::flags{debug};

our %netstat_states =
(
  'BOUND'       => 'bound',
  'CLOSING'     => 'clsng',
  'CLOSED'      => 'clsd',
  'CLOSE_WAIT'  => 'clsw',
  'ESTABLISHED' => 'est',
  'FIN_WAIT1'   => 'finw1',
  'FIN_WAIT2'   => 'finw2',
  'FIN_WAIT_1'  => 'finw1',
  'FIN_WAIT_2'  => 'finw2',
  'IDLE'        => 'idle',
  'LAST_ACK'    => 'lstack',
  'LISTEN'      => 'list',
  'LISTENING'   => 'list',
  'SYN_SENT'    => 'syns',
  'SYN_RECV'    => 'synr',
  'SYN_RCVD'    => 'synr',
  'TIME_WAIT'   => 'timew',
  'UNKNOWN'     => 'unk',
);

##################################
sub new
##################################
{
  my $package = shift;
  $package->SUPER::new(@_);

  my $mi = $package . '->new()';

  croak "$mi requires an even number of parameters" if (@_ & 1);
  my %params = @_;

  foreach my $p (keys %params)
  {
    warn "Unknown parameter $p";
  }

  my $module = "SNAG/Source/SystemStats/" . OS . '/' . OSDIST . OSVER;

  eval
  {
    require $module . '.pm';
    $module =~ s/\//::/g;
  };
  if($@)
  {
    if($@ =~ /Can\'t locate/)  
   {
      $poe_kernel->post('logger' => 'log' => "SysStats: Could not find $module") if $debug;
      $module =~ s/\/\w*$//;

      eval
      {
        require $module . '.pm';
        $module =~ s/\//::/g;
      };
      if($@)
      {
        if($@ =~ /Can\'t locate/)  
        {
          $poe_kernel->post('logger' => 'log' => "SysStats: Could not find $module") if $debug;
        }
        else
        {
          $poe_kernel->post('logger' => 'log' => "SysStats: Uncaught error loading $module: $@") if $debug;
        }
        return;
      }
      else
      {
        $poe_kernel->post('logger' => 'log' => "SysStats: Loaded $module") if $debug;
      }
    }
    else
    {
      die "Uncaught error loading $module: $@";
    }
  }
  else
  {
    $poe_kernel->post('logger' => 'log' => "SysStats: Loaded $module") if $debug;
  }

  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        $kernel->sig( CHLD => 'catch_sigchld' );

        _scan_namespace($kernel, $module);

        my $target_epoch = time();
 
        unless($SNAG::flags{nowait})
        {
          while(++$target_epoch % 60){}
        }

        $heap->{next_time} = int ( $target_epoch );
        $kernel->alarm('run' => $heap->{next_time});
      },
 
      run => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->alarm($_[STATE] => $heap->{next_time} += $rrd_step);

        ### send rrds based on shared data here, no reason to fork it off the data is already present!
        if(my $cpu_count = $SNAG::Dispatch::shared_data->{cpu_count})
        {
          $kernel->post('client' => 'sysrrd' => 'load' => join ':', (HOST_NAME, 'cpucount', "1g", time, $cpu_count));
        }

        while( my ($state, $ref) = each %$run_states)
        {
          unless($heap->{running_states}->{$state})
          {
            $kernel->yield($state);
            $heap->{running_states}->{$state}->{running}++;
          }
          else
          {
            if(++$heap->{running_states}->{$state}->{stuck} > 3)
            {
              $kernel->post('logger' => 'alert' => { Subject => "SNAG::Source::SystemStats => $state stuck on " . HOST_NAME, Message => "$state has been stuck the last $heap->{running_states}->{$state}->{stuck} times.  This could be a problem!" } );
            }
          }
        }
      },

      catch_sigchld => sub
      {

      },      

      _stop => sub 
      {

      }
    }
  );
}

##################################
sub _scan_namespace 
##################################
{
  my ($kernel, $module) = @_;

  no strict;

  my %symbol_table = %{$module . '::'};
  if(my $val = $symbol_table{'ISA'})
  {
    local *ISA = $val;

    foreach my $parent (@ISA)
    {
      _scan_namespace($kernel, $parent);
    }
  }

  while(my ($key, $val) = each %symbol_table)
  {
    next unless $key =~ /^run_/ || $key =~ /^supp_/;
    local *alias = $val;

    if($key =~ /^run_/)
    {
      $kernel->post('logger' => 'log' => "SysStats: Found run state: $key") if $debug;
      $run_states->{$key} = {};
    }

    if(defined &alias)
    {
      $kernel->state($key, \&alias);
    }
  }
}
1;
