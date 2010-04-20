package SNAG::Client;

use strict;
use SNAG; #FOR CONSTANTS
use SNAG::Queue;
use POE;
use POE::Session;
use POE::Component::Client::TCP;
use FreezeThaw qw/freeze thaw/;
use Carp qw(carp croak);

use Date::Format;
use Mail::Sendmail;
use Crypt::CBC;
use Date::Format;
use Time::Local;
use DBM::Deep;
use File::Spec::Functions qw/catfile/;
use Data::Dumper;

my $max_chunk_size = 100;
my $hold_period = 120;
my $parcel_sep = PARCEL_SEP;
my $line_sep = LINE_SEP;
my $rec_sep = REC_SEP;

my $init_handshake_timeout = 20;
my $parcel_ack_timeout = 60;

my $reconnect_min  = 20;
my $reconnect_rand = 20;

(my $script_name = SCRIPT_NAME) =~ s/\.\w+$//;

#########################################
sub new
#########################################
{
  my ($package, $default_connections) = @_;

  unless($default_connections)
  {
    croak 'missing argument';
  }
  
  $default_connections = [ $default_connections ] unless (ref $default_connections eq 'ARRAY');
  
  unless( grep { $_->{name} eq 'master' } @$default_connections)
  {
    croak 'SNAG::Client requires connection info for master server!';
  }

  ## handle and log attempts to communicate with servers based old aliasing method
  ## we can get rid of this some day
  foreach my $name ('sysinfo', 'sysrrd', 'dashboard', 'sysrrd', 'flowrrd', 'gunitloader', 'snag', 'noc', 'barracuda', 'sysinfo3', 'sysinfo2', 'netrrd', 'ciscorrd2', 'spazd', 'ciscorrd4', 'ciscorrd1', 'oldsysinfo', 'olddashboard', 'master', 'oldsysrrd', 'benchrrd', 'oldsysrrdpublic', 'sysrrdpublic', 'oldpollrrd', 'pollrrd') 
  {
    POE::Session->create
    (  
      inline_states =>
      {  
        _start => sub
        {
          my ($kernel, $heap) = @_[KERNEL, HEAP];
          $heap->{alias} = $name;
          $kernel->alias_set($name);
        },
       
        _default => sub
        {
          my ($kernel, $heap, $session, $name, $args) = @_[KERNEL, HEAP, SESSION, ARG0, ARG1];
          my $msg = "Illegal attempt to communicate with server: $heap->{alias}, method: $session, args: " . join ', ', grep { $_ } ($_[ARG0], $_[ARG1], $_[ARG2], $_[ARG3], $_[ARG4]);
          $kernel->post('logger' => 'log' => $msg);
        }
      }
    );
  }
 

  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        $kernel->alias_set('client');

        my $master_info_exists;

        foreach my $ref (@$default_connections)
        {
          $heap->{client_queue}->{ $ref->{name} } = $ref->{client_queue} = {};
          $kernel->state( $ref->{name} => \&handle_input );

          create_connection($ref);
        }
        
        ### Go through all existing queue files for this script
        ###   if they are empty, delete them
        ###   if they are non-empty, set up a client for them
        opendir IN, LOG_DIR;
        my @files = readdir IN;
        foreach my $line (@files)
        {
          if($line =~ /^($script_name\_(\w+)\_client_queue)\.dat$/)
          {
            my ($queue_name, $server_name) = ($1, $2);

            my $queue_file = catfile(LOG_DIR, $queue_name);
            my $queue = new SNAG::Queue ( File => $queue_file, Seperator => PARCEL_SEP );

            if($queue->peek(1))
            {
              print "  $queue_name is non-empty, requesting a connection to $server_name\n" if $SNAG::flags{debug};
              $kernel->state($server_name => \&handle_input);

              $heap->{client_queue}->{$server_name}->{has_data} = 1;
              $heap->{client_queue}->{$server_name}->{functions}->{load} = $queue;

              $kernel->yield('query_server_info' => $server_name);
            }
            else
            {
              print "  $queue_name is empty, deleting it.\n" if $SNAG::flags{debug};
              $queue->delete();
            }
          }
        }
      },

      _default => sub
      {
        my ($kernel, $heap, $session, $name, $args) = @_[KERNEL, HEAP, SESSION, ARG0, ARG1];
        return if $name eq '_child';
        return if $name eq '_stop';

        print "Recieved unhandled request to communicate with the $name server\n";

        my ($function, $data) = @$args;

        ### Set up new handler for client, and send the data to it
        $kernel->state($name => \&handle_input);
        $kernel->yield($name => $function, $data);

        $kernel->yield('query_server_info' => $name);
      },

      add => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        my $msg = "Calling depricated state 'add' with args: " . join ', ', grep { $_ } ($_[ARG0], $_[ARG1], $_[ARG2], $_[ARG3], $_[ARG4]);

        $kernel->post('logger' => 'log' => $msg);
      },

      ### need some state to periodically check to see if client_queue's that have data have corresponding _connection

      query_server_info => sub
      {
        my ($kernel, $heap, $session, $name) = @_[KERNEL, HEAP, SESSION, ARG0];

        ### what if the manager server is down?  Or you get an invalid response?
        ### what happens when two manager functions are sent before the first one gets anything back
        ### what if the manager never responds?
        $kernel->yield('master' => 'get_server_info' =>  { name => $name, client_host => HOST_NAME, postback => $session->postback('get_server_info_response', $name) } );
      },

      get_server_info_response => sub
      {
        my ($kernel, $heap, $passed_through, $passed_back) = @_[ KERNEL, HEAP, ARG0, ARG1 ];

        foreach my $ref (@$passed_back)
        {
          if(ref $ref eq 'HASH')
          {
            $ref->{client_queue} = $heap->{client_queue}->{ $ref->{name} };

            create_connection($ref);

            return;
          }
          else
          {
            $kernel->post("logger" => "log" => "Invalid data in get_server_info_response:" . Dumper $ref);
          }
        }

        $kernel->delay('query_server_info' => 60, $passed_through->[0]);
      },

    }
  );
}

