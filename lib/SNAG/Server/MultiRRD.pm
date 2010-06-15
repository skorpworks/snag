package SNAG::Server::RRD; 
use base qw(SNAG::Server);

use strict;
use SNAG;
use Time::HiRes;
use POE;
use Carp qw(carp croak);
use Devel::Size qw(total_size);;

use POE::Component::EasyDBI;
use RRDTool::OO;
use RRDs;
use FileHandle;
use Data::Dumper;
use File::Basename;
use XML::Simple;
use File::Path;
use File::Spec;
use URI::Escape;
#use Cache::FastMmap::Tie;
=cut
my $rec_sep = REC_SEP;

my $debug = $SNAG::flags{debug};
my $verbose = $SNAG::flags{verbose};

my ($rrd, $cache, $stats, $stat_ref, @scan_queue);
my {$fc, %cache);

my $MAX_LOADERS = 4;

################################
sub new
################################
{
  my $type = shift;
  $type->SUPER::new(@_);

  my %params = @_; 
  my $alias = delete $params{Alias};
  my $args = delete $params{Args};

  croak "Args must be a hashref" if ref $args ne 'HASH';
  croak "Args must contain values for 'dir', 'dsn', 'user', and 'pw'" unless ($args->{dir} && $args->{dsn} && $args->{user} && $args->{pw});
  
  my $rrd_base_dir = $args->{dir};
  $rrd_base_dir =~ s/\/$//;  ### REMOVE TRAILING SLASH ON DIR TO AVOID PROBLEMS
   

  my $host_name = HOST_NAME;
  my $table = 'host_to_ds';

  my %valid_types = ( '1d' => 1, '5d' => 1, '15d' => 1, 
                      '1da' => 1, '5da' => 1, '15da' => 1, 
                      '1c' => 1, '5c' => 1, '15c' => 1,
                      '1ca' => 1, '5ca' => 1, '15ca' => 1,
                      '1g' => 1, '5g' => 1, '15g' => 1,
                      '1ga' => 1, '5ga' => 1, '15ga' => 1,
                    );

#  $fc = tie %cache, 'Cache::FastMmap::Tie', 
#                    (
#                       share_file => "/var/lib/SNAG/$alias.mmap",
#                       cache_size => "250M",
#                       expire_time=> "10m",
#                    );

  POE::Component::EasyDBI->spawn
  (
    alias           => 'dbi',
    dsn             => $args->{dsn},
    username        => $args->{user},
    password        => $args->{pw},
    max_retries     => -1,
    connected       => ['dbi_helper', 'conn_handler'],
    connect_error   => ['dbi_helper', 'conn_err_handler'],
  );

  POE::Session->create ## EasyDBI states/handlers
  (
    inline_states =>
    {
      _start => sub
      {
        $_[KERNEL]->alias_set('dbi_helper');
      },

      update_query => sub
      {
        my ($kernel, $host, $multi, $ds, $epoch) = @_[KERNEL, ARG0, ARG1, ARG2, ARG3 ];
        $multi = '' unless $multi;

        $kernel->post("logger" => "log" => "SCAN:uq: Updating db: $host_name, $host, $multi, $ds, $epoch\n") if $debug;
        $kernel->post
        (
          'dbi',
          do =>
          {
            sql => 
              qq{
                update $table 
                  set epoch = ? 
                  where server = ? and host = ? and multi = ? and ds = ?
              },      
            placeholders => [ $epoch, $host_name, $host, $multi, $ds ],
            event => 'update_query_handler',
          },
        );
      },

      update_query_handler => sub
      {
        my ($kernel, $res) = @_[KERNEL, ARG0];

        if($res->{error})
        {
          my $rrd_tuple = join ':', @{$res->{placeholders}};
          $kernel->post("logger" => "log" => "SCAN:uqh: Error: $res->{error} on $rrd_tuple\n") if $debug;
        }
        else
        {
          unless($res->{rows} > 0)
          {
            $kernel->yield('insert_query' => @{$res->{placeholders}})
          }
        }
      },

      insert_query => sub
      {
        my ($kernel, $rrd_host, $host, $multi, $ds, $epoch) = @_[KERNEL, ARG1, ARG2, ARG3, ARG4, ARG0];
        $multi = '' unless $multi;

        $kernel->post("logger" => "log" => "SCAN:iq: Inserting db: $rrd_host, $host, $multi, $ds, $epoch\n") if $debug;
        $kernel->post
        (
          'dbi',
          do =>
          {
            sql => 
              qq{
                insert into $table (server, host, multi, ds, epoch) values(?, ?, ?, ?, ?)
              },
            placeholders => [ $rrd_host, $host, $multi, $ds, $epoch ],
            event => 'insert_query_handler',
          },
        );
      },

      insert_query_handler => sub
      {
        my ($kernel, $res) = @_[KERNEL, ARG0];

        if($res->{error})
        {
          my $rrd_tuple = join ':', @{$res->{placeholders}};
          $kernel->post("logger" => "log" => "SCAN:iqh: Error: $res->{error} on $rrd_tuple\n") if $debug;
        }
        else
        {
          my $rrd_tuple = join ':', @{$res->{placeholders}};
          unless($res->{rows} > 0)
          {
            ###DELETE THIS LATER
            $kernel->post("logger" => "log" => "SCAN:easydbi: Error Insert/Update db: $rrd_tuple\n") if $debug;
          }
        }
      },

      conn_handler => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $heap->{connected} = 1;
        if (defined($heap->{disconnect_time}))
        {
          $kernel->post("logger" => "log" => "EASYDBI: Connected to db - was down for " . (time() - $heap->{disconnect_time})); 
         delete $heap->{disconnect_time};
        }
        else
        {
          $kernel->post("logger" => "log" => "EASYDBI: Connected to db"); 
        }
      },

      conn_err_handler => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $heap->{connected} = 0;
        $heap->{disconnect_time} = time() unless defined($heap->{disconnect_time});
        $kernel->post("logger" => "log" => "EASYDBI: Could not connect to db\n"); 
      },
    }
  );


  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
        my ($heap, $kernel) = @_[HEAP, KERNEL];
        $kernel->alias_set('object');

        unless(-d $rrd_base_dir)
        {
          mkdir $rrd_base_dir, 0770 and $kernel->post("logger" => "log" => "START: Creating $rrd_base_dir");
          system "chgrp nobody $rrd_base_dir";
        }



        my $target_epoch = time();
        print "Current epoch: $target_epoch\n" if $debug;
        while(++$target_epoch % 60){}
        print "Target epoch: $target_epoch\n" if $debug;
        $heap->{stats_next_time} = int ( $target_epoch + 60 );
        $kernel->alarm('stats' => $heap->{stats_next_time});

        #no longer needed since there are crons to accomplish this.
        #$kernel->delay('scan_init' => 14400);

        $kernel->delay('scan' => 60);

        $kernel->yield('loader_start');
        $kernel->yield('build_threshholds');
      },

      build_threshholds => sub
      {
        my ($heap, $kernel) = @_[HEAP, KERNEL];
        my ($base_dir, $xs, $ref);

        $base_dir = BASE_DIR;
        $kernel->post("logger" => "log" => "DASHBOARD: build_threshholds: loading $base_dir/RULES.xml\n");

        eval
        {
          $xs = XML::Simple->new(ForceArray => 1, KeepRoot => 0);
          $ref = $xs->XMLin("$base_dir/RULES.xml") or die "$!";
        };
        if ($@)
        {
          $kernel->post("logger" => "log" => "DASHBOARD: build_threshholds: failed loading $base_dir/RULES.xml : $@\n");
        }
        else
        {
          $heap->{threshholds} = $ref;
          my ($xmlstring) = $xs->XMLout($heap->{threshholds});
          my (@xml) = split /\n/, $xmlstring;
          foreach my $line (@xml) { $kernel->post("logger" => "log" => "DASHBOARD: build_threshholds: $line"); }
        }
      },

      scan_init => sub
      {
        my ($heap, $kernel) = @_[HEAP, KERNEL];
   
        (@scan_queue) = sort keys %{$rrd};
        $kernel->post("logger" => "log" => "SCANINIT: " . scalar @scan_queue . " objects\n");
        #$kernel->delay('scan_init' => 86400);
      },

      scan => sub
      { 
        my ($heap, $kernel) = @_[HEAP, KERNEL];

        if ($#scan_queue < 0)
        {
          $kernel->post("logger" => "log" => "SCAN: empty queue\n") if $debug;
          $kernel->delay($_[STATE] => 60);
          return 
        }

        $kernel->post("logger" => "log" => "SCAN: starting on " . scalar @scan_queue . " objects\n");

        my ($host_multi, $host, $multi, $val, $i);
        TOP:    for ($i = 0; $i <= 10; $i++)
        {
          $kernel->post("logger" => "log" => "SCAN: processing $scan_queue[0]\n") if $debug;
          $host_multi = $scan_queue[0];
          $val = $rrd->{$scan_queue[0]};

          $multi = '';
          $host = $host_multi unless (($host, $multi) = $host_multi =~ /(.+)\[(.+)\]$/);

          my ($ds, $obj, $seen);
          while (($ds, $obj) = each %$val)
          {
            eval { $seen = $obj->last; };

            if($@) { delete $rrd->{$host_multi}->{$ds}; } ###THE RRD MUST HAVE BEEN DELETED 
            else
            {
              eval  
              {
                $kernel->post('dbi_helper' => 'update_query' => $host, $multi, $ds, $seen );
              }
            }
            $stats->{easydbi}->{scan}++; 
          } ### end while loop
          shift @scan_queue;
          $kernel->post("logger" => "log" => "SCAN: " . scalar @scan_queue . " objects in scan_queue\n") if $debug;
          last TOP if $#scan_queue < 0;
        } ### end for loop

        if ($#scan_queue >= 0)
        {
          $kernel->post("logger" => "log" => "SCAN: delay\n") if $debug;
          $kernel->delay($_[STATE] => 10);
        }
        else
        {
          $kernel->post("logger" => "log" => "SCAN: sleep\n") if $debug;
          $kernel->delay($_[STATE] => 60);
        }
      },

      stats => sub
      {
        my ($heap, $kernel) = @_[HEAP, KERNEL];

        $heap->{stats_next_time} += 60;
        $kernel->alarm('stats' => $heap->{stats_next_time});

        $stat_ref = ();

        my $stat_prefix = HOST_NAME . "[$alias]";
        my $time = time();
        foreach my $stat (keys %{$stats->{stats}})
        {
            push @{$stat_ref}, $stat_prefix . ":rrd_$stat:1g:$time:" . $stats->{stats}->{$stat};
            $stats->{stats}->{$stat} = 0;
        }
        push @{$stat_ref}, $stat_prefix . ":rrd_hosts:1g:$time:" . keys(%{$stats->{hosts}});
        push @{$stat_ref}, $stat_prefix . ":rrd_multi:1g:$time:" . keys(%{$stats->{multi}});
        delete $stats->{hosts};
        delete $stats->{multi};

        push @{$stat_ref},  $stat_prefix . ":SNAGs_scan:1g:$time:$stats->{easydbi}->{scan}";
        $stats->{easydbi}->{scan} = 0;

        push @{$stat_ref}, $stat_prefix . ":SNAGs_parcel:1g:$time:" . ($SNAG::Server::server_data->{parcels} + 0);
        $SNAG::Server::server_data->{parcels} = 0;
        push @{$stat_ref}, $stat_prefix . ":SNAGs_cons:1g:$time:" . ($SNAG::Server::server_data->{conn} + 0);
        $SNAG::Server::server_data->{conn} = 0;
        push @{$stat_ref}, $stat_prefix . ":SNAGs_conn:1g:$time:" . ((scalar keys %{$SNAG::Server::server_data->{ips}}) + 0);

        push @{$stat_ref}, $stat_prefix . ":SNAGs_mem_rrd:1g:$time:" . (total_size($rrd) + 0);
        push @{$stat_ref}, $stat_prefix . ":SNAGs_mem_stats:1g:$time:" . (total_size($stats) + 0);
        push @{$stat_ref}, $stat_prefix . ":SNAGs_mem_heap:1g:$time:" . (total_size($heap) + 0);
        push @{$stat_ref}, $stat_prefix . ":SNAGs_mem_scanqueue:1g:$time:" . (total_size(\@scan_queue) + 0);

        $kernel->yield('load' => $stat_ref);
      },

      loader_start => sub
      {
        for (my $i = 1; $i <= $MAX_LOADERS; $i++)
        {
          my $wheel = POE::Wheel::Run->new
          (
             Program => \&loader,
             StdoutEvent => 'loader_stdout',
             StderrEvent => 'loader_stderr',
             CloseEvent => 'loader_close',
            );
          $heap->{loaders}->{$wheel->ID} = $wheel;
        }
      },

      load => sub
      {
        my ($heap, $kernel, $parcel) = @_[HEAP, KERNEL, ARG0];

        #my ($hostkey, $ds, $type, $time, $value, $host, $dbevent, $threshhold);

        my ($part, $remain, $chunk, $ticker);

        $part   = scalar @{$parcel} / $MAX_LOADERS;
        $remain = scalar @{$parcel} % $MAX_LOADERS;
        
        $chunk = $part + $remain;
        
        foreach my $wheel (keys %{$heap->{loaders}})
        {
          $heap->{loaders}->{$wheel}->put( split(${@parcels}, 0, $chunk) );
          $cache{$wheel} = 1;
          $chunk = $part;
        }
        
        while (scalar %cache > 0)
        {
          $ticker++; 
        }

        return 0;
      },

      loader_stdout => sub
      {

        my ($hostkey, $ds, $type, $time, $value, $host, $dbevent, $threshhold);

        eval ## create $rrd->{$hostkey}->{$ds} entry
        {
          if ( (! defined $rrd->{$hostkey}->{$ds}) && $heap->{threshholds}->{$ds})
          {
            $rrd->{$hostkey}->{$ds} = RRDTool::OO->new( file => "$rrd_base_dir/$host/$multi/$ds.rrd");
          }
        };

        if ($heap->{threshholds}->{$ds}) ## THRESHOLDS
        {
          $kernel->post("logger" => "log" => "DASHBOARD: $hostkey:$ds entered") if $debug;
          if ($type =~ /\d[c|d]/i)
          {
            eval
            {
              $rrd->{$hostkey}->{$ds}->fetch_start(cfunc => "LAST", start => ($time-10), end => ($time-1));
              ($dbevent->{'time'}, $dbevent->{'value'}) = $rrd->{$hostkey}->{$ds}->fetch_next();
            };   
            if($@)
            {
            }
          }
          else
          {
            $dbevent->{'time'} = $time;
            $dbevent->{'value'} = $value;
          }
          foreach $threshhold (@{$heap->{threshholds}->{$ds}}) ## check thresholds for ds
          {
            $dbevent->{message} = '';
            $dbevent->{full} = '';
            $kernel->post("logger" => "log" => "DASHBOARD: $hostkey:$ds ($threshhold->{'type'}:$threshhold->{'limit'}) $dbevent->{'value'}") if $debug;
            if ($threshhold->{type} eq 'range' && $dbevent->{'value'} <= $threshhold->{high} &&  $dbevent->{'value'} >= $threshhold->{low})
            {
              $dbevent->{full} = "$threshhold->{alert} ($threshhold->{low} < $dbevent->{'value'} <  $threshhold->{high})"; 
            }
            if ($threshhold->{type} eq 'ceiling' && $dbevent->{'value'} >= $threshhold->{limit})
            {
              $dbevent->{full} = "$threshhold->{alert} ($dbevent->{'value'} > $threshhold->{limit})";
            }
            elsif ($threshhold->{type} eq 'floor' && $dbevent->{'value'} <= $threshhold->{limit})
            {
              $dbevent->{full} = "$threshhold->{alert} ($dbevent->{'value'} < $threshhold->{limit})";
            }
            elsif ($threshhold->{type} eq 'drop')
            {
              if (defined $heap->{dashboard_store}->{$host}->{$ds} &&  $dbevent->{'value'} < $heap->{dashboard_store}->{$host}->{$ds})
              {
                $dbevent->{full} = "$threshhold->{alert} ($dbevent->{'value'} < $heap->{dashboard_store}->{$host}->{$ds})"; 
              }
              $heap->{dashboard_store}->{$host}->{$ds} = $dbevent->{'value'};
            } 
            elsif ($threshhold->{type} eq 'ratio')
            {
              if (defined $heap->{dashboard_store}->{$host}->{$threshhold->{denom}})
              {
                unless ($dbevent->{'value'} <=0 || $heap->{dashboard_store}->{$host}->{$ds} <= 0)
                {
                  $dbevent->{full} = "$threshhold->{alert} ($dbevent->{'value'} < $threshhold->{limit})" if (($dbevent->{'value'}/$heap->{dashboard_store}->{$host}->{denom}) <= $threshhold->{ratio});
                }
              }
            }
            elsif ($threshhold->{type} eq 'store')
            {
              $heap->{dashboard_store}->{$host}->{$ds} = $dbevent->{'value'};
            }
            if ($dbevent->{full} && $dbevent->{full} ne '')
            {
              $dbevent->{param} =  "pvHost=$host&pvDS=$ds";
              $dbevent->{param} .= "&pvMulti=$multi" if (defined $multi && $multi ne '');
              $dbevent->{full} = uri_unescape($multi) . " $dbevent->{full}"; 
              $dbevent->{'time'} = scalar(localtime($time));
              $dbevent->{message} = join $rec_sep, ('events', $host, 'sysrrd', $threshhold->{type}, $threshhold->{alert}, $dbevent->{full}, $dbevent->{param}, $dbevent->{'time'});
              $kernel->post("logger" => "log" => "DASHBOARD: $dbevent->{message}") if $debug;
              $kernel->post('client' => 'dashboard' => 'load' => $dbevent->{message});
            }
          } ### foreach
        } ### if ($heap->{threshholds}->{$ds})

        my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
        print "writenetd($heap->{writenet_wheel_id}->{$wheel_id}): $heap->{writenet_wheel_dev}->{$wheel_id}: $output\n" if $opt{debug};
        if ($output =~ /^WHEELDONE/)
        {
          my $device = $heap->{writenet_wheel_dev}->{$wheel_id};
          if ($device = shift @{$heap->{writeables_a}})
          {
              print "sending device $device to writenetd($heap->{writenet_wheel_id}->{$wheel_id})\n" if $opt{debug};
            $heap->{writenet_wheel_dev}->{$wheel_id} = $device;
            $heap->{writenet_wheels}->{$wheel_id}->put("$device:$heap->{writeables_h}->{$device}");
          }
          else
          {
            print "No more devices\n" if $opt{debug};
            $heap->{writenet_wheels}->{$wheel_id}->kill();
            $heap->{writenet_wheels}->{$wheel_id}->kill(9);
          }
        }

        my $device = shift @{$heap->{writeables_a}};
        print "sending device $device\n" if $opt{debug};
        $heap->{writenet_wheel_dev}->{$wheel->ID} = $device;
        $heap->{writenet_wheel_id}->{$wheel->ID} = $i;
        $heap->{writenet_wheels}->{$wheel->ID}->put("$device:$heap->{writeables_h}->{$device}");
      },

    } ## inline states
  ); ## POE session
} ## new

