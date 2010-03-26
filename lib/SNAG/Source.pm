package SNAG::Source;

use SNAG;
use POE; 
use POE::Session;
use DBM::Deep;
use Data::Dumper;
use FreezeThaw qw/cmpStr/;
use Storable qw/dclone/;

use POE::Session;

my $del = ':';

sub new
{
  my $package = shift;
  my %params = @_;
  $alias = $params{Alias};

  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $heap->{alias} = $alias;
        $heap->{stat_source} = $package;
        $heap->{stat_source} =~ s/\:\:/-/g;
        $heap->{stat_source} =~ s/\:\:/-/g;
        $heap->{stat_source} .=  "-";
        $heap->{stat_source} .= $alias || 'na';
        $kernel->alias_set($heap->{stat_source});

        $kernel->alias_set('source_' . $package);
        $kernel->post('logger' => 'log' => "Source starting: $package - $alias}") if $debug;

        unless ($package =~ m/Source\:\:(DailyFile|File|Manager)\:\:/)
        { 
          $kernel->post('logger' => 'log' => "Starting stats for $heap->{stat_source}") if $debug;
          $heap->{start} = time();
          $kernel->yield('stats_update');
        }
      },

      _stop => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        print "Stopping $package\n";
      },

      stats_update => sub
      {
        my ($heap, $kernel) = @_[ HEAP, KERNEL ];
        my ($epoch, $uptime);
        $epoch = time();
        $uptime = $epoch - $heap->{start};
        $kernel->post('client' => 'sysrrd' => 'load' => join RRD_SEP, (HOST_NAME, "snagstat_uptime~" . $heap->{stat_source}, '1g', $epoch, $uptime));
        $kernel->alarm_set($_[STATE] => $epoch + 60);
      },

    }
  );
}

our $sysinfo_prune_state;

sub sysinfo_prune
{
  my ($info, $options) = @_;

  my $host = $options->{host} || 'default';

  if($info = my_diff($sysinfo_prune_state->{$host}, $info))
  {
    $sysinfo_prune_state->{$host} = merge_hashref($sysinfo_prune_state->{$host}, $info);
  }

  return $info;
}

sub my_diff
{
  my ($state, $item) = @_;

  my $return;
  unless(cmpStr($state, $item) == 0)
  {
    if(ref $item eq 'HASH')
    {
      ### Check if its a base hash
      my $base_hash = 1;
      foreach my $val (values %$item)
      {
        $base_hash = 0 if ref $val;
      }

      if($base_hash)
      {
        $return = $item;
      }
      else
      {
        foreach my $key (keys %$item)
        {
          if($item->{$key})
          {
            if(my $diff = my_diff($state->{$key}, $item->{$key}) )
            {
              $return->{$key} = $diff;
            }
          }
          else
          {
            $return->{$key} = $item->{$key};
          }
        }
      }
    }
    else
    {
      $return = $item;
    }
  }

  return $return;
}

sub merge_hashref
{
  my ($ref1, $ref2) = @_;

  my $return;
  if(ref $ref1)
  {
    $return = dclone $ref1;
  }
  else
  {
    $return = $ref1;
  }

  while(my ($key, $val) = each %$ref2)
  {
    if(ref $val eq 'HASH')
    {
      $return->{$key} = merge_hashref($ref1->{$key}, $ref2->{$key});
    }
    else
    {
      $return->{$key} = $val;
    }
  }

  return $return;
}


1;

