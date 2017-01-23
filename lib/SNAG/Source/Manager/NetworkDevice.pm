package SNAG::Source::Manager::NetworkDevice;
use base qw/SNAG::Source::Manager/;

use strict;

BEGIN { $ENV{POE_EVENT_LOOP} = "POE::XS::Loop::Poll"; };         
use POE qw(Wheel::Run Filter::Reference Component::EasyDBI);

use Date::Format;
use SNMP::Effective;
use Data::Dumper;

use SNAG;

my ($debug, $verbose, $fullpull);
my ($snagalias, $alias, $package, $type, $parent, $module, $source);
my ($config, $state, $timings);

$debug = $SNAG::flags{debug};
$verbose = $SNAG::flags{verbose};

my $rec_sep = REC_SEP;
my ($oids, $altoids);

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

  my $module = $package;
  $module =~ s/\:\:/\//g;
  $module .= '.pm';

  my %params = @_;
  $source = delete $params{Source};

  $snagalias = delete $params{Alias};
  $snagalias = $alias . '-' . $snagalias;

  $config  = $package->config;
  $state   = $package->state;
  $timings = $package->timings;

  print Dumper $timings if $verbose;

  for my $key (keys %{$config->{snmp}})
  {
    $oids->{$config->{snmp}->{$key}->{oid}} = $key;
    $oids->{$config->{snmp}->{$key}->{altoid}} = $key if (exists $config->{snmp}->{$key}->{altoid});
    $altoids->{$config->{snmp}->{$key}->{altoid}} = $key if (exists $config->{snmp}->{$key}->{altoid});
  }

  POE::Component::EasyDBI->spawn(
    alias           => 'netdisco',
    dsn             => $source->{dsn},
    username        => $source->{username},
    password        => $source->{password},
    max_retries => -1,
  );

  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->post("logger" => "log" =>  "$snagalias: DEBUG: starting.\n") if $debug;
        $kernel->delay('query_pickables' => 5);
      },

      query_pickables => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        my $sql = eval $config->{query};
        print "Executing: $sql\n" if $verbose;

        $kernel->post('netdisco',
                       arrayhash => {
                                      sql => $sql,
                                      event => 'pickables',
                                    }
                     );
        $kernel->post("logger" => "log" =>  "$snagalias: DEBUG: queried pickables.\n") if $debug;
        $kernel->delay($_[STATE] => 3600);
      },
      pickables => sub
      {
        my ($kernel, $heap, $dbires) = @_[KERNEL, HEAP, ARG0];
        $kernel->post('logger' => 'log' => "$snagalias: DEBUG: operating on pickables.\n");

        if($dbires->{error})
        {
          print "$dbires->{error}\n";
        }
        else
        {
          my $time = time();
          $state->{pickables} = {};
          foreach my $row (@{$dbires->{result}})
          {
            unless (defined $row->{dns})
            {
              $kernel->post("logger" => "log" =>  "$snagalias: skipping host $row->{ip} without dns entry\n");
              next;
            }

            unless (defined $row->{server})
            {
              $kernel->post('logger' => 'log' => "$snagalias: skipping host $row->{ip} without server entry\n");
              next;
            }
            $state->{pickables}->{"$row->{ip}$rec_sep$row->{dns}$rec_sep$row->{name}$rec_sep$row->{snmp_comm}$rec_sep$row->{snmp_ver}"} = $time;
            $state->{host2server}->{"$row->{name}"} = $row->{server};
            $state->{host2server}->{"$row->{ip}"} = $row->{server};
            $state->{host2server}->{"$row->{dns}"} = $row->{server};
            print "VERBOSE: pickables: $row->{dns}:$row->{ip}:$row->{snmp_comm}:$row->{snmp_ver}\n" if $verbose;
          }
        }
      },
    }
  );
}

