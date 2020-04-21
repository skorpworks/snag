package SNAG::Server::RRD; 
use base qw(SNAG::Server);

use strict;

use POE;      
use POE::Component::EasyDBI;

use SNAG;
use Time::HiRes qw( gettimeofday tv_interval );
use POE;
use Carp qw(carp croak);
use Devel::Size qw(total_size);;

use RRDTool::OO;
use RRDs;
use FileHandle;
use Data::Dumper;
use File::Basename;
use XML::Simple;
use File::Path;
use File::Spec;
use URI::Escape;
use Date::Format;

use Statistics::Descriptive;

### this bit only needed temporarily for rrd migration
use DBI;
my $dbh;
$dbh = DBI->connect("dbi:Pg:dbname=sysinfo;host=snag-db.puregig.net", 'sysinfo', 'AverycrypticPW', { RaiseError => 1} ) or die $dbh->errstr;

my $rec_sep = REC_SEP;

my $debug = $SNAG::flags{debug};
my $verbose = $SNAG::flags{verbose};

my ($rrd, $statistics, @load_stats, $stats, $stat_ref, @scan_queue);
my ($type, $module, $alias, $SNAGalias, $args);

################################
sub new
################################
{
  my $type = shift;
  $type->SUPER::new(@_);
  $alias = $type;
  $alias =~ s/.*\:\:([\w\.\-]+)$/$1/;

  $type = $type;
  $type =~ s/\:\:/\./g;
  $type =~ s/\:\:/\./g;

  $module = $type;
  $module =~ s/\:\:/\//g;
  $module .= '.pm';

  my %params = @_; 
  my $alias = delete $params{Alias};
  my $args = delete $params{Args};

  $SNAGalias = delete $params{Alias};
  $SNAGalias = $alias . '-' . $SNAGalias;

  croak "Args must be a hashref" if ref $args ne 'HASH';
  croak "Args must contain values for 'dir', 'dsn', 'user', and 'pw'" unless ($args->{dir} && $args->{dsn} && $args->{user} && $args->{pw});
  
  my $rrd_base_dir = $args->{dir};
  $rrd_base_dir =~ s/\/$//;  ### REMOVE TRAILING SLASH ON DIR TO AVOID PROBLEMS
   

  my $host_name = HOST_NAME;
  my $table = 'host_to_ds';

  my %valid_types = ( '1d' => 1, '5d' => 1, '15d' => 1, 
                      '1da' => 1, '5da' => 1, '15da' => 1, 
                      '1di' => 1, '5di' => 1, '15di' => 1, 
                      '1c' => 1, '5c' => 1, '15c' => 1,
                      '1ca' => 1, '5ca' => 1, '15ca' => 1,
                      '1ci' => 1, '5ci' => 1, '15ci' => 1,
                      '1g' => 1, '5g' => 1, '15g' => 1,
                      '1ga' => 1, '5ga' => 1, '15ga' => 1,
                      '1gi' => 1, '5gi' => 1, '15gi' => 1,
                    );


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

  POE::Session->create
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

        $kernel->call('logger' => "log" => "SCAN:uq: Updating db: $host_name, $host, $multi, $ds, $epoch\n") if $debug;
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
          $kernel->call('logger' => "log" => "SCAN:uqh: Error: $res->{error} on $rrd_tuple\n") if $debug;
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

        $kernel->call('logger' => "log" => "SCAN:iq: Inserting db: $rrd_host, $host, $multi, $ds, $epoch\n") if $debug;
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
          $kernel->call('logger' => "log" => "SCAN:iqh: Error: $res->{error} on $rrd_tuple\n") if $debug;
        }
        else
        {
          my $rrd_tuple = join ':', @{$res->{placeholders}};
          unless($res->{rows} > 0)
          {
            ###DELETE THIS LATER
            $kernel->call('logger' => "log" => "SCAN:easydbi: Error Insert/Update db: $rrd_tuple\n") if $debug;
          }
        }
      },

      conn_handler => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $heap->{connected} = 1;
        if (defined($heap->{disconnect_time}))
        {
          $kernel->call('logger' => "log" => "EASYDBI: Connected to db - was down for " . (time() - $heap->{disconnect_time})); 
         delete $heap->{disconnect_time};
        }
        else
        {
          $kernel->call('logger' => "log" => "EASYDBI: Connected to db"); 
        }
      },

      conn_err_handler => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $heap->{connected} = 0;
        $heap->{disconnect_time} = time() unless defined($heap->{disconnect_time});
        $kernel->call('logger' => "log" => "EASYDBI: Could not connect to db\n"); 
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
          mkdir $rrd_base_dir, 0770 and $kernel->call('logger' => "log" => "START: Creating $rrd_base_dir");
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
        $kernel->yield('build_threshholds');
      },

      build_threshholds => sub
      {
        my ($heap, $kernel) = @_[HEAP, KERNEL];
        my ($base_dir, $xs, $ref);

        $base_dir = BASE_DIR;
        $kernel->call('logger' => "log" => "DASHBOARD: build_threshholds: loading $base_dir/RULES.xml\n");

        eval
        {
          $xs = XML::Simple->new(ForceArray => 1, KeepRoot => 0);
          $ref = $xs->XMLin("$base_dir/RULES.xml") or die "$!";
        };
        if ($@)
        {
          $kernel->call('logger' => "log" => "DASHBOARD: build_threshholds: failed loading $base_dir/RULES.xml : $@\n");
        }
        else
        {
          $heap->{threshholds} = $ref;
          my ($xmlstring) = $xs->XMLout($heap->{threshholds});
          my (@xml) = split /\n/, $xmlstring;
          foreach my $line (@xml) { $kernel->call('logger' => "log" => "DASHBOARD: build_threshholds: $line"); }
          print Dumper($ref) if $debug;
        }
        $kernel->delay('build_threshholds' => 900);
      },

      scan_init => sub
      {
        my ($heap, $kernel) = @_[HEAP, KERNEL];
   
        (@scan_queue) = sort keys %{$rrd};
        $kernel->call('logger' => "log" => "SCANINIT: " . scalar @scan_queue . " objects\n");
        #$kernel->delay('scan_init' => 86400);
      },

      scan => sub
      { 
        my ($heap, $kernel) = @_[HEAP, KERNEL];

        if ($#scan_queue < 0)
        {
          $kernel->call('logger' => "log" => "SCAN: empty queue\n") if $debug;
          $kernel->delay($_[STATE] => 60);
          return 
        }

        $kernel->call('logger' => "log" => "SCAN: starting on " . scalar @scan_queue . " objects\n");

        my ($host_multi, $host, $multi, $val, $i);
        TOP:    for ($i = 0; $i <= 10; $i++)
        {
          $kernel->call('logger' => "log" => "SCAN: processing $scan_queue[0]\n") if $debug;
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
          $kernel->call('logger' => "log" => "SCAN: " . scalar @scan_queue . " objects in scan_queue\n") if $debug;
          last TOP if $#scan_queue < 0;
        } ### end for loop

        if ($#scan_queue >= 0)
        {
          $kernel->call('logger' => "log" => "SCAN: delay\n") if $debug;
          $kernel->delay($_[STATE] => 10);
        }
        else
        {
          $kernel->call('logger' => "log" => "SCAN: sleep\n") if $debug;
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

        push @{$stat_ref}, $stat_prefix . ":SNAGs_mem_rrd:1g:$time:" . (total_size($rrd) + 0);
        push @{$stat_ref}, $stat_prefix . ":SNAGs_mem_stats:1g:$time:" . (total_size($stats) + 0);
        push @{$stat_ref}, $stat_prefix . ":SNAGs_mem_heap:1g:$time:" . (total_size($heap) + 0);
        push @{$stat_ref}, $stat_prefix . ":SNAGs_mem_scanqueue:1g:$time:" . (total_size(\@scan_queue) + 0);

        if (@load_stats > 0)
        {
          $statistics = Statistics::Descriptive::Full->new();
          $statistics->add_data(@load_stats);
          push @{$stat_ref}, $stat_prefix . ":rrd_loadtime_min:1g:$time:" . $statistics->min();
          push @{$stat_ref}, $stat_prefix . ":rrd_loadtime_max:1g:$time:" . $statistics->max();
          push @{$stat_ref}, $stat_prefix . ":rrd_loadtime_mean:1g:$time:" . $statistics->mean();
          push @{$stat_ref}, $stat_prefix . ":rrd_loadtime_hmean:1g:$time:" . $statistics->harmonic_mean();
          push @{$stat_ref}, $stat_prefix . ":rrd_loadtime_stddev:1g:$time:" . $statistics->standard_deviation();
          push @{$stat_ref}, $stat_prefix . ":rrd_loadtime_pct75:1g:$time:" . $statistics->percentile(75); 
          @load_stats = ();
        }

        $kernel->yield('load' => $stat_ref);
      },

      load => sub
      {
        my ($heap, $kernel, $parcel) = @_[HEAP, KERNEL, ARG0];

        my ($t0, $hostkey, $ds, $type, $time, $value, $host, $dbevent, $threshhold);

        $t0 = [gettimeofday];

        foreach my $row (@$parcel)
        {
          print "LOAD: $row\n" if $verbose;

          ($hostkey, $ds, $type, $time, $value) = split /:/, $row;

          print "LOAD: $row\n" if ($debug && $ds =~ /^(SNAGs_|rrd_)/);

          $host = $hostkey;
          my $multi;
          $multi = $1 if ( $host =~ s/\[(.+)\]//);

          eval
          {
            #$rrd->{$hostkey}->{$ds}->update(time => $time, value => $value);

            RRDs::update ("$rrd_base_dir/$host/$multi/$ds.rrd", "$time:$value");
            my $err=RRDs::error;
            die "ERROR: $err\n" if $err;

            $stats->{hosts}->{$host} = 1;
            $stats->{multi}->{$hostkey} = 1 if $multi;
            $stats->{stats}->{update}++;

            utime $time, $time, "$rrd_base_dir/$host/$multi/$ds.rrd";
            if ( (! defined $rrd->{$hostkey}->{$ds}) && $heap->{threshholds}->{$ds})
            {
              $rrd->{$hostkey}->{$ds} = RRDTool::OO->new( file => "$rrd_base_dir/$host/$multi/$ds.rrd");
            }
          };
          if($@)
          {
            if($@ =~ /Can\'t call method \"update\" on an undefined value/ || $@ =~ /No such file or directory/) 
            {
              ### VALIDATE
              unless($hostkey && $ds && $type && $time && defined $value)
              {
                $kernel->call('logger' => "log" => "LOAD: Bogus line: $row");
              }
              elsif($hostkey !~ /^([\w\%\~\-\[\]]+\.?)+$/)
              {
                $kernel->call('logger' => "log" => "LOAD: Bogus line: $row, invalid hostkey: $hostkey");
              }
              elsif($host !~ /^([\w\-\.])+$/)
              {
                $kernel->call('logger' => "log" => "LOAD: Bogus line: $row, invalid host: $host");
              }
              elsif($ds !~ /^([\w\%\~\-\[\]]+\.?)+$/)
              {
                $kernel->call('logger' => "log" => "LOAD: Bogus line: $row, invalid ds: $ds");
              }
              elsif(!$valid_types{$type})
              {
                $kernel->call('logger' => "log" => "LOAD: Bogus line: $row, invalid type: $type");
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
                    mkdir $dir, 0750 and $kernel->call('logger' => "log" => "LOAD: Creating $dir");
                  }
                  mkdir $rrd_dir, 0750 and $kernel->call('logger' => "log" => "LOAD: Creating $rrd_dir");

	### this bit only needed temporarily for rrd migration
	#if( my $lookup = $dbh->selectrow_hashref("select server_host from snag_server_definitions, snag_server_mappings where server_id = id and snag_server_mappings.name = 'sysrrd' and snag_server_mappings.host = ?", undef, $host ) )
	#{
	#	my $start = time;

	#	my $source_host = $lookup->{server_host};
	#	my $command = "rsync -a root\@$source_host:/var/rrd/$host/ /var/rrd/$host/";

	#	my $rsync_output;
	#	open RSYNC, "$command 2>&1 |";
	#	while( my $line = <RSYNC> )
	#	{
	#		$rsync_output .= $line;
	#	}
	#	my $close_status = close RSYNC;
	#	my $exit_status = $? >> 8;

	#	my $elapsed = time - $start;

	#	my $result;
	#	if( $close_status && !$exit_status && ( not defined $rsync_output ) )
	#	{
	#		$result = 'success';
	#	}
	#	else
	#	{
	#		$result = 'failure';
	#	}

	#	$kernel->call('logger' => "log" => "rrd migrate: host=$host result=$result elapsed=$elapsed close_status=$close_status exit_status=$exit_status rsync_output=$rsync_output source_host=$source_host");

	#	if( ( $result eq 'failure' ) && ( length($host) > 1 ) )
	#	{
	#		system "rm -rf /var/rrd/$host/"; ## yikes
	#		exit;
	#	}
	#}

                }

                eval
                {
                  $rrd->{$hostkey}->{$ds} = RRDTool::OO->new( file => $rrd_file);

                  unless(-e $rrd_file)
                  {
                    my ($n, $t) = ($type =~ /^(\d+)(.+)$/);

                    #enable aberrant
                    my $a = 0;
                    $a = 1 if ($t =~ s/a//i);

                    #non-consolidated "infinite" rrd
                    my $i = 0;
                    $i = 1 if ($t =~ s/i//i);
                  
                    $t = 'COUNTER' if $t =~ /^c/;
                    $t = 'GAUGE'   if $t =~ /^g/;
                    $t = 'DERIVE'  if $t =~ /^d/;
                    $kernel->call('logger' => "log" => "LOAD: Creating $rrd_file");
                    $rrd->{$hostkey}->{$ds}->create(@{&get_template($ds, $n, $t, $a, $i, $time)});
                    chmod 0740, $rrd_file || $kernel->call('logger' => "log" => "Error chmoding: $rrd_file");
                    #system "/bin/chgrp nobody $rrd_file" && $kernel->call('logger' => "log" => "Error chmoding: $rrd_file");
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
                  $kernel->call('logger' => 'log' => "LOAD: Failed creating RRD \'$row\', $@");
                  $kernel->post('client' => 'dashboard' => 'load' => join $rec_sep, ('events', $host, 'RRD', 'rrd error',                  
                  'RRD create error', "$rrd_file: . $@", '', time2str("%Y-%m-%d %T", $time)));                                      
                  $stats->{hosts}->{$host} = 1;
                  $stats->{multi}->{$hostkey} = 1 if $multi;
                  $stats->{stats}->{update}++;
                }
              } ### CREATE
            }
            else
            {
              if ($@ =~ m/: illegal attempt to/)
              {
                $stats->{stats}->{illegal}++;
                #$kernel->post('client' => 'dashboard' => 'load' => join $rec_sep, ('events', $host, 'RRD', 'rrd error', 'RRD create error', $@,'',time2str("%Y-%m-%d %T", $time)));  
                $kernel->call('logger' => 'log' => "LOAD: Failed loading \'$row\', $@") if $debug; 
                 
              }
              else
              {
                $stats->{stats}->{fail}++;
                $kernel->post('client' => 'dashboard' => 'load' => join $rec_sep, ('events', $host, 'RRD', 'rrd error',
                  'RRD create error', $@, '', time2str("%Y-%m-%d %T", $time)));                
                $kernel->call('logger' => 'log' => "LOAD: Failed loading \'$row\', $@"); 
              }
            }
          }
          else
          {
            if ($heap->{threshholds}->{$ds})
            {
              $kernel->call('logger' => "log" => "DASHBOARD: $hostkey:$ds entered") if $debug;
              if ($type =~ /(\d+)[c|d]/i)
              {
                eval
                {
                  $rrd->{$hostkey}->{$ds}->fetch_start(cfunc => "LAST", start => ($time-10), end => ($time-1));
                  ($dbevent->{'time'}, $dbevent->{'value'}) = $rrd->{$hostkey}->{$ds}->fetch_next();
                  $dbevent->{'value'} = int($dbevent->{'value'} * $1 * 60);
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
              foreach $threshhold (@{$heap->{threshholds}->{$ds}})
              {
                next if (defined $threshhold->{onlyhost} && $threshhold->{onlyhost} ne $host);

		if (defined $threshhold->{agg} && defined $heap->{dashboard_store}->{$host}->{$threshhold->{agg}} )
		{
		  $dbevent->{'value'} += $heap->{dashboard_store}->{$host}->{$threshhold->{agg}};
		}

                $dbevent->{message} = '';
                $dbevent->{full} = '';
                $kernel->call('logger' => "log" => "DASHBOARD: $hostkey:$ds ($threshhold->{'type'}:$threshhold->{'limit'}) $dbevent->{'value'}") if $debug;
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
                    unless ($dbevent->{'value'} <= 0 || $heap->{dashboard_store}->{$host}->{$threshhold->{denom}} <= 0)
                    {
                      $dbevent->{full} = "$threshhold->{alert} ($dbevent->{'value'} > $threshhold->{limit})" if ( ($dbevent->{'value'} / $heap->{dashboard_store}->{$host}->{$threshhold->{denom}}) <= $threshhold->{ratio});
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
                  $kernel->call('logger' => "log" => "DASHBOARD: $dbevent->{message}") if $debug;
                  $kernel->post('client' => 'dashboard' => 'load' => $dbevent->{message});
                }
              } ### foreach
            } ### if ($heap->{threshholds}->{$ds})
          } ### if($@) else
        } ### foreach
        push @load_stats, (tv_interval ( $t0, [gettimeofday])) / scalar @$parcel;

        return 0;
      },
    }
  );
}

################################
sub get_template
################################
{
  my ($ds, $n, $type, $aber, $inf, $time) = @_;

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

    if ($inf)
    {
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
          rows    => 2628000,
          cpoints => 1,
          cfunc   => 'AVERAGE', 
        },
      ]
    }
    else
    {
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
  }
  elsif($n == 5)
  {
    ## 1:4032   12(per H)*24*7*2  5-minute avg details for 2 week
    ## 6:2016   2(per H)*24*7*6   30-minute avg/min/max details for 6 weeks 
    ## 24:1344  12(per D)*7*4*4   2-hour avg/min/max details for 4 months,
    ## 288:732  1(per D)*365*2    1-day avg/min/max for 2 years

    $data_source->{heartbeat} = 900;

    if ($inf)
    {
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
          rows    => 525600,
          cpoints => 1,
          cfunc   => 'AVERAGE', 
        },
      ]
    }
    else
    {
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
  }
  elsif($n == 15)
  {
    ## 1:1344   4(per H)*24*7*4  15-minute avg details for 2 weeks
    ## 2:2016   2(per H)*24*7*6  30-minute avg/min/max details for 6 weeks
    ## 8:1344  12(per D)*7*4*4  2-hour avg/min/max details for 4 months,
    ## 96:732  1(per D)*365*2   1-day avg/min/max for 2 years

    $data_source->{heartbeat} = 1800;
    if ($inf)
    {
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
          rows    => 175200, 
          cpoints => 1,
          cfunc   => 'AVERAGE', 
        },
      ]
    }
    else
    {
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
  }
  elsif($n == 60)
  {
    $data_source->{heartbeat} = 7200;

    if ($inf)
    {
      return
      [
        step      => 3600,
        start     => $time - 3600,
        data_source => $data_source,
        archive => {
          rows    => 1,
          cpoints => 1,
          cfunc   => 'LAST',
        },
        archive => {
          rows    => 43800,
          cpoints => 1,
          cfunc   => 'AVERAGE',
        },
      ]
    }
  }
  elsif($n == 1440)
  {
    $data_source->{heartbeat} = 172800;

    if ($inf)
    {
      return
      [
        step      => 86400,
        start     => $time - 86400,
        data_source => $data_source,
        archive => {
          rows    => 1,
          cpoints => 1,
          cfunc   => 'LAST',
        },
        archive => {
          rows    => 1825,
          cpoints => 1,
          cfunc   => 'AVERAGE',
        },
      ]
    }
  }
  else
  {
    warn "Invalid value for n: $n";
  }
}

1;
