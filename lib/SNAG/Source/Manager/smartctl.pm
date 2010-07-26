package SNAG::Source::Manager::smartctl; 
use base qw/SNAG::Source::Manager/;

use strict;

BEGIN { $ENV{POE_EVENT_LOOP} = "POE::XS::Loop::Poll"; };         
use POE qw(Wheel::Run Filter::Reference);

use Date::Format;
use Net::Nslookup;
use URI::Escape;
use Data::Dumper;

use Storable qw/dclone store retrieve/;
use FreezeThaw  qw/freeze thaw/;   

use SNAG;
  
my $rec_sep = REC_SEP;
my $host = HOST_NAME;
        
my ($debug, $verbose, $fullpull);
my ($snagalias, $alias, $package, $type, $parent, $module);
my ($config, $timings, $db_info);

$debug = $SNAG::flags{debug};
$verbose = $SNAG::flags{verbose};
$fullpull = $SNAG::flags{fullpull};

#################################
sub new
#################################
{
  my $package= shift;
  $package->SUPER::new(@_);

  $parent = $package;
  $parent =~ s/\:\:[\w\-\.]+$//;

  $alias = $package;
  $alias =~ s/.*\:\:([\w\.\-]+)$/$1/;

  $type = $package;
  $type =~ s/\:\:/\./g;
  $type =~ s/\:\:/\./g;

  $module = $package;
  $module =~ s/\:\:/\//g;
  $module .= '.pm';

  my %params = @_;
  $snagalias = delete $params{Alias};
  $snagalias = $alias . '-' . $snagalias;

  #$config  = $SNAG::Source::Manager::config;
  #$timings = $SNAG::Source::Manager::timings;


  POE::Session->create
  (
    inline_states =>
    { 
      _start => sub
      { 
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->post("logger" => "log" =>  "$snagalias: DEBUG: starting.\n") if $debug;

        $kernel->delay('build_pickables' => 5);
      },
      build_pickables => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP, ARG0];

        #$state->{pickables}->{five} = '5';
        #$state->{pickables}->{twentyfive} = '25';
        $kernel->delay('build_pickables' => 300);
      },
    }
  );
}

#sub process
#{
#  my ($heap, $kernel, $message) = @_[ HEAP, KERNEL, ARG0 ];
#  return;
#}

sub picker
{
  my ($heap, $kernel) = @_[ HEAP, KERNEL ];

$heap->{timings} =     
{                                                                                                                                                                                                                                                                             
  'min_wheels'  => 1,                                                                                                                                                                                                                                                         
  'max_wheels'  => 3,                                                                                                                                                                                                                                                        
  'poll_period' => 60,                                                                                                                                                                                                                                                        
  'poll_expire' => 35,                                                                                                                                                                                                                                                        
  'tasks_per'   => 1,                                                                                                                                                                                                                                                         
};   

  #alarm next run
  $heap->{next_time} = int ( $heap->{next_time} + $heap->{timings}->{poll_period} );
  $kernel->alarm('job_maker' => $heap->{next_time});

  $heap->{epoch}  = time();
  $heap->{minute} = time2str("%M", $heap->{epoch});
  $heap->{hour}   = time2str("%H", $heap->{epoch});
  $heap->{seen}   = time2str("%c", $heap->{epoch});

  foreach (`fdisk -l 2>&1`)    
  {                            
    if (m/^Disk \s+ (\/dev\/[sh]d[\w]+)\:/x)           
    {                         
      my $job;
      $job->{epoch}     = $heap->{epoch};
      $job->{hhour}     = $heap->{hour};
      $job->{hmin}      = $heap->{minute};
      $job->{hseen}     = $heap->{seen};
      $job->{name}      = $1;
      $job->{payload}   = $1;
      $job->{text} = $heap->{hour} . $rec_sep . $heap->{minute} . $rec_sep . $heap->{seen} . $rec_sep . "$1";
      push @{$heap->{jobs}}, $job;
    }
  }
  $kernel->yield('job_manager');
}