sub handle_input
{
  my ($kernel, $heap, $name, $function, $data) = @_[KERNEL, HEAP, STATE, ARG0, ARG1, ARG2];

  $heap->{client_queue}->{$name}->{has_data} = 1;

  if($function eq 'load')
  {
    unless($heap->{client_queue}->{$name}->{functions}->{load})
    {
      my $queue_file = catfile(LOG_DIR, $script_name . '_' . $name . '_client_queue');

      $heap->{client_queue}->{$name}->{functions}->{load} = new SNAG::Queue ( File => $queue_file, Seperator => PARCEL_SEP );
    }

    print "Enqueue: $name($function): $data\n" if $SNAG::flags{debug};

    $heap->{client_queue}->{$name}->{functions}->{load}->enq($data);
  }
  else
  {
    my $queue_mode = delete $data->{queue_mode};
    if($queue_mode eq 'replace')
    {
      print "Enqueue: $name($function), replacing\n" if $SNAG::flags{debug};
      $heap->{client_queue}->{$name}->{functions}->{$function} = [ $data ];
    }
    else
    {
      print "Enqueue: $name($function)\n" if $SNAG::flags{debug};
      push @{$heap->{client_queue}->{$name}->{functions}->{$function}}, $data;
    }
  }
}

sub create_connection
{
  my $args = shift;

  my $missing;
  foreach my $key ('name', 'host', 'port', 'key', 'client_queue')
  {
    unless(defined $args->{$key})
    {
      print "Missing required argument '$key'\n" if $SNAG::flags{debug};
      push @$missing, $key;
    }
  }

  return if $missing;

  POE::Component::Client::TCP->new
  ( 
    RemoteAddress  => $args->{host},
    RemotePort     => $args->{port},

    Filter   => [ "POE::Filter::Line", Literal => $parcel_sep ],
 
    ConnectTimeout => 10,

    Started        => sub
                      {
                        my ($kernel, $heap) = @_[ KERNEL, HEAP ];
                        
                        $heap->{name} = $args->{name};
                        $heap->{host} = $args->{host};
                        $heap->{fallbackip} = $args->{fallbackip} || 0;
                        $heap->{port} = $args->{port};
                        $heap->{client_queue} = $args->{client_queue};

                        $heap->{cipher} = Crypt::CBC->new
                        (
                          {
                            'key' => $args->{key},
                            'cipher' => 'Blowfish',
                            'header' => 'randomiv',
                          }
                        );

			                  $kernel->post("logger" => "log" => "CLIENT STARTING $args->{name}" );
                      },

    Connected      => sub
                      {
                        my ($kernel, $heap) = @_[ KERNEL, HEAP ];
        
                        delete $heap->{connect_attempts};

                        $kernel->post("logger" => "log" => "CLIENT CONNECTED: $args->{name} to $heap->{host} on $args->{port}");

                        ### Send handshake
                        $kernel->state('got_server_input' => \&receive_handshake);
                        my $handshake = { handshake => 'Conan, what is best in life?' };
                        my $parcel = $heap->{cipher}->encrypt( freeze($handshake) );
                        $heap->{server}->put($parcel);

                        $heap->{timeout_id} = $kernel->alarm_set('force_disconnect' => (time() + $init_handshake_timeout), 'init handshake timeout');
                      },

    ConnectError   => sub
                      {
                        my ($kernel, $heap, $syscall, $num, $error) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2 ];
          
                        $heap->{connect_attempts}++;

                        my $error_msg = "CLIENT ERROR: $args->{name} to $heap->{host} on $heap->{port}: syscall = $syscall, num = $num, error = $error, failed after $heap->{connect_attempts} attempts";
 
                        if ($heap->{connect_attempts} <= 5 && $heap->{fallbackip})
                        {
                          my $reconnect_time = int( rand($reconnect_rand)) + $reconnect_min;
                          $error_msg .= ", reconnecting to fallback ip $heap->{fallbackip} in $reconnect_time seconds";
                          $kernel->delay('connect' => $reconnect_time, $heap->{fallbackip});
                        }
                        elsif($heap->{connect_attempts} <= 5 || $args->{name} eq 'master')
                        {
                          my $reconnect_time = int( rand($reconnect_rand)) + $reconnect_min;
                          $error_msg .= ", reconnecting in $reconnect_time seconds";

                          $kernel->delay('connect' => $reconnect_time, $heap->{host});
                        }
                        else
                        {
                          $error_msg .= ', destroying this session and requerying master server.';
                          
                          $kernel->yield('shutdown');

                          $kernel->post('client' => 'query_server_info' => $args->{name});
                        }

                        $kernel->post('logger' => 'log' => $error_msg);
                      },

    Disconnected   => sub
                      {
                        my ($kernel, $heap) = @_[ KERNEL, HEAP ];

                        delete $heap->{initiated_connection};
                        delete $heap->{pending_data};

                        my $reconnect_time = int( rand($reconnect_rand)) + $reconnect_min;

                        $kernel->post("logger" => "log" => "DISCONNECTED: $args->{name} to $heap->{host} on $args->{port}: reconnecting in $reconnect_time seconds");

                        $kernel->delay('reconnect' =>  $reconnect_time);
                      },

    ServerInput    => \&receive_handshake,

    ServerError    => sub
                      {
                        my ($kernel, $heap, $syscall, $num, $error) = @_[ KERNEL, HEAP, ARG0, ARG1, ARG2 ];

                        $kernel->post("logger" => "log" => "SERVER ERROR: $args->{name} to $heap->{host} on $args->{port}: syscall = $syscall, num = $num, error = $error");
                      },

    InlineStates   => { 
                        heartbeat => sub
                        {
                          my ($kernel, $heap) = @_[ KERNEL, HEAP];
                          $kernel->delay($_[STATE] => 60);

                          $kernel->post('client' => $args->{name} => 'heartbeat' => { source => SCRIPT_NAME, queue_mode => 'replace', host => HOST_NAME, seen => time2str('%Y-%m-%d %T', time) } );
                        },

                        send_parcel => sub
                        {
                          my ($kernel, $heap) = @_[ KERNEL, HEAP ];

                          if($heap->{pending_data})
                          {
			    $kernel->post('logger' => 'log' => 'CLIENT ERROR.  This client already has pending data, this should never happen');
                          }

                          return unless $heap->{initiated_connection};
                          
                          my $parcel;

                          ### this doesn't work for some crazy reason
                          #while ( my ($function, $data) = each %{$heap->{client_queue}->{functions}} )

                          foreach my $function ( keys %{$heap->{client_queue}->{functions}} )
                          {
                            my $data = $heap->{client_queue}->{functions}->{$function};

                            unless($function eq 'load')
                            {
                              my $postback = delete $data->[0]->{postback};

                              $parcel =
                              {
                                function => $function,
                                data => $data->[0],
                              };

                              $heap->{pending_data} =
                              {
                                function => $function,
                                postback => $postback,
                              };

                              if($SNAG::flags{debug})
                              {
                                my $args_str = join ', ', map { "$_ => $parcel->{data}->{$_}" } keys %{$parcel->{data}}; 
                                print "Sending: $args->{name}($function): args($args_str)\n";
                              }
                            }
                            elsif(my $chunk = $data->peek($max_chunk_size))
                            {
                              my $chunk_size = scalar @$chunk;

                              $parcel =
                              {
                                function => $function,
                                data => $chunk,
                              };

                              $heap->{pending_data} =
                              {
                                function => $function,
                                chunk_size => $chunk_size,
                              };

                              print "Sending: $args->{name}($function): $chunk_size items\n" if $SNAG::flags{debug};
                            }

                            last;
                          }

                          if($parcel)
                          {
                            ### found something to send

                            my $serialized = freeze($parcel);
                            my $encrypted = $heap->{cipher}->encrypt($serialized);

                            eval
                            {
                              $heap->{server}->put($encrypted);
                            };
                            if($@)
                            {
			                        $kernel->post("logger" => "log" => "Caught error while sending data: $@");
                              $kernel->yield('force_disconnect'); 
                            }
                            else
                            {                                                                    
                              $heap->{timeout_id} = $kernel->alarm_set('force_disconnect' => time() + $parcel_ack_timeout, 'timeout on parcel ack');
                            }
                          }
                          else
                          {
                            delete $heap->{client_queue}->{has_data};
                            $kernel->delay('check_queue' => 2);
                          }
                        },
     
                        check_queue => sub
                        {
                          my ($kernel, $heap) = @_[KERNEL, HEAP];
                         
                          print "In check_queue for $heap->{name}\n" if $SNAG::flags{verbose};

                          if($heap->{client_queue}->{has_data})
                          {
                            print "  sending parcel\n" if $SNAG::flags{verbose};
                            $kernel->yield('send_parcel');
                          }
                          else
                          {
                            $kernel->delay($_[STATE] => 2);
                            print "  no parcels to send\n" if $SNAG::flags{verbose};
                          }
                        },

                        force_disconnect => sub
                        {
                          my ($kernel, $heap, $msg) = @_[KERNEL, HEAP, ARG0];
   
                          $msg = 'Unknown reason' unless $msg;

                          my $reconnect_time = int( rand($reconnect_rand)) + $reconnect_min;
                          $kernel->post("logger" => "log" => "FORCED DISCONNECT: $args->{name} to $heap->{host} on $args->{port}: $msg, reconnecting in $reconnect_time seconds");

                          delete $heap->{initiated_connection};
                          delete $heap->{pending_data};

                          if($heap->{server})
                          {
                            $heap->{server}->shutdown_input();
                            $heap->{server}->shutdown_output();
                            delete $heap->{server};
                          }

                          $kernel->yield('shutdown');

                          $kernel->delay('reconnect' =>  $reconnect_time);
                        },
                      }
  );
}

