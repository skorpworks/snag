package SNAG::Source::File;
use base qw/SNAG::Source/;

use strict;
use SNAG;

use POE qw/Wheel::FollowTail/; 
use Carp qw(carp croak);

use DBM::Deep;

our ($alias, $debug, $verbose);

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
  croak "$mi needs a Source parameter" unless exists $params{Source};

  $alias = delete $params{Alias};
  my $source = delete $params{Source};
  my $options = delete $params{Options};

  foreach my $p (keys %params)
  {
    warn "Unknown parameter $p";
  }

  $debug = $SNAG::flags{debug};

  $verbose = $options->{verbose};

  my $startatend = $options->{startatend};
  my $startatendifnew = $options->{startatendifnew};

  POE::Session->create
  (
    inline_states=>
    {
      _start => sub
      {
        my ($heap, $kernel) = @_[ HEAP, KERNEL ];

        $heap->{source} = $source->{file} || $source;
        $heap->{stat_source} = $package;
        $heap->{stat_source} =~ s/\:\:/-/g;
        $heap->{stat_source} =~ s/\:\:/-/g;
        $heap->{stat_source} .=  "-";
        $heap->{stat_source} .= $alias || 'na';

        $kernel->alias_set($heap->{stat_source});

        $heap->{start} = time();

        my (%file_state);
        $heap->{file_state} = \%file_state;

        my $state_file = LOG_DIR . "/$alias.state";
          
        unless(-e $state_file)
        {
          $startatend = 1 if $startatendifnew;
        }

        tie %file_state, "DBM::Deep", $state_file;

        $kernel->state('filter' => \&{$package . '::filter'});
      
        if($startatend)
        {
          $heap->{tailer} = POE::Wheel::FollowTail->new
          (
            Filename   => $heap->{source},
            InputEvent => "filter",
            ErrorEvent => "error",
            ResetEvent => "reset",
          );
        }
        else
        {
          my $index = 0;

          my @stats = stat $heap->{source};
          my $new_size = $stats[7];
          my $new_check = join ':', @stats[0,1,3,6];

          if(!($file_state{index} && $file_state{size} && $file_state{check}) 
               || $new_size < $file_state{size} || $new_check ne $file_state{check})
          {
            $kernel->call('logger' => "log" => "Starting at beginning of file");
          }
          else
          {
            $index = $file_state{index};;
            $kernel->call('logger' => "log" => "Starting at byte index: $index");
          }

          $heap->{tailer} = POE::Wheel::FollowTail->new
          (
            Filename   => $heap->{source},
            InputEvent => "filter",
            ErrorEvent => "error",
            ResetEvent => "reset",
            Seek       => $index,
          );
        }

        $kernel->delay('sync' => 10);
        $kernel->delay('size' => 60);
        $kernel->yield('stats_update');
      },

      stats_update => sub
      {
        my ($heap, $kernel) = @_[ HEAP, KERNEL ];
        # Kludge to not run stats on the apache web log stuff until its fixed.
        return if $heap->{stat_source} =~ m/-web_(access|error)_log-/;
        my ($epoch, $uptime);
        $epoch = time();
        $uptime = $epoch - $heap->{start};
        $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, (HOST_NAME, "snagstat_uptime~" . $heap->{stat_source}, '1g', $epoch, $uptime));
        $kernel->alarm_set($_[STATE] => $epoch + 60);
      },

      error => sub
      {
        my ($kernel, $operation, $errnum, $errstr) = @_[KERNEL, ARG0 .. ARG2];
        $kernel->call('logger' => "log" => "FollowTail Error: $operation, $errnum, $errstr");
      },

      reset => sub
      {
        my ($kernel, $heap) = @_[ KERNEL, HEAP ];
        $kernel->call('logger' => "log" => "$alias log file was reset");
      }, 

      sync => sub
      {
        my ($kernel, $heap) = @_[ KERNEL, HEAP ];
        my @stats = stat $heap->{tailer}->[POE::Wheel::FollowTail::SELF_HANDLE]; 
        return unless @stats; ## File doesn't currently exist

        $heap->{file_state}->{index} = sysseek($heap->{tailer}->[POE::Wheel::FollowTail::SELF_HANDLE], 0, 1);
        $heap->{file_state}->{size} = $stats[7];
        $heap->{file_state}->{check} = join ':', @stats[0,1,3,6];

        $kernel->delay($_[STATE] => 10);
      },

      size => sub
      {
        my ($kernel, $heap) = @_[ KERNEL, HEAP ];
        my @stats = stat $heap->{tailer}->[POE::Wheel::FollowTail::SELF_HANDLE];
        return unless @stats; ## File doesn't currently exist

        $kernel->post("client" => "sysrrd" => "load" => join ':', (HOST_NAME, "file_" . $heap->{alias}, '1g', time(), $stats[7]));
        $kernel->delay($_[STATE] => 60);
      }
    }
  );
}

1;