sub poller
{
  binmode(STDOUT); 
  binmode(STDIN); 
  my ($filter, $return, $return_filtered, $return_debug);
  $filter = POE::Filter::Reference->new();

  $0 =~ s/.pl$/_$alias.pl/;

  my ($size, $raw, $message);
  $size = 4096;

  my $cache;
  
  while ( sysread( STDIN, $raw, $size ) )
  {
    my $message = $filter->get( [$raw] );
    my $job = shift @$message;
    my ($hhour, $hmin, $hseen, $ip, $host, $snmp_comm) =  split /$rec_sep/, $job->{text};

    if ($verbose)
    { 
      $return = { 
                  "status"  => "DEBUGOBJ",
                  "message" => $job,
                };
      $return_filtered = $filter->put( [ $return ] );
      print @$return_filtered;
      $return = '';
    }

    eval
    {
      my ($disk, $device, $version, $serial, $enabled, $status, $hours, $nmec, $egdl);               
      foreach (`smartctl --all $job->{payload} 2>&1`)          
      {
        chomp;   
                 
        if (m/^Device(:)\s+(.*?)Version: (.*)$/i)                                                        
        {                                                                                                
          $device = $2;                                                                                  
          $version = $3;                                                                                 
        }                                                                                                
        elsif (m/^Device Model:\s+(.*)$/i)                                                               
        {                                                                                                
          $device = $1;                                                                                  
        }                                                                                                
        elsif (m/^Serial Number:\s+(.*)$/i)                                                              
        {                                                                                                
          $serial = $1;                                                                                  
        }                                                                                                
        elsif (m/^Firmware Version:\s+(.*)$/i)                                                           
        {                                                                                                
          $version = $1;                                                                                 
        }                                                                                                
        elsif (m/^(Device supports SMART and is Enabled|SMART support is: Enabled)/)                     
        {                                                                                                
          $enabled = 1;                                                                                  
        }                                                                                                
                                                                                                         
        elsif (m/^(SMART Health Status:|SMART overall-health self-assessment test result:)\s+(.*)$/i)    
        {                                                                                                
          $status = $2;                                                                                  
        }                                                                                                
                                                                                                         
        elsif (m/^\s+number of hours powered up\s+=\s+(.*)$/i)                                           
        {                                                                                                
          $hours = $1;                                                                                   
        }                                                                                                
                                                                                                         
        elsif (m/^\s+\d+\s+Power_On_Hours\s+.*(\d+)\s*$/i)                                               
        {                                                                                                
          $hours = $1;                                                                                   
        }                                                                                                
                                                                                                         
        elsif (m/^Non-medium error count:\s+(.*)$/i)                                                     
        {                                                                                                
          $nmec = $1;                                                                                    
        }                                                                                                
        elsif (m/^Elements in grown defect list:\s+(.*)$/i)                                              
        {                                                                                                
          $egdl = $1;                                                                                    
        }                                                                                                
      }                                                                                                                            
      if (defined $device && defined $version && defined $serial)                                                                  
      {                                                                                                                            
        $job->{out} =  "$device || $version || $serial || en:$enabled || hrs:$hours || nmec:$nmec || egdl:$egdl || status:$status"; 
      }                                                                                                                            
      else                                                                                                                         
      {                                                                                                                            
        $job->{out} = "$disk : missing data";                                                                                            
      }                                         
                                                                                                       
      #$return = { 'status'  => 'DEBUG', 'message' => "$out"};
      #$return_filtered = $filter->put( [ $return ] );
      #print @$return_filtered;
    };
    if($@)
    {
      $return = { 
                  "status"  => "ERROR",
                  "message" => "$job->{text}: $@\n",
                };
      $return_filtered = $filter->put( [ $return ] );
      print @$return_filtered;
    }
    else
    {
      $return = { 
                  "status"  => "JOBFINISHED",
                  "message" => "$job->{text} : $job->{out}",
                };
      $return_filtered = $filter->put( [ $return ] );
      print @$return_filtered;
    }
  }
}

1;