sub receive_handshake
{
  my ($kernel, $heap, $encrypted) = @_[KERNEL, HEAP, ARG0];
  return if $heap->{'shutdown'};

  $kernel->alarm_remove(delete $heap->{timeout_id});

  my $input = $heap->{cipher}->decrypt($encrypted);
  my ($parcel) = thaw($input);

  if($parcel->{handshake} eq 'To crush your enemies, to see them driven before you, and to hear the lamentations of their women.')
  {
    ## SUCCESS! Back to default ServerInput
    $kernel->post("logger" => "log" => "CLIENT INITIATED: $heap->{name} to $heap->{host} on $heap->{port}");

    $heap->{initiated_connection} = 1;
    $kernel->state('got_server_input' => \&receive);

    $kernel->yield('check_queue');

    $kernel->yield('heartbeat') unless $heap->{name} =~ /rrd$/;
  }
  else
  {
    if($parcel->{error})
    {
      $kernel->post("logger" => "log" => "CLIENT ERROR: $heap->{name} to $heap->{host} on $heap->{port}: $parcel->{error}");
    }
    else
    {
      $kernel->post("logger" => "log" => "CLIENT ERROR: $heap->{name} to $heap->{host} on $heap->{port}: Invalid handshake response");
    }

    $kernel->yield('force_disconnect');
  }
}