sub picker
{
  my ($heap, $kernel) = @_[ HEAP, KERNEL ];

  #alarm next run
  $heap->{next_time} = int ( $heap->{next_time} + $timings->{poll_period} );
  $kernel->alarm('job_maker' => $heap->{next_time});

  $heap->{epoch}  = time();
  $heap->{minute} = time2str("%M", $heap->{epoch});
  $heap->{hour}   = time2str("%H", $heap->{epoch});
  $heap->{seen}   = time2str("%c", $heap->{epoch});

  my ($count) = 0;
  my ($job) = 0;
  my ($recent);
  delete $heap->{jobs}[$job]->{hosts};
  delete $heap->{jobs}[$job]->{text};
  delete $heap->{jobs}[$job];
  for my $row (keys %{$state->{pickables}}) 
  {                                             
    my ($ip, $dns, $name, $snmp_comm, $snmp_ver) = split /$rec_sep/, $row;

    my $time = time();
    delete $state->{pickables}->{$row} if $state->{pickables}->{$row} < $time - 60 * 60 * 24 * 3;

    next if defined $recent->{$ip};
    $recent->{$ip} = 1;
 
    print "VERBOSE: $snagalias: $state->{pickables}->{$row} : $ip : $row\n" if $verbose;

    if ($count == 0)
    {
      delete $heap->{jobs}[$job]->{hosts};
      delete $heap->{jobs}[$job]->{text};
      delete $heap->{jobs}[$job];
    }

    push @{$heap->{jobs}[$job]->{hosts}}, $dns || $name;     
    $heap->{jobs}[$job]->{snmp_comm} = $snmp_comm;
    $heap->{jobs}[$job]->{snmp_ver}  = $snmp_ver;
    $heap->{jobs}[$job]->{text} .= ":" . $dns || $name;
    $heap->{jobs}[$job]->{hhour}     = $heap->{hour};
    $heap->{jobs}[$job]->{hmin}      = $heap->{minute};
    $heap->{jobs}[$job]->{hseen}     = $heap->{seen};
    $heap->{jobs}[$job]->{hepoch}    = $heap->{epoch};
    
    $count++;

    if ($count >= $timings->{tasks_per})
    {
      $heap->{jobs}[$job]->{text} = $heap->{hour} . $rec_sep . $heap->{minute} . $rec_sep . $heap->{seen} . $rec_sep . $heap->{jobs}[$job]->{text};

      $count = 0;
      $job++;
    }
  }                                                                                    
  $kernel->yield('job_manager');
}

