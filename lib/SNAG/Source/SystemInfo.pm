package SNAG::Source::SystemInfo;
use base qw/SNAG::Source/;

use SNAG;
use POE;
use POE::Filter::Reference;
use Carp qw(carp croak);
use Data::Dumper;
use FreezeThaw qw/freeze/;
use DBM::Deep;
use Date::Parse;
use Date::Format;

if(OS ne 'Windows')
{
  require POE::Wheel::Run;
}

my $timeout = 6000; #Seconds

my $debug = $SNAG::flags{debug};

my $shared_data = $SNAG::Dispatch::shared_data;

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

  my $module = 'SNAG/Source/SystemInfo/' . OS;
  (my $namespace = $module) =~ s#/#::#g;

  eval
  {
    require $module . '.pm';
    import $namespace ':all';
  };
  if($@)
  {
    die "SystemInfo: Problem loading $module: $@";
  }

  my ($config, %symbol_table);
  {
    no strict 'refs';
    $config = ${$namespace . '::config'};
    %symbol_table = %{$package . '::'};
  }

  my ($schedule, $min_period);
  while(my ($piece, $ref) = each %$config)
  {
    if(defined $min_period)
    {
      $min_period = $ref->{period} if $ref->{period} < $min_period;
    }
    else
    {
      $min_period = $ref->{period};
    }
  }

  $poe_kernel->post('logger' => 'log' => "Sysinfo: processed config") if $debug;

  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->sig( CHLD => 'catch_sigchld' ); ## Does this even need to be here?

        $kernel->delay('sync_remote_hosts' => 5) unless OS eq 'Windows';
        $kernel->delay('sync_xen_uuids' => 5) unless OS eq 'Windows';
        #$kernel->delay('get_client_functions' => 7) unless OS eq 'Windows';

        $kernel->delay('get_info' => 2);
      },

      sync_remote_hosts => sub
      {
        my ($kernel, $heap, $session) = @_[ KERNEL, HEAP, SESSION ];
        $kernel->delay($_[STATE] => 21600);

        $kernel->post('client' => 'sysinfo' => 'sync_remote_hosts' => { postback => $session->postback('add_remote_hosts') } );
      },

      sync_xen_uuids => sub
      {
        my ($kernel, $heap, $session) = @_[ KERNEL, HEAP, SESSION ];
        $kernel->delay($_[STATE] => 21600);
        $kernel->post('client' => 'sysinfo' => 'sync_xen_uuids' => { postback => $session->postback('add_xen_uuids') } );
      },

      get_client_functions => sub
      {
        my ($kernel, $heap, $session) = @_[ KERNEL, HEAP, SESSION ];
        $kernel->delay($_[STATE] => 600);

        $kernel->post('client' => 'sysinfo' => 'get_client_functions' => { host => HOST_NAME, postback => $session->postback('process_client_functions') } );
      },

      process_client_functions => sub
      {
#[
  #{
    #client_function => 'remove_user',
    #arg => 'ghetto',
    #function_id => 292,
  #}
#]
        my ($kernel, $heap, $ref) = @_[ KERNEL, HEAP, ARG1 ];
 
        my $functions = $ref->[0];

        foreach my $ref (@$functions)
        {
          my $rv;

          if( defined $client_functions->{ $ref->{client_function} })
          {
            $rv = $client_functions->{ $ref->{client_function} }->( $ref->{arg} );
          }
          else
          {
            $rv = "client function $ref->{client_function} not installed on this system!";
          }

          $kernel->post('client' => 'sysinfo' => 'result_client_function' => { result => $rv, function_id => $ref->{function_id} } );
        }
      },

      add_remote_hosts => sub
      {
        my ($kernel, $heap, $ref) = @_[ KERNEL, HEAP, ARG1 ];

        $SNAG::Dispatch::shared_data->{remote_hosts} = $ref->[0];
      },

      add_xen_uuids => sub
      {
        my ($kernel, $heap, $ref) = @_[ KERNEL, HEAP, ARG1 ];
        $SNAG::Dispatch::shared_data->{xen_uuids} = $ref->[0];
      },

      get_info => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->delay($_[STATE] => $min_period);

        my $subs_to_run;

        while(my ($sub, $args) = each %$config)
        {
          if(my $tag = $args->{if_tag})
          {
            my $tag_match = $SNAG::Dispatch::shared_data->{tags};
            foreach my $item (split /\./, $tag)
            {
              $tag_match = $tag_match->{$item};
              last unless $tag_match;
            }

            next unless $tag_match;
          }

          unless($symbol_table{$sub})
          {
            $kernel->post('logger' => 'log' => "Sysinfo: Subroutine $sub does not exist in SNAG::Source::SystemInfo's symbol table, skipping" );
            next;
          }

          unless(($schedule->{$sub} -= $min_period) > 0)
          {
            $subs_to_run->{$sub} = $args;
            $schedule->{$sub} = $args->{period};
          }
        }

        if(%$subs_to_run)
        {
          if($heap->{wheels} && scalar(keys %{$heap->{wheels}}))
          {  
            my $count = scalar(keys %{$heap->{wheels}} );
    
	    $kernel->post('client' => 'dashboard' => 'load' => join REC_SEP, ('events', HOST_NAME, 'aslc', 'sysinfo', 'Too many forked processes', "$count processes already running", '', time2str("%Y-%m-%d %T", time())));
            $kernel->post('logger' => 'log' => "Sysinfo: $count forked processes were already running when I wanted to start a new one" );
          }
          else
          {
            if(OS eq 'Windows')
            {
	      $kernel->post('logger' => 'log' => 'Sysinfo: Running (' . (join ", ", keys %$subs_to_run) . ")\n") if $debug;
  
              my $sysinfo = info($subs_to_run);
              $kernel->yield('info_stdio' => $sysinfo);
            }
            else
            {
	      $kernel->post('logger' => 'log' => 'Sysinfo: Starting a new wheel to run (' . (join ", ", keys %$subs_to_run) . ")\n") if $debug;
    
	      my $wheel = POE::Wheel::Run->new
	      (
	        Program => sub { info($subs_to_run) },
	        StdioFilter  => POE::Filter::Reference->new(),
	        StdoutEvent  => 'info_stdio',
	        StderrEvent  => 'info_stderr',
	        CloseEvent   => "info_close",
	        Priority     => +5,
	        CloseOnCall  => 1,
	      );
    
	      $heap->{wheels}->{$wheel->ID} = $wheel;
	      $heap->{timeouts}->{$wheel->ID} = $kernel->alarm_set('timeout' => time() + $timeout => $wheel->ID);
            }
          }
        }
      },

      timeout => sub
      {
        my ($kernel, $heap, $id) = @_[KERNEL, HEAP, ARG0];

        $kernel->post('logger' => 'log' => "Sysinfo: PWR exceeded its timeout and killed after $timeout seconds:  $heap->{sysinfo_debug}"); 

        $kernel->alarm_remove($id);
        delete $heap->{timeouts}->{$id};

        $heap->{wheels}->{$id}->kill or $heap->{wheels}->{$id}->kill(9);
        delete $heap->{wheels}->{$id};
 
        $kernel->post('client' => 'dashboard' => 'load' => join REC_SEP, ('events', HOST_NAME, 'aslc', 'sysinfo', 'A Sysinfo PWR exceeded its timeout', "$timeout seconds: $heap->{sysinfo_debug}", '', time2str("%Y-%m-%d %T", time())));
      },

      info_stdio => sub
      {
        my ($kernel, $heap, $info, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];

        if($heap->{state}->{host} ne CHECK_HOST_NAME)
        {
          ### Send a name change thingie?
          ### The hostname changed, clear the state
          #delete $heap->{state};
          $SNAG::Source::sysinfo_prune_state = undef;
          $heap->{state}->{host} = HOST_NAME;
        }
        
        if(%$info && ( my $pruned = SNAG::Source::sysinfo_prune($info) ) )
        {
          $pruned->{host} = HOST_NAME;
          $pruned->{seen} = time2str("%Y-%m-%d %T", time);

          ### save data here for other sources to use
          if(defined $pruned->{cpumem} && defined $pruned->{cpumem}->{cpu_count})
          {
            $shared_data->{cpu_count} = $pruned->{cpumem}->{cpu_count};
          }
          elsif(defined $pruned->{iface})
          {
            $shared_data->{iface} = $pruned->{iface};
          }

          $kernel->post('client' => 'sysinfo' => 'load' => freeze($pruned));
        }
      },

      info_stderr => sub
      {
        my ($kernel, $heap, $output) = @_[KERNEL, HEAP, ARG0];

        #shell-init: could not get current directory: getcwd: cannot access parent directories: No such file or directory
        #bash: /root/.bashrc: Permission denied
        #print STDERR join REC_SEP, ('events', HOST_NAME, 'sysinfo', 'service_state', 'service state change', "service $service is not running.  usual run rate is $pct%", '', $seen);  print STDERR "\n";

        if($output =~ /^events/)
        {
          $kernel->post('client' => 'dashboard' => 'load' => $output);
        }
        elsif($output =~ s/^\s*sysinfo_debug://)
        {
          $kernel->post('logger' => 'log' => "Sysinfo: $output") if $debug; 
          $heap->{sysinfo_debug} = $output;
        }
        else
        {
          unless($output =~ /got duplicate tcp line/
             || $output =~ /got bogus tcp line/
             || $output =~ /could not get current directory/
             || $output =~ /bashrc: Permission denied/
             || $output =~ /(lspci|pcilib)/) ### annoying messages from broken lspci on xenU
          {
    	    $kernel->post('client' => 'dashboard' => 'load' => join REC_SEP, ('events', HOST_NAME, 'aslc', 'sysinfo', 'Error getting sysinfo', "$output", '', time2str("%Y-%m-%d %T", time())));
          #$kernel->post('logger' => 'log' => "Sysinfo: Error getting sysinfo: $output"); 
          }
        }
      },

      info_close => sub
      {
        my ($kernel, $heap, $id) = @_[KERNEL, HEAP, ARG0];
        $kernel->alarm_remove(delete $heap->{timeouts}->{$id});
        delete $heap->{wheels}->{$id};
      },

      catch_sigchld => sub
      {
      },
    }
  );
}