sub receive
{
  my ($kernel, $heap, $encrypted) = @_[KERNEL, HEAP, ARG0];
  return if $heap->{'shutdown'};

  my $input = $heap->{cipher}->decrypt($encrypted);
  my ($parcel) = thaw($input);

  $kernel->alarm_remove(delete $heap->{timeout_id});

  if(my $pending_data = delete $heap->{pending_data})
  {
    my $function = $pending_data->{function};

    if($function eq 'load')
    {
      my $chunk_size = $pending_data->{chunk_size} or die "Function '$function' requires 'chunk_size' in 'pending_data'";

      print "Receiving: $heap->{name}($function): status=$parcel->{status} $chunk_size items\n" if $SNAG::flags{debug};

      unless($parcel->{action} eq 'hold')
      {
        $heap->{client_queue}->{functions}->{$function}->deq() for 0..$chunk_size - 1;
      }
    }
    else
    {
      print "Receiving: $heap->{name}($function): status=$parcel->{status}\n" if $SNAG::flags{debug};

      if(my $postback = $pending_data->{postback})
      {
        if($parcel->{status} eq 'success')
        {
          print "  calling postback\n" if $SNAG::flags{debug};
          $postback->( $parcel->{result} );
        }
        else
        {
          print "  NOT calling postback\n" if $SNAG::flags{debug};
        }
      }

      unless($parcel->{action} eq 'hold')
      {
        shift @{$heap->{client_queue}->{functions}->{$function}};

        unless(scalar @{$heap->{client_queue}->{functions}->{$function}} > 0)
        {
          delete $heap->{client_queue}->{functions}->{$function};
        }
      }
    }
  }
  else
  {
    $kernel->post("logger" => "log" => "SERVER ERROR: $heap->{name} received response yet has no pending data");
  }

  if($parcel->{status} eq 'error')
  {
    $kernel->post("logger" => "log" => "SERVER ERROR: $heap->{name} to $heap->{host} on $heap->{port}: action = $parcel->{action}, details = $parcel->{details}");
  }

  if($parcel->{action} eq 'hold')
  {
    $kernel->delay( 'send_parcel' => $hold_period );
  }
  else
  {
    $kernel->yield( 'send_parcel' );
  }
}

1;