sub poller
{
  binmode(STDOUT); 
  binmode(STDIN);

  $poe_kernel->stop();

  my $filter = POE::Filter::Reference->new();

  $0 =~ s/.pl$/_poller.pl/;

  my ($return, $return_filtered);

  my ($size, $raw, $message);
  $size = 4096;

  my (@repeaters, @nonrepeaters, $seen);
  for my $dsn (sort { $config->{snmp}->{$a}->{priority} <=> $config->{snmp}->{$b}->{priority} } keys %{$config->{snmp}})
  {
    if (lc $config->{snmp}->{$dsn}->{type} eq 'n')
    {
       push @nonrepeaters, $config->{snmp}{$dsn}{oid};
    }
    else
    {
      push @repeaters, $config->{snmp}->{$dsn}->{oid};
      push @repeaters, $config->{snmp}->{$dsn}->{altoid} if exists $config->{snmp}->{$dsn}->{altoid};
    }

  }

  my $step = $timings->{poll_period} / 60;

  while ( sysread( STDIN, $raw, $size ) )
  {
    my $message = $filter->get( [$raw] );
    my $job = shift @$message;
    my ($hhour, $hmin, $hseen, $ip, $host, $snmp_comm, $snmp_ver) =  split /$rec_sep/, $job->{text};

    if ($verbose)
    {
      $return = { status  => 'DEBUGOBJ', message => $job };
      $return_filtered = $filter->put( [ $return ] );

      print @$return_filtered;
      undef $return;
    }

    eval
    {
      my $stats;
      my $snmp = SNMP::Effective->new(
        max_sessions   => $timings->{tasks_per},
        master_timeout => $timings->{poll_expire}*.95,
      );

      $snmp->add(
        dest_host => $job->{hosts},
        walk      => [ @repeaters ],
        get       => [ @nonrepeaters ],
        arg            => {
            Version   => $snmp_ver || 1,
            Community => $snmp_comm || 'public',
            Timeout   => 30_000_000,
        },
        callback  => sub
        {
          my ($host, $error) = @_;
          my $hostname = lc $host->address;
          my ($data, $hold);

          $stats->{$hostname}{oids_sent} = scalar @nonrepeaters + scalar @repeaters;
          if ($error)
          {
            $return = { status  => 'ERROR', message => "$hostname failed: $error" };
            $return_filtered = $filter->put( [ $return ] );
            print @$return_filtered;
            undef $return;

            return;
          }

          my $response = $host->data;

          for my $oid (keys %$response)
          {
            my $oidstr = SNMP::Effective::make_name_oid($oid);
            my $dsn = lc $oids->{$oid};

            $stats->{$hostname}{oids_recv}++;

            for my $iid (keys %{$response->{$oid}})
            {
              $stats->{$hostname}{total_recv}++;

              if ($oidstr eq 'ifName')
              { 
                my $ifName = lc $response->{$oid}{$iid};
                $ifName =~ s/\s+//g;
                $ifName =~ s/\//_/g;
                $ifName =~ s/:/~/g;
                $hold->{names}{$iid} = $ifName;
                $stats->{$hostname}{interfaces}++;
              }
              else
              {
                if (defined $iid and defined $dsn)
                { 
                  exists $altoids->{$oid}
                         ? $data->{$dsn}{$iid}   = $response->{$oid}{$iid}
                         : $data->{$dsn}{$iid} ||= $response->{$oid}{$iid};
                }

                $hold->{operstatus}{$iid} = $response->{$oid}{$iid} if $oidstr eq 'ifOperStatus';

              }
            }

          }

          my ($dsn, $iid, $type, $dst, $epoch, $message);
          for $dsn (keys %$data)
          {
            next unless defined $source->{server} && defined $state->{host2server}{$hostname};
            $return = { status => 'LBSTATS', server => $source->{server} . '_dyn_' . $state->{host2server}{$hostname}, message => () };                                                                                            
            for $iid (keys %{$data->{$dsn}})
            {
              $type = $dst = $epoch = $message = '';

              $type = lc $config->{snmp}->{$dsn}->{type};
              $dst = lc $config->{snmp}->{$dsn}->{dst};
              $epoch = $job->{hepoch};

              next if $data->{$dsn}{$iid} eq 'NOSUCHINSTANCE';
              next if $type eq 'r' and not exists $hold->{names}{$iid};
              next if $dsn =~ /^(iftype|operreason)$/i;
              next if $hold->{operstatus}->{$iid} != 1 && lc $dsn ne 'operstat' && $type eq 'r';
              next if $type eq 'r' && $hold->{names}->{$iid} =~ /^(lo|eo|netflow|vl|nu)/i;

              $message = $type eq 'r'
                            ? join ':', ($hostname . '[' . $hold->{names}{$iid} . ']', $dsn, $step . $dst, $epoch, $data->{$dsn}{$iid})
                            : join ':', ($hostname, $dsn, ($step . $dst), $epoch, $data->{$dsn}{$iid});
              push @{$return->{message}}, $message;
            }

            $return_filtered = $filter->put( [ $return ] );
            print @$return_filtered;
            undef $return;
          }

          $return = { status => 'STATUS', host => $hostname, hostname => $hostname };
          $return_filtered = $filter->put( [ $return ] );
          print @$return_filtered unless $debug;
          undef $return;

          undef $hold;
          undef $data;
        },
      );
      $snmp->execute;

      for my $key (keys %$stats)
      {
        $return = { status => 'LBSTATS', server => $source->{server}, message => () };                                                                                            
        push @{$return->{message}}, join ':', (HOST_NAME, 'oids_recv['  . $key . '~_~' . $snagalias . ']', $step . 'd', $job->{hepoch}, $stats->{$key}{oids_recv});                 
        push @{$return->{message}}, join ':', (HOST_NAME, 'oids_sent['  . $key . '~_~' . $snagalias . ']', $step . 'd', $job->{hepoch}, $stats->{$key}{oids_sent});                 
        push @{$return->{message}}, join ':', (HOST_NAME, 'total_recv[' . $key . '~_~' . $snagalias . ']', $step . 'd', $job->{hepoch}, $stats->{$key}{total_recv});                
        push @{$return->{message}}, join ':', (HOST_NAME, 'interfaces[' . $key . '~_~' . $snagalias . ']', $step . 'd', $job->{hepoch}, $stats->{$key}{interfaces}) if exists $stats->{$key}{interfaces};

        $return_filtered = $filter->put( [ $return ] );                                                                                                                           
        print @$return_filtered;                                                                                                                                                  
        undef $return;
      }

      undef $stats;
    };

    if($@)
    {
      $return = { status  => 'ERROR', message => "$@\n" }; 
      $return_filtered = $filter->put( [ $return ] );
      print @$return_filtered;
      undef $return;
    }
    else
    {
      $return = { status  => 'JOBFINISHED', message => $job->{text} };
      $return_filtered = $filter->put( [ $return ] );
      print @$return_filtered;
      undef $return;
    }
  } # while stdin
}

1;
