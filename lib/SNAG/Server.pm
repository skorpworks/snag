package SNAG::Server;

use strict;
use SNAG;
use POE;
use Socket;
use POE::Component::Server::TCP;
use Carp qw(carp croak);

use Net::Nslookup;
use Sys::Hostname;
use FileHandle;
use Crypt::CBC;
use File::Basename;
use Net::Nslookup;
use Data::Dumper;
use FreezeThaw qw/freeze thaw/;
use Date::Format;
use Capture::Tiny qw/capture tee capture_merged tee_merged/;

my $parcel_sep = PARCEL_SEP;
my $del = ':';

our $server_data;

our $heartbeat_batch = 20;

#################################
sub new
#################################
{
  my $package = shift;

  my $mi = $package . '->new()';

  croak "$mi requires an even number of parameters" if (@_ & 1);
  my %params = @_;

  croak "$mi needs an Alias parameter" unless exists $params{Alias};
  croak "$mi needs a Port parameter" unless exists $params{Port};
  croak "$mi needs a Key parameter" unless exists $params{Key};
  croak "$mi needs a Args parameter" unless exists $params{Args};

  my $alias      = delete $params{Alias};
  my $port       = delete $params{Port};
  my $key        = delete $params{Key};
  my $args	 = delete $params{Args};
  my $options    = delete $params{Options};

  $server_data->{server_alias} = $alias;

  foreach my $p (keys %params)
  {
    warn "Unknown parameter $p";
  }

  my $cipher = Crypt::CBC->new
  (
    {
      'key' => $key,
      'cipher' => 'Blowfish',
      'header' => 'randomiv',
    }
  );

  my $heartbeat_spool;

  POE::Session->create
  (
    inline_states=>
    {
      _start => sub
      {
        my ($heap, $kernel) = @_[ HEAP, KERNEL ];

        $kernel->alias_set("server_stats");
        $heap->{start} = time();
        $kernel->yield("server_stats");
      
      },

      server_stats => sub
      {
        my ($heap, $kernel) = @_[ HEAP, KERNEL ];
      
        $kernel->call('logger' => 'log' => "Entered server_stats");
        my $epoch = time();
        $kernel->alarm_set($_[STATE] => $epoch + 60);

        my $uptime = $epoch - $heap->{start};

        my $stat_prefix = HOST_NAME . "[$alias]";

        $kernel->call('logger' => 'log' => "posting server_stats");
        $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($stat_prefix, 'SNAGs_uptime', '1g', $epoch, $uptime));
        $kernel->call('logger' => 'log' => join $del, ($stat_prefix, 'SNAGs_uptime', '1g', $epoch, $uptime));

        $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($stat_prefix, 'SNAGs_conn', '1g', $epoch, ((scalar keys %{$SNAG::Server::server_data->{ips}}) + 0) ) );
        $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($stat_prefix, 'SNAGs_parcel', '1g', $epoch, ($server_data->{parcels}+0) ) );
        $SNAG::Server::server_data->{parcels} = 0;
        $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($stat_prefix, 'SNAGs_cons', '1g', $epoch,  ($server_data->{conn}+0) ) );
        $SNAG::Server::server_data->{conn} = 0;
        $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($stat_prefix, 'SNAGs_cons', '1g', $epoch,  ($server_data->{disconn}+0) ) );
        $SNAG::Server::server_data->{disconn} = 0;
        $kernel->post('client' => 'sysrrd' => 'load' => join $del, ($stat_prefix, 'SNAGs_cons', '1g', $epoch,  ($server_data->{timeout}+0) ) );
        $SNAG::Server::server_data->{timeout} = 0;
        $kernel->call('logger' => 'log' => "done server_stats");
      },
    }
  );

  POE::Component::Server::TCP->new
  (
    Started => sub
    {
      my ($kernel, $heap) = @_[ KERNEL, HEAP ];
      $kernel->alias_set('server');
      $kernel->call('logger' => 'log' => "STARTED: Starting $alias SNAG server on " . HOST_NAME);
    },

    Port => $port,

    ClientFilter => [ "POE::Filter::Line", Literal => $parcel_sep ],

    ClientConnected => sub
    {
      my ($kernel, $heap) = @_[ KERNEL, HEAP ];

			my ($now, $socket, $ip, $host, $stdout);
			$now = time();
      # Horrible hack to get to the socket
      $socket = $heap->{client}[$heap->{client}->HANDLE_INPUT];
      setsockopt($socket, SOL_SOCKET, SO_KEEPALIVE, 1) || die "Could not set keepalive on socket: $!";

      $ip = $heap->{remote_ip};
			
      ($stdout) = capture_merged
      {
        # don't perform nslookups, as if many one of them time out, then future clients can't 
	# get through the backlog and no one is happy 
        #$host = nslookup(host => $ip, type => "PTR") || $ip;
        $host = $ip;
      };

      $server_data->{last_connect_attempt}->{$ip} = time2str('%Y-%m-%d %T', $now);

      $server_data->{ips}->{$ip}++;
      $server_data->{conn}++;

      $heap->{hostname} = $host;

      $heap->{cipher} = $cipher;
      $heap->{key} = $key;

      $kernel->call('logger' => 'log' => "ClientConnected: New connection from $ip ($host) timing out at " . ($now + 20));

      $heap->{handshake_timeout_id} = $kernel->alarm_set('handshake_timeout' => ($now + 20));
    },

    ClientDisconnected => sub
    {
      my ($kernel, $heap) = @_[ KERNEL, HEAP ];
      my $ip = $heap->{remote_ip};

      if($server_data->{ips}->{$ip})
      {
        unless(--$server_data->{ips}->{$ip})
        {
          delete $server_data->{ips}->{$ip};
        }
      }  
      else
      {
        $kernel->call('logger' => 'log' => "SNAG::Server Error:  got a disconnect from a server that wasn't connected, ip=$ip, host=$heap->{hostname}");
      }

      
      $server_data->{disconn}++;
      $kernel->call('logger' => 'log' => "ClientDisconnected: Closed connection from $ip ($heap->{hostname})");
    },
  
    Error => sub
    {
      my ($kernel, $heap, $syscall_name, $error_number, $error_string) = @_[KERNEL, HEAP, ARG0, ARG1, ARG2];
      $kernel->call('logger' => 'log' => "SNAG::Server Error:  $syscall_name:$error_number:$error_string");
    },

    ClientError => sub
    {
      my ($kernel, $heap, $syscall_name, $error_number, $error_string) = @_[KERNEL, HEAP, ARG0, ARG1, ARG2];
      $kernel->call('logger' => 'log' => "SNAG::Server ClientError:  $syscall_name:$error_number:$error_string");
    },


    ClientInput => \&handshake,

    InlineStates =>
    {
      send => sub
      {
        my ($kernel, $heap, $data) = @_[KERNEL, HEAP, ARG0];

        my $serialized = freeze($data);
        my $encrypted = $heap->{cipher}->encrypt($serialized);
        $heap->{client}->put($encrypted);
      },

      disconnect => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        if($heap->{client})
        {
          $heap->{client}->shutdown_input();
          $heap->{client}->shutdown_output();
        }
        $kernel->yield('shutdown');
      },

      handshake_timeout => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        my $now = time;
        $server_data->{timeout}++;
        $kernel->call('logger' => 'log' => "Handshake Error:  Client sent nothing within time allowed ($now)");
        $kernel->yield('disconnect');
      },

      heartbeat => sub
      {
        my ($heap, $kernel, $input) = @_[HEAP, KERNEL, ARG0];

        unless(defined $heartbeat_spool)
        {
          $kernel->delay('heartbeat_update' => 10); 
        }

        if(ref $input->{host})
        {
          foreach my $host (@{$input->{host}})
          {
            $heartbeat_spool->{$host}->{ $input->{source} || 'SNAGc.pl' } = $input->{seen};
          }
        }
        else
        {
          $heartbeat_spool->{ $input->{host} }->{ $input->{source} || 'SNAGc.pl' } = $input->{seen};
        }
      },

      heartbeat_update => sub
      {
        my ($heap, $kernel) = @_[HEAP, KERNEL];

        print "START heartbeat_update....\n" if $SNAG::flags{debug};

        eval
        {
          my $sysinfo_dbh;

          ### jack the database handle maintained by the 'object' session, if present
          if(my $dbh = $kernel->alias_resolve('object')->get_heap()->{dbh})
          {
            my $db_name = $dbh->get_info(16);

            if($db_name eq 'sysinfo')
            {
              $sysinfo_dbh = $dbh;
            }
          }

          if($sysinfo_dbh && $sysinfo_dbh->ping())
          {
            if($heartbeat_spool)
            {
              my $hb_insert_sth = $sysinfo_dbh->prepare("insert into server_heartbeats(host, server, source, seen, server_seen) values(?, ?, ?, ?, now() )");
              my $hb_update_sth = $sysinfo_dbh->prepare("update server_heartbeats set seen = ?, server_seen = now() where host = ? and server = ? and source = ?");

	      my $processed = 0;

              while( my ($host, $ref) = each %$heartbeat_spool)
              {
                while( my ($source, $seen) = each %$ref)
                {
                  if($hb_update_sth->execute($seen, $host, $alias, $source) == 1)
                  {
                    print "  updating $host, $alias, $source, $seen\n" if $SNAG::flags{debug};
                  }
                  else
                  {
                    print "  inserting $host, $alias, $source, $seen\n" if $SNAG::flags{debug};

                    $hb_insert_sth->execute($host, $alias, $source, $seen) or die "Unable to update server_heartbeats: " . $sysinfo_dbh->errstr;
                  }
                }

		delete $heartbeat_spool->{$host};
		last if $processed > $heartbeat_batch;
              }
            }
          }
          else
          {
            $kernel->call('logger' => 'log' => "Could not update heartbeats, 'object' not connected to the sysinfo database!");
          }
        };
        if($@)
        {
          $kernel->call('logger' => 'log' => "Error in heartbeat_update: $@");
        }

        my $remaining_hb = scalar keys %$heartbeat_spool > 0 
        if ( $remaining_hb > 0 )
        {
          $kernel->yield('heartbeat_update');
          print "REMAIN: $remaining_hb heartbeat_updates\n" if $SNAG::flags{debug};
        }
        else
        {
          print "DONE heartbeat_update!\n" if $SNAG::flags{debug};
          #redundant but gives me warm fuzzies
          $heartbeat_spool = undef;
        }
      },
    }
  );
}