sub loader
{
  $0 =~ s/.pl$/_loader.pl/;

  while ( sysread( STDIN, $writeable, $size ) )
  {
    foreach my $row (@$parcel)
    {
      print "LOAD: $row\n" if $verbose;

      ($hostkey, $ds, $type, $time, $value) = split /:/, $row;

      print "LOAD: $row\n" if ($debug && $ds =~ /^(SNAGs_|rrd_)/);

      $host = $hostkey;
      my $multi;
      $multi = $1 if ( $host =~ s/\[(.+)\]//);
  
      $stats->{hosts}->{$host} = 1;
      $stats->{multi}->{$hostkey} = 1 if $multi;
      $stats->{stats}->{update}++;
  
      eval
      {
        #$rrd->{$hostkey}->{$ds}->update(time => $time, value => $value);
        RRDs::update ("$rrd_base_dir/$host/$multi/$ds.rrd", "$time:$value");
        my $err=RRDs::error;
        die "ERROR: $err\n" if $err;
  
        utime $time, $time, "$rrd_base_dir/$host/$multi/$ds.rrd";
      };
      if($@)  ## ERROR on update
      {
        if($@ =~ /Can\'t call method \"update\" on an undefined value/ || $@ =~ /No such file or directory/) ### VALIDATE
        {
          unless($hostkey && $ds && $type && $time && defined $value)
          {
            print "ERROR: Bogus line: $row\n";
          }
          elsif($hostkey !~ /^([\w\%\~\-\[\]]+\.?)+$/)
          {
            print "ERROR: Bogus line: $row, invalid hostkey: $hostkey\n";
          }
          elsif($host !~ /^([\w\-\.])+$/)
          {
            print "ERROR: Bogus line: $row, invalid host: $host\n";
          }
          elsif($ds !~ /^([\w\%\~\-\[\]]+\.?)+$/)
          {
            print "ERROR: Bogus line: $row, invalid ds: $ds\n";
          }
          elsif(!$valid_types{$type})
          {
            print "ERROR: Bogus line: $row, invalid type: $type\n";
          }
          else ### CREATE
          {
            my $rrd_dir = $rrd_base_dir . "/" . $host;
            $rrd_dir .= "/" . $multi if $multi;
  
            my $rrd_file = $rrd_dir . "/" . $ds . ".rrd";
  
            unless(-d $rrd_dir)
            {
              my $dir = dirname $rrd_dir;
              unless(-d $dir)
              {
                mkdir $dir, 0750 and $kernel->post("logger" => "log" => "LOAD: Creating $dir");
              }
              mkdir $rrd_dir, 0750 and $kernel->post("logger" => "log" => "LOAD: Creating $rrd_dir");
            }
  
            eval
            {
              $rrd->{$hostkey}->{$ds} = RRDTool::OO->new( file => $rrd_file);
  
              unless(-e $rrd_file)
              {
                my ($n, $t) = ($type =~ /^(\d+)(.+)$/);
  
                my $a = 0;
                $a = 1 if ($t =~ s/a//i);
  
                $t = 'COUNTER' if $t =~ /^c/;
                $t = 'GAUGE'   if $t =~ /^g/;
                $t = 'DERIVE'  if $t =~ /^d/;
                $kernel->post("logger" => "log" => "LOAD: Creating $rrd_file");
                $rrd->{$hostkey}->{$ds}->create(@{&get_template($ds, $n, $t, $a, $time)});
                chmod 0740, $rrd_file || $kernel->post("logger" => "log" => "Error chmoding: $rrd_file");
                  #system "/bin/chgrp nobody $rrd_file" && $kernel->post("logger" => "log" => "Error chmoding: $rrd_file");
                $stats->{stats}->{create}++;
                #push @scan_queue, $hostkey;
              }
              else
              {
                $stats->{stats}->{rebind}++;
              }
            };
            if($@)
            {
              $kernel->post('logger' => 'log' => "LOAD: Failed creating RRD \'$row\', $@");
            }
          } ### CREATE
        }
        else # not a creation issue
        {
          if ($@ =~ m/failed: illegal attempt/)
          {
            $stats->{stats}->{illegal}++;
            print "WARN: illegal update \'$row\', $@\n";
          }
          else
          {
            $stats->{stats}->{fail}++;
            print "ERROR: failed loading \'$row\', $@\n";
          }
        }
      }
    }
  }
}


################################
sub get_template
################################
{
  my ($ds, $n, $type, $aber, $time) = @_;

  my $data_source = {
       name => 'data',
       type => $type,
  };

  if ($type eq 'DERIVE')
  {
    $data_source->{min} = 0;
  }

  if($n == 1)
  {
    ## 1:20160  60(per H)*24*7*2  5-minute avg details for 2 week
    ## 30:2016  2(per H)*24*7*6   30-minute avg/min/max details for 6 weeks 
    ## 120:1344  12(per D)*7*4*4  2-hour avg/min/max details for 4 months,
    ## 1440:732  1(per D)*365*2    1-day avg/min/max for 3 years

    $data_source->{heartbeat} = 360;

    return 
    [
      step      => 60,
      start     => $time - 60,
      data_source => $data_source,
      archive => { 
        rows    => 1,
        cpoints => 1,
        cfunc   => 'LAST', 
      },
      archive => { 
        rows    => 20160,
        cpoints => 1,
        cfunc   => 'AVERAGE', 
      },
      archive => { 
        rows    => 20160,
        cpoints => 1,
        cfunc   => 'MAX', 
      },
      archive => { 
        rows    => 2688,
        cpoints => 30,
        cfunc   => 'AVERAGE', 
      },
      archive => { 
        rows    => 2688,
        cpoints => 30,
        cfunc   => 'MIN', 
      },
      archive => { 
        rows    => 2688,
        cpoints => 30,
        cfunc   => 'MAX', 
      },
      archive => {
        rows    => 1488,
        cpoints => 120,
        cfunc   => 'AVERAGE',
      },
      archive => {
        rows    => 1488,
        cpoints => 120,
        cfunc   => 'MIN',
      },
      archive => {
        rows    => 1488,
        cpoints => 120,
        cfunc   => 'MAX',
      },
      archive => { 
        rows    => 732,
        cpoints => 1440,
        cfunc   => 'AVERAGE', 
      },
      archive => { 
        rows    => 732,
        cpoints => 1440,
        cfunc   => 'MIN', 
      },
      archive => { 
        rows    => 732,
        cpoints => 1440,
        cfunc   => 'MAX', 
      },
    ];
  }
  elsif($n == 5)
  {
    ## 1:4032   12(per H)*24*7*2  5-minute avg details for 2 week
    ## 6:2016   2(per H)*24*7*6   30-minute avg/min/max details for 6 weeks 
    ## 24:1344  12(per D)*7*4*4   2-hour avg/min/max details for 4 months,
    ## 288:732  1(per D)*365*2    1-day avg/min/max for 2 years

    $data_source->{heartbeat} = 900;

    return
    [
      step      => 300,
      start     => $time - 300,
      data_source => $data_source,
      archive => { 
        rows    => 1,
        cpoints => 1,
        cfunc   => 'LAST', 
      },
      archive => { 
        rows    => 4032,
        cpoints => 1,
        cfunc   => 'AVERAGE', 
      },
      archive => { 
        rows    => 4032,
        cpoints => 1,
        cfunc   => 'MAX', 
      },
      archive => { 
        rows    => 2016,
        cpoints => 6,
        cfunc   => 'AVERAGE', 
      },
      archive => { 
        rows    => 2016,
        cpoints => 6,
        cfunc   => 'MIN', 
      },
      archive => { 
        rows    => 2016,
        cpoints => 6,
        cfunc   => 'MAX', 
      },
      archive => {
        rows    => 1488,
        cpoints => 24,
        cfunc   => 'AVERAGE',
      },
      archive => {
        rows    => 1488,
        cpoints => 24,
        cfunc   => 'MIN',
      },
      archive => {
        rows    => 1488,
        cpoints => 24,
        cfunc   => 'MAX',
      },
      archive => { 
        rows    => 732,
        cpoints => 288,
        cfunc   => 'AVERAGE', 
      },
      archive => { 
        rows    => 732,
        cpoints => 288,
        cfunc   => 'MIN', 
      },
      archive => { 
        rows    => 732,
        cpoints => 288,
        cfunc   => 'MAX', 
      },
    ];
  }
  elsif($n == 15)
  {
    ## 1:1344   4(per H)*24*7*4  15-minute avg details for 2 weeks
    ## 2:2016   2(per H)*24*7*6  30-minute avg/min/max details for 6 weeks
    ## 8:1344  12(per D)*7*4*4  2-hour avg/min/max details for 4 months,
    ## 96:732  1(per D)*365*2   1-day avg/min/max for 2 years

    $data_source->{heartbeat} = 1800;

    return
    [
      step      => 900,
      start     => $time - 300,
      data_source => $data_source,
      archive => { 
        rows    => 1,
        cpoints => 1,
        cfunc   => 'LAST', 
      },
      archive => { 
        rows    => 1344,
        cpoints => 1,
        cfunc   => 'AVERAGE', 
      },
      archive => { 
        rows    => 1344,
        cpoints => 1,
        cfunc   => 'MAX', 
      },
      archive => { 
        rows    => 2016,
        cpoints => 2,
        cfunc   => 'AVERAGE', 
      },
      archive => { 
        rows    => 2016,
        cpoints => 2,
        cfunc   => 'MIN', 
      },
      archive => { 
        rows    => 2016,
        cpoints => 2,
        cfunc   => 'MAX', 
      },
      archive => {
        rows    => 1488,
        cpoints => 8,
        cfunc   => 'AVERAGE',
      },
      archive => {
        rows    => 1488,
        cpoints => 8,
        cfunc   => 'MIN',
      },
      archive => {
        rows    => 1488,
        cpoints => 8,
        cfunc   => 'MAX',
      },
      archive => { 
        rows    => 732,
        cpoints => 96,
        cfunc   => 'AVERAGE', 
      },
      archive => { 
        rows    => 732,
        cpoints => 96,
        cfunc   => 'MIN', 
      },
      archive => { 
        rows    => 732,
        cpoints => 96,
        cfunc   => 'MAX', 
      },
    ];
  }
  else
  {
    warn "Invalid value for n: $n";
  }
}

=cut
1;