my $client_functions =
{
  'remove_user' => sub
  {
    my $uid = shift;

    my $return;

    if($uid =~ /^\w+$/)
    {
      my $rv = `userdel $uid`;

      unless($rv)
      {
        $rv = 'success!';
      }

      return $rv;
    }
    else
    {
      return "invalid uid $uid";
    }
  },
};

sub info
{
  local $/;

  my $subs = shift;

  my $info = {};

  while(my ($sub, $args) = each %$subs)
  {
    no strict 'refs';

    print STDERR "sysinfo_debug:PWR: running $sub \n" if $debug;
    eval
    {
      if(my $new_info = $sub->($args))
      {
        $info = SNAG::Source::merge_hashref($info, $new_info);
      }
    };
    if ($@)
    {
      print STDERR "PWR: $sub aborted: $@ \n" if $debug;
    }
  }

  if(OS eq 'Windows')
  {
    return $info;
  }
  else
  {
    my $filter = POE::Filter::Reference->new('Storable');
    my $return = $filter->put( [ $info ] );
    print @$return;
  }

  print STDERR "sysinfo_debug:PWR subs done!\n" if $debug;
}

sub apache_version
{
  my ($execs, $contents);

  require Proc::ProcessTable;
  my $procs = new Proc::ProcessTable;

  foreach my $proc ( @{$procs->table} )
  {
    if($proc->fname eq 'httpd' || $proc->fname eq 'masond' || $proc->fname eq 'apache' || $proc->fname eq 'apache2')
    {
      (my $exec) = (split /\s+/, $proc->{cmndline})[0];
      $execs->{ $exec } = 1;
    }
  }

  my $info;
  foreach my $exe (sort keys %$execs)
  {
    my $output = `$exe -v 2>/dev/null`;
    chomp $output;

    push @$contents, "Server binary: $exe\n$output";
  }

  $info->{conf}->{apache_version} = { contents => join "\n-------------\n", @$contents };

  return $info;
}

sub tags
{
  my $args = shift;

  eval
  {
    my $info;

    if(my $tags_data = $args->{data}->{tags})
    {
      my $tags = _get_tags($tags_data, []);

      foreach my $tag (@$tags)
      {
        push @{$info->{tags}}, { tag => $tag };
      }
    }
    return $info;
  };
}

sub listening_ports
{
  my $args = shift;

  eval
  {
    if($args->{data}->{listening_ports})
    {
      my $info;

      foreach my $port (sort keys %{$args->{data}->{listening_ports}})
      {
        foreach my $addr (sort keys %{$args->{data}->{listening_ports}->{$port}})
        {
          push @{$info->{listening_ports}}, { port => $port, addr => $addr };
        }
      }

      return $info;
    }
  };
}

sub _get_tags
{
  my ($struct, $pre) = @_;

  my $return;

  while(my ($key, $val) = each %$struct)
  {
    push @$return, (join '.', (@$pre, $key));

    if(ref $val)
    {
      push @$return, @{ _get_tags($val, [ @$pre, $key ]) };
    }
  }

  return $return;
}

1;