#################
sub handshake
#######################
{
  my ($kernel, $heap, $encrypted) = @_[ KERNEL, HEAP, ARG0 ];
  my $id = $_[SESSION]->ID;
 
  $server_data->{parcels}++;

  eval
  {
    my $serialized = $heap->{cipher}->decrypt($encrypted) or die $!;
    my ($parcel) = thaw($serialized) or die $!; 

    if(my $handshake = $parcel->{handshake})
    {
      unless($handshake eq 'Conan, what is best in life?')
      {
        die "Invalid handshake: $handshake";
      }
    }
    else
    {
      die "No handshake sent";
    }
  };
  if($@)
  {
    my $error = "Handshake Error: $heap->{hostname}: $@";

    $kernel->yield('send' => { error => $error } );
    $kernel->call('logger' => 'log' => $error);

    $kernel->delay('disconnect' => 1);
  }
  else
  {
    $kernel->yield('send' => { handshake => 'To crush your enemies, to see them driven before you, and to hear the lamentations of their women.' } );

    $kernel->state($_[STATE], \&input);
  }

  $kernel->alarm_remove(delete $heap->{handshake_timeout_id});
}

############################
sub input
############################
{
  my ($kernel, $heap, $encrypted) = @_[ KERNEL, HEAP, ARG0 ];
  my $id = $_[SESSION]->ID;
  my $rv;
 
  eval
  {
    my $serialized = $heap->{cipher}->decrypt($encrypted) or die $!;
    my ($parcel) = thaw($serialized) or die $!;

    $server_data->{parcels}++;

    if(my $function = $parcel->{function})
    {
      my $args = $parcel->{data};

      my $dest_session;
                                                    
      if($function eq 'heartbeat' and $server_data->{server_alias} =~ /^(sysinfo|dashboard|alerts|master|sysrrd)$/ )
      {
        ### for some reason settting this to the alias does not work   
        $dest_session = $_[SESSION];
      }
      else
      {
        $dest_session = 'object';
      }

      if($dest_session)
      {
        print "########### $heap->{hostname}($dest_session:$function) START ########\n" if $SNAG::flags{debug};
        $rv = $kernel->call($dest_session => $function => $args); 
        print "########### $heap->{hostname}($dest_session:$function) DONE! ########\n" if $SNAG::flags{debug};
      }
      else
      {
        $rv = 'skipped, no dest_session';
      }

      #rv passes back valid data for functions now, if something goes wrong in $function the die needs to occur there
      if($rv && $rv == -1)
      {
        $kernel->post('client' => 'dashboard' => 'load' => join REC_SEP, ('events', HOST_NAME, 'SNAG', "$server_data->{server_alias}", 'SNAG Server sending hold', "Server is sending $heap->{hostname} hold.  return value: $rv", '', time2str("%Y-%m-%d %T\n", time()) ));
        die "Unsuccessful loading.  Bad return value encountered.";
      }
    }
    else
    {
      ### Also check for non-implemented functions
      my $error = "Input Error: no function specified.  Received from client:" . Dumper $parcel;

      $kernel->call('logger' => 'log' => $error);
      $kernel->yield('send' => { status => 'error', details => $error });
    }
  };
  if($@)
  {
    #$kernel->yield('disconnect');
    my $error = "Input Error: $heap->{hostname}: $@";

    print "ERROR, sending hold: $@\n";
    $kernel->call('logger' => 'log' => $error);
    $kernel->yield('send' => { status => 'error', action => 'hold', details => $error });
  }
  else
  {
    $kernel->yield('send' => { status => 'success', result => $rv } );
  }
}

1;
