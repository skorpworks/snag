package SNAG::Server::RRDBench; 
use base qw(SNAG::Server);

use strict;
use SNAG;
use Time::HiRes;
use POE;
use Carp qw(carp croak);
use Devel::Size qw(total_size);
use Test::Memory::Cycle;

use POE::Component::EasyDBI;
use RRDTool::OO;
use RRDs;
use FileHandle;
use Data::Dumper;
use File::Basename;
use Devel::Size;

my $rec_sep = REC_SEP;

my $debug = $SNAG::flags{debug};
my $verbose = $SNAG::flags{verbose};

my ($rrd, $stats, $stat_ref, @scan_queue);


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
   
  my $rrd;
  my $stats;

  my $table = 'host_to_ds_' . HOST_NAME;



  my %valid_types = ( '1d' => 1, '5d' => 1, '15d' =>1, 
                      '1c' => 1, '5c' => 1, '15c' => 1,
                      '1g' => 1, '5g' => 1, '15g' => 1 
                    );

  my $ioscheds = { 1 => 'noop',
                   2 => 'anticipatory',
                   3 => 'deadline',
                   4 => 'cfq',
                 };

  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
        my ($heap, $kernel) = @_[HEAP, KERNEL];
        $kernel->alias_set('object');

        my $state_file =  LOG_DIR . "/$alias.state";
        $heap->{state} = new DBM::Deep(file => $state_file);

        $heap->{sleepy_time} = 100;
        $heap->{tuned} = 0;

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

        if (! defined $heap->{state}->{run})
        {
          $heap->{state}->{run} = 0;
          $heap->{state}->{loop} = 1;
        }
        $heap->{run_started} = 0;
        $heap->{tuned} = 0;

        $kernel->delay('reset_tune' => 30);
      },

      reset_tune => sub
      {
        my ($heap, $kernel) = @_[HEAP, KERNEL];

        $heap->{state}->{run}++;
        $kernel->post("logger" => "log" => "Tuning to spec #$heap->{state}->{run} in 30 seconds\n");

        $heap->{sleepy_time} = 900;
        
        $kernel->delay('tune' => 60);
      },

      tune => sub
      {
        my ($heap, $kernel) = @_[HEAP, KERNEL];

        print "Tuning to spec #$heap->{state}->{run}\n";

        system("echo $ioscheds->{$heap->{state}->{loop}} > /sys/block/sda/queue/scheduler");

        if ($heap->{state}->{run} == 1)
        {
          system('sysctl  -w vm.dirty_background_ratio=8');
          system('sysctl  -w vm.dirty_ratio=33');
          system('sysctl  -w vm.dirty_writeback_centisecs=500');
          system('sysctl  -w vm.dirty_expire_centisecs=3000');

          system('blockdev --setra 128 /dev/sda4');

          system('sysctl  -w vm.vfs_cache_pressure=100');
        }
        elsif ($heap->{state}->{run} == 2)
        {
          system('sysctl  -w vm.vfs_cache_pressure=60');
        }
        elsif ($heap->{state}->{run} == 3)
        {
          system('blockdev --setra  64 /dev/sda4');
          system('sysctl  -w vm.vfs_cache_pressure=100');
        }
        elsif ($heap->{state}->{run} == 4)
        {
          system('sysctl  -w vm.vfs_cache_pressure=60');
        }
        elsif ($heap->{state}->{run} == 5)
        {
          system('blockdev --setra 32 /dev/sda4');
          system('sysctl  -w vm.vfs_cache_pressure=100');
        }
        elsif ($heap->{state}->{run} == 6)
        {
          system('sysctl  -w vm.vfs_cache_pressure=60');
        }
        elsif ($heap->{state}->{run} == 7)
        {
          system('sysctl  -w vm.dirty_background_ratio=80');
          system('sysctl  -w vm.dirty_ratio=90');
          system('sysctl  -w vm.dirty_writeback_centisecs=2000');
          system('sysctl  -w vm.dirty_expire_centisecs=8000');

          system('blockdev --setra 128 /dev/sda4');

          system('sysctl  -w vm.vfs_cache_pressure=100');
        }
        elsif ($heap->{state}->{run} == 8)
        {
          system('sysctl  -w vm.vfs_cache_pressure=60');
        }
        elsif ($heap->{state}->{run} == 9)
        {
          system('blockdev --setra 64 /dev/sda4');
          system('sysctl  -w vm.vfs_cache_pressure=100');
        }
        elsif ($heap->{state}->{run} == 10)
        {
          system('sysctl  -w vm.vfs_cache_pressure=60');
        }
        elsif ($heap->{state}->{run} == 11)
        {
          system('blockdev --setra 32 /dev/sda4');
          system('sysctl  -w vm.vfs_cache_pressure=100');
        }
        elsif ($heap->{state}->{run} == 12)
        {
          system('sysctl  -w vm.vfs_cache_pressure=60');
        }
        elsif ($heap->{state}->{run} == 13)
        {
          system('sysctl  -w vm.dirty_background_ratio=6');
          system('sysctl  -w vm.dirty_ratio=15');
          system('sysctl  -w vm.dirty_writeback_centisecs=500');
          system('sysctl  -w vm.dirty_expire_centisecs=1500');

          system('blockdev --setra 128 /dev/sda4');

          system('sysctl  -w vm.vfs_cache_pressure=100');
        }
        elsif ($heap->{state}->{run} == 14)
        {
          system('sysctl  -w vm.vfs_cache_pressure=60');
        }
        elsif ($heap->{state}->{run} == 15)
        {
          system('blockdev --setra 64 /dev/sda4');
          system('sysctl  -w vm.vfs_cache_pressure=100');
        }
        elsif ($heap->{state}->{run} == 16)
        {
          system('sysctl  -w vm.vfs_cache_pressure=60');
        }
        elsif ($heap->{state}->{run} == 17)
        {
          system('blockdev --setra 32 /dev/sda4');
          system('sysctl  -w vm.vfs_cache_pressure=100');
        }
        elsif ($heap->{state}->{run} == 18)
        {
          system('sysctl  -w vm.vfs_cache_pressure=60');
        }

        $kernel->post("logger" => "log" => "TUNE: Removing all existing data rrds\n");
        #system('find /var/rrd/ -type f -name "*.rrd" ! -path "*spork*" -exec /bin/rm {} \;');
        system('find /var/rrd/ -type f -name "*.rrd" ! -path "*`hostname -s`*" -exec /bin/rm {} \;');
        $kernel->post("logger" => "log" => "TUNE: Syncing\n");
        system('/bin/sync');
        $kernel->post("logger" => "log" => "TUNE: Tuned to $heap->{state}->{run}\n");

        if ($heap->{state}->{run} >= 19)
        {
          $heap->{state}->{loop}++;
          $heap->{state}->{run} = 0;
          system('/bin/sync');
          exit;
        }


        $stats->{run} = $heap->{state}->{run} * 100;
        $stats->{updatetot} = 0;
        foreach my $stat (keys %{$stats->{stats}})
        {
            $stats->{stats}->{$stat} = 0;
        }
        delete $stats->{hosts};
        delete $stats->{multi};
        $SNAG::Server::server_data->{parcels} = 0;
        $SNAG::Server::server_data->{conn} = 0;

        $heap->{sleepy_time} = 0;
        $heap->{tuned} = 1;
        $heap->{run_started} = 0;

      },

      stats => sub
      {
        my ($heap, $kernel) = @_[HEAP, KERNEL];

        $heap->{stats_next_time} += 60;
        $kernel->alarm('stats' => $heap->{stats_next_time});

        $stat_ref = ();
   
        $kernel->post("logger" => "log" => "============== STATS ==============\n");
        $kernel->post("logger" => "log" => "STATS: run         = $heap->{state}->{run}\n");
        $kernel->post("logger" => "log" => "STATS: loop        = $heap->{state}->{loop}\n");
        $kernel->post("logger" => "log" => "STATS: sleepy_time = $heap->{sleepy_time}\n");
        $kernel->post("logger" => "log" => "STATS: tuned       = $heap->{tuned}\n");
        $kernel->post("logger" => "log" => "STATS: run_started = $heap->{run_started}\n");

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

      sleepy_time => sub  ## server function
      {
        my ($heap, $kernel) = @_[HEAP, KERNEL];

        $kernel->post("logger" => "log" => "sleepy_time: ($heap->{sleepy_time})\n");
        if($heap->{sleepy_time} > 0)
        {
          return {sleepy_time => $heap->{sleepy_time}};
        }
        return {sleepy_time => 0};
      },

      load => sub  ## default server funtion
      {
        my ($heap, $kernel, $parcel) = @_[HEAP, KERNEL, ARG0];

        if($heap->{sleepy_time} > 0)
        {
          sleep 1;
          return 0;
        }

        if($heap->{run_started} == 0)
        {
          $kernel->delay('reset_tune' => 60*80);
          $heap->{run_started} = 1;
        }

        my ($hostkey, $ds, $type, $time, $value, $host);

        foreach my $row (@$parcel)
        {
          ($hostkey, $ds, $type, $time, $value) = split /:/, $row;


          print "LOAD: $row\n" if ($debug && $ds =~ /^(SNAGs_|rrd_)/);

          $host = $hostkey;
          my $multi;
          $multi = $1 if ( $host =~ s/\[(.+)\]//);

          eval
          {

            RRDs::update ("$rrd_base_dir/$host/$multi/$ds.rrd", "$time:$value");
            my $err=RRDs::error;
            die "ERROR: $err\n" if $err;

            $stats->{hosts}->{$host} = 1;
            $stats->{multi}->{$hostkey} = 1 if $multi;
            $stats->{stats}->{update}++;
            $stats->{updatetot}++;
          };
          if($@)
          {
            if($@ =~ /Can\'t call method \"update\" on an undefined value/ || $@ =~ /No such file or directory/) 
            {
              ### VALIDATE
              unless($hostkey && $ds && $type && $time && defined $value)
              {
                $kernel->post("logger" => "log" => "LOAD: Bogus line: $row");
              }
              elsif($hostkey !~ /^([\w\%\~\-\[\]]+\.?)+$/)
              {
                $kernel->post("logger" => "log" => "LOAD: Bogus line: $row, invalid host: $hostkey");
              }
              elsif($ds !~ /^([\w\%\~\-\[\]]+\.?)+$/)
              {
                $kernel->post("logger" => "log" => "LOAD: Bogus line: $row, invalid ds: $ds");
              }
              elsif(!$valid_types{$type})
              {
                $kernel->post("logger" => "log" => "LOAD: Bogus line: $row, invalid type: $type");
              }
              else
              {
                ### CREATE
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
                  $rrd = RRDTool::OO->new( file => $rrd_file);

                  unless(-e $rrd_file)
                  {
                    my ($n, $t) = ($type =~ /^(\d+)(.+)$/);
                    $t = 'COUNTER' if $t eq 'c';
                    $t = 'GAUGE'   if $t eq 'g';
                    $t = 'DERIVE'  if $t eq 'd';
                    #$kernel->post("logger" => "log" => "LOAD: Creating $rrd_file");
                    $rrd->create(@{&get_template($ds, $n, $t, $time)});
                    chmod 0740, $rrd_file || $kernel->post("logger" => "log" => "Error chmoding: $rrd_file");
                    #system "/bin/chgrp nobody $rrd_file" && $kernel->post("logger" => "log" => "Error chmoding: $rrd_file");
                    $stats->{stats}->{create}++;
                  }
                  else
                  {
                    $stats->{stats}->{rebind}++;
                  }
                  RRDs::update ("$rrd_base_dir/$host/$multi/$ds.rrd", "$time:$value");
                };
                if($@)
                {
                  $kernel->post('logger' => 'log' => "LOAD: Failed creating RRD \'$row\', $@");
                }
                else
                {
                  $stats->{hosts}->{$host} = 1;
                  $stats->{multi}->{$hostkey} = 1 if $multi;
                  $stats->{stats}->{update}++;
                  $stats->{updatetot}++;
                }
              } ### CREATE
            }
            else
            {
              $kernel->post('logger' => 'log' => "LOAD: Failed loading \'$row\', $@") unless $@ =~ m/failed: illegal attempt/;
              $stats->{stats}->{fail}++;
            }
          }
        }
        return 0;
      },
    }
  );
}

################################
sub get_template
################################
{
  my ($ds, $n, $type, $time) = @_;
  
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

1;
