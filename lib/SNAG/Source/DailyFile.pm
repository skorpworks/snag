package SNAG::Source::DailyFile;
use base qw/SNAG::Source/;

use strict;
use SNAG;

use POE qw/Wheel::FollowTail Wheel::Run/; 
use Carp qw/carp croak/;

use DBM::Deep;
use Data::Dumper;

our ($config, $alias, $debug, $verbose);

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
  croak "$mi needs a Source parameter" unless exists $params{Source};

  $alias = $params{Alias};
  my $source = delete $params{Source};
  my $options = delete $params{Options};
  $debug = $SNAG::flags{debug};
  $verbose = $SNAG::flags{verbose};

  my $type = $package;                                                                                                                                                                                           
  $type =~ s/\:\:/\./g;                                                                                                                                                                                          
  $type =~ s/\:\:/\./g;

  foreach my $key (keys %params)
  {
    next if $key eq 'Alias';
    print "Unknown parameter $key" if $debug;
  }

  #$config = XMLin(CFG_DIR . "/$type-$alias.xml") or die "Could not open $package-$alias.xml: $!"; #config file must be: <this files name>.xml                                                                  
  #$timings->{min_wheels}  = $config->{timings}->{min_wheels}  || $timings->{min_wheels}; 

  my $base_dir = $source->{dir};
  croak "<dir> was not provided within source" unless $base_dir;
  unless(-d $base_dir)
  {
    print "$base_dir is not a valid directory, stopping $alias source\n" if $debug;
    return;
  }

  my $match;
  if($source->{match})
  {
    $match = qr/$source->{match}/;
  }

  my $file_match;
  if($source->{file_match})
  {
    $file_match = qr/$source->{file_match}/;
  }

  my $startatend = $options->{startatend} || $SNAG::flags{startatend};
  my $startatendifnew = $options->{startatendifnew};

  
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

        $heap->{start} = time();

        my $state_file =  LOG_DIR . "/$alias.state";

        unless(-e $state_file)
        {
          $startatend = 1 if $startatendifnew;
        }
         
        $heap->{file_state} = new DBM::Deep(file => $state_file);

        $kernel->state('filter' => \&{$package . '::filter'});

        $kernel->sig( CHLD => 'catch_sigchld' );

        unless($startatend)
        {
          foreach my $dir (keys %{$heap->{file_state}})
          {
            print "Found $dir in file_state\n" if $debug;
            if(-f $heap->{file_state}->{$dir}->{name})
            {
              $kernel->yield('open_file' => $dir, $heap->{file_state}->{$dir}->{name}, $heap->{file_state}->{$dir}->{index});
            }
            else
            {
              $kernel->call('logger' => "log" => "Dailyfile: Could not find $heap->{file_state}->{$dir}->{name}");
            }
          }
        }
        else
        {
          $kernel->call('logger' => "log" => "DailyFile: starting at end");
        }

        $kernel->yield('stats_update');
        $kernel->yield('dir_scan');
        $kernel->delay('file_check' => 10);
        $kernel->delay('sync' => 10);
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

      catch_sigchld => sub
      {
      },

      dir_scan => sub
      {
        my ($kernel, $heap) = @_[ KERNEL, HEAP ];

        $kernel->call('logger' => "log" => "DailyFile:dir_scan processing base_dir: $base_dir") if $debug;

        $heap->{find_wheel} = POE::Wheel::Run->new
        (
          Program => sub
                     {
                       use File::Find;
                          
                       find(sub
                            {
                              if(-d $File::Find::name && (!$match || $File::Find::name =~ /$match/))
                              { 
                                print "$File::Find::name\n";
                              }
                              else
                              {
                                #$kernel->call('logger' => "log" => "DailyFile:find: Skipping $_") if $debug;
                                print STDERR "DailyFile:dir_scan: Skipping $File::Find::name\n" if $debug && $verbose;
                              }
                            }, $base_dir);
                       },
          StdoutEvent  => 'add_dir',
          StderrEvent  => 'throw_err',
          CloseEvent   => "done_dir",
        );
        
        $kernel->delay($_[STATE] => 1800);
      },

      throw_err => sub
      {
        my ($kernel, $heap, $out) = @_[ KERNEL, HEAP, ARG0 ];
        $kernel->call('logger' => "log" => "DailyFile:throw_err: $out") if $debug;
      },

      add_dir => sub
      {
        my ($kernel, $heap, $dir) = @_[ KERNEL, HEAP, ARG0 ];
        $kernel->call('logger' => 'log' => "DailyFile:add_dir: $dir") if $debug;
        $heap->{dirs}->{$dir} = 1;
      },

      done_dir => sub
      {
        my ($kernel, $heap) = @_[ KERNEL, HEAP ];
        $kernel->call('logger' => 'log' => "DailyFile:dir_scan: done.") if $debug;
        delete $heap->{find_wheel};
      },

      file_check => sub
      {
        my ($kernel, $heap) = @_[ KERNEL, HEAP ];

        $kernel->call('logger' => 'log' => "DailyFile:file_check: starting") if $debug;
        foreach my $dir (keys %{$heap->{dirs}})
        {
          unless(-d $dir) 
          {
            $kernel->call('logger' => 'log' => "DailyFile:file_check: $dir no longer exists, removing") if $debug;
            delete $heap->{dirs}->{$dir};
            delete $heap->{tailer}->{$dir};
          }

          $kernel->call('logger' => 'log' => "DailyFile:file_check: processing $dir") if $debug;

          if($startatend)
          {
            my ($latest_file) = grep { $file_match ? /$file_match/ : 1 }        ## if a file_match filter exists, apply it 
                                grep { -f $_ }                                  ## filter out all non-files
                                  reverse sort <$dir/*>;  			##Get all contents of $dir in reverse sorted order
            if($latest_file)
            {
              $kernel->yield('open_file' => $dir, $latest_file, -1);
            }
          }
          else
          {
            my ($next) = grep { $_ gt $heap->{file_state}->{$dir}->{name} }     ## filter out files that are 'less than or equal to' the last file read
                         grep { -M $_ < 14 }  					## filter out all files older than 2 weeks old
                         grep { $file_match ? /$file_match/ : 1 } 		## if a file_match filter exists, apply it
                         grep { -f $_ } 					## filter out all non-files
                           sort <$dir/*>; 					## Get all contents of $dir in sorted order

            if($next)
            {
              $kernel->call('logger' => 'log' => "DailyFile:file_check: found next") if $debug;
              unless($heap->{file_state}->{$dir}->{name})
              {
                $kernel->yield('open_file' => $dir, $next, 0);
              }
              else
              {
                my $file_size = -s $heap->{file_state}->{$dir}->{name};
                if($file_size == $heap->{file_state}->{$dir}->{index})
                {
                  ### CURRENT FILE IS INACTIVE AND THERES A NEW ONE, OPEN THE NEW ONE
                  $kernel->call('logger' => 'log' => "DailyFile:file_check: current inactive") if $debug;
                  $kernel->yield('open_file' => $dir, $next, 0);
                }
              }
            }
            else
            {
              $kernel->call('logger' => 'log' => "DailyFile:file_check: done") if $debug;
            }
          }
        }
        
        $startatend = 0;
        $kernel->delay($_[STATE] => 60);
      },

      open_file => sub
      {
        my ($kernel, $heap, $dir, $file, $index) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2 ];

        delete $heap->{tailer}->{$dir};

        $kernel->call('logger' => 'log' => "DailyFile:open_file: called with file $file") if $debug;

        if($index == -1)
        {
          print "Opening $file, starting at end of file\n" if $debug;

          $heap->{tailer}->{$dir} = POE::Wheel::FollowTail->new
          (
            Filename   => $file,
            Driver     => POE::Driver::SysRW->new(BlockSize => 4096),
            InputEvent => "filter",
            ErrorEvent => "error",
          );
        }
        else
        {
          print "Opening $file, starting at byte index: $index\n" if $debug;

          $heap->{tailer}->{$dir} = POE::Wheel::FollowTail->new
          (
            Filename   => $file,
            Driver     => POE::Driver::SysRW->new(BlockSize => 4096),
            InputEvent => "filter",
            ErrorEvent => "error",
            Seek       => $index,
          );
        }

        $heap->{wheel_ids}->{$heap->{tailer}->{$dir}->ID} = $dir;

        $heap->{file_state}->{$dir}->{name} = $file;
        $heap->{file_state}->{$dir}->{index} = $index;
      },

      sync => sub
      {
        my ($kernel, $heap) = @_[ KERNEL, HEAP ];

        foreach my $dir (keys %{$heap->{tailer}})
        {
          eval
          {
            $heap->{file_state}->{$dir}->{index} = $heap->{tailer}->{$dir}->tell();
          };
          if ($@)
          {
            $kernel->call('logger' => "log" => "sync error for file $dir, is the file open?  check file permissions: $@");
          }
        }

        $kernel->delay($_[STATE] => 30);
      },
 
      error => sub
      {
        my ($kernel, $operation, $errnum, $errstr) = @_[KERNEL, ARG0 .. ARG2];
        $kernel->call('logger' => "log" => "FollowTail Error: $operation, $errnum, $errstr");
      },
    }
  );
}

1;
