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
    'max_wheels'  => 5,          
    'poll_period' => 900,        
    'poll_expire' => 30,         
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

  $poe_kernel->stop();  

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
      #=== START OF INFORMATION SECTION ===
      #Device Model:     WDC WD30EZRS-00J99B0
      #Serial Number:    WD-WCAWZ0117762
      #Firmware Version: 80.00A80
      #User Capacity:    3,000,592,982,016 bytes
      #Device is:        Not in smartctl database [for details use: -P showall]
      #ATA Version is:   8
      #ATA Standard is:  Exact ATA specification draft version not indicated
      #Local Time is:    Thu Apr 28 19:16:07 2011 UTC
      #SMART support is: Available - device has SMART capability.
      #SMART support is: Enabled

      #=== START OF INFORMATION SECTION ===
      #Device Model:     SAMSUNG HD203WI
      #Serial Number:    S1UYJ1RZ601028
      #Firmware Version: 1AN10002
      #User Capacity:    2,000,398,934,016 bytes
      #Device is:        In smartctl database [for details use: -P show]
      #ATA Version is:   8
      #ATA Standard is:  Not recognized. Minor revision code: 0x28
      #Local Time is:    Thu Apr 28 19:18:01 2011 UTC
      #SMART support is: Available - device has SMART capability.
      #SMART support is: Enabled

      #Device: SEAGATE  ST373207LC       Version: 0002
      #Serial number: 3KT01ADH00007507DM8M
      #Device type: disk
      #Transport protocol: Parallel SCSI (SPI-4)
      #Local Time is: Thu Jun  9 18:59:55 2011 UTC
      #Device supports SMART and is Enabled
      #Temperature Warning Enabled

      foreach (`smartctl -i $job->{payload} 2>&1`)          
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
        elsif (m/^User Capacity:\s+(.*)$/i)                                                           
        {                                                                                                
          $capacity = $1;                                                                                 
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

        #  1 Raw_Read_Error_Rate     0x002f   200   200   051    Pre-fail  Always       -       0
        #  3 Spin_Up_Time            0x0027   159   159   021    Pre-fail  Always       -       9041
        #  4 Start_Stop_Count        0x0032   100   100   000    Old_age   Always       -       14
        #  5 Reallocated_Sector_Ct   0x0033   200   200   140    Pre-fail  Always       -       0
        #  7 Seek_Error_Rate         0x002e   200   200   000    Old_age   Always       -       0
        #  9 Power_On_Hours          0x0032   099   099   000    Old_age   Always       -       1363
        # 10 Spin_Retry_Count        0x0032   100   253   000    Old_age   Always       -       0
        # 11 Calibration_Retry_Count 0x0032   100   253   000    Old_age   Always       -       0
        # 12 Power_Cycle_Count       0x0032   100   100   000    Old_age   Always       -       12
        #192 Power-Off_Retract_Count 0x0032   200   200   000    Old_age   Always       -       11
        #193 Load_Cycle_Count        0x0032   198   198   000    Old_age   Always       -       7052
        #194 Temperature_Celsius     0x0022   129   120   000    Old_age   Always       -       23
        #196 Reallocated_Event_Count 0x0032   200   200   000    Old_age   Always       -       0
        #197 Current_Pending_Sector  0x0032   200   200   000    Old_age   Always       -       0
        #198 Offline_Uncorrectable   0x0030   200   200   000    Old_age   Offline      -       0
        #199 UDMA_CRC_Error_Count    0x0032   200   200   000    Old_age   Always       -       0
        #200 Multi_Zone_Error_Rate   0x0008   200   200   000    Old_age   Offline      -       0
        
        #  1 Raw_Read_Error_Rate     0x002f   100   100   051    Pre-fail  Always       -       4680
        #  2 Throughput_Performance  0x0026   252   252   000    Old_age   Always       -       0
        #  3 Spin_Up_Time            0x0023   061   061   025    Pre-fail  Always       -       11860
        #  4 Start_Stop_Count        0x0032   100   100   000    Old_age   Always       -       7
        #  5 Reallocated_Sector_Ct   0x0033   252   252   010    Pre-fail  Always       -       0
        #  7 Seek_Error_Rate         0x002e   252   252   051    Old_age   Always       -       0
        #  8 Seek_Time_Performance   0x0024   252   252   015    Old_age   Offline      -       0
        #  9 Power_On_Hours          0x0032   100   100   000    Old_age   Always       -       6333
        # 10 Spin_Retry_Count        0x0032   252   252   051    Old_age   Always       -       0
        # 11 Calibration_Retry_Count 0x0032   252   252   000    Old_age   Always       -       0
        # 12 Power_Cycle_Count       0x0032   100   100   000    Old_age   Always       -       19
        #191 G-Sense_Error_Rate      0x0022   252   252   000    Old_age   Always       -       0
        #192 Power-Off_Retract_Count 0x0022   252   252   000    Old_age   Always       -       0
        #194 Temperature_Celsius     0x0002   064   064   000    Old_age   Always       -       24 (Lifetime Min/Max 23/29)
        #195 Hardware_ECC_Recovered  0x003a   100   100   000    Old_age   Always       -       0
        #196 Reallocated_Event_Count 0x0032   252   252   000    Old_age   Always       -       0
        #197 Current_Pending_Sector  0x0032   252   252   000    Old_age   Always       -       0
        #198 Offline_Uncorrectable   0x0030   252   252   000    Old_age   Offline      -       0
        #199 UDMA_CRC_Error_Count    0x0036   200   200   000    Old_age   Always       -       0
        #200 Multi_Zone_Error_Rate   0x002a   100   100   000    Old_age   Always       -       11
        #223 Load_Retry_Count        0x0032   252   252   000    Old_age   Always       -       0
        #225 Load_Cycle_Count        0x0032   100   100   000    Old_age   Always       -       22
                                                                                                         
        #Current_Pending_Sector
        #Hardware_ECC_Recovered
        #High_Fly_Writes
        #Multi_Zone_Error_Rate
        #Offline_Uncorrectable
        #Power_Cycle_Count
        #Raw_Read_Error_Rate
        #Reallocated_Sector_Ct
        #Reallocated_Event_Count
        #Reported_Uncorrect
        #Spin_Retry_Count
        #UDMA_CRC_Error_Count
        #ATA Error Count: 5

#        elsif (m/^\s+\d+\s+Power_On_Hours\s+.*(\d+)\s*$/i)                                               
#        {                                                                                                
#          $hours = $1;                                                                                   
#        }                                                                                                
#        elsif (m/^\s+\d+\s+Multi_Zone_Error_Rate\s+.*(\d+)\s*$/i)                                               
#        {                                                                                                
#          $mzer= $1;                                                                                   
#        }                                                                                                
#                                                                                                         
#        elsif (m/^Non-medium error count:\s+(.*)$/i)                                                     
#        {                                                                                                
#          $nmec = $1;                                                                                    
#        }                                                                                                
#        elsif (m/^Elements in grown defect list:\s+(.*)$/i)                                              
#        {                                                                                                
#          $egdl = $1;                                                                                    
#        }                                                                                                
      }                                                                                                                            
      if (defined $device && defined $version && defined $serial)                                                                  
      {                                                                                                                            
         # host   | text                        | not null
         # device | text                        | not null
         # vendor | text                        | 
         # model  | text                        | 
         # rev    | text                        | 
         # serial | text                        | 
         # size   | text                        | 
         # seen   | timestamp without time zone | 
        $job->{out} =  "$device || $version || $serial || en:$enabled || hrs:$hours || nmec:$nmec || egdl:$egdl || status:$status"; 
        $job->{disk} =  { device => $device, vendor => $vendor
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
