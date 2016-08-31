package SNAG::Server::Master; 
use base qw(SNAG::Server);

use strict;
use SNAG;
use POE;
use Carp qw(carp croak);
use FreezeThaw qw(thaw freeze cmpStr cmpStrHard);
use Date::Format;
use Data::Dumper;
use Net::Patricia;

use DBI;

my $rec_sep = REC_SEP;
my $debug = $SNAG::flags{debug};
my $verbose = $SNAG::flags{verbose};
# Server error codes
my $error_regex = qr/terminating connection due to administrator command|no connection to the server|the database system is shutting down|message type 0x[\d]+ arrived from server|could not connect to server|server closed the connection unexpectedly/;

################################
sub new
################################
{
  my $type = shift;
  $type->SUPER::new(@_);

  my %params = @_;
  my $args = delete $params{Args};
  my $alias = $params{Alias};

  croak "Args must be a hashref" if $args and ref $args ne 'HASH';
  croak "Args must contain values for 'dsn', 'user', and 'pw'" unless ($args->{dsn} && $args->{user} && $args->{pw});

  $args->{dsn} =~ /^DBI:(\w+):/i;
  my $driver = lc $1;
  croak "Unsupported DB driver ($driver)" unless $driver =~ /^(pg|mysql)$/;

  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->alias_set('object');

        $kernel->yield('connect');
      },

      build_server_mappings => sub
      {
        my ($heap, $kernel) = @_[ HEAP, KERNEL ];
        $kernel->delay($_[STATE] => 600);

        ### does this even need to run more than once?  Should I just run it to compare memory with the db, it should never be different

        print "START build_server_mappings ... " if $debug;

        eval
        {
          my $new_data;

          my $get_server_definitions = $heap->{dbh}->selectall_arrayref('select * from SNAG_server_definitions', { Slice => {} });
          foreach my $ref (@$get_server_definitions)
          {
            $ref->{mappings} = 0;
            $new_data->{server}->{id}->{ $ref->{id} } = $ref;
            push @{$new_data->{server}->{name}->{ $ref->{name} }}, $ref;
          }

          my $get_server_mappings = $heap->{dbh}->selectall_arrayref('select * from SNAG_server_mappings', { Slice => {} });
          foreach my $ref (@$get_server_mappings) 
          {
            $new_data->{mapping}->{ $ref->{name} }->{ $ref->{host} } = $new_data->{server}->{id}->{ $ref->{server_id} };

            $new_data->{server}->{id}->{ $ref->{server_id} }->{mappings}++;
          }

          $heap->{server_data} = $new_data; 
        };
        if($@ =~ /$error_regex/) 
        {
          $kernel->call('logger' => 'alert' => { To => 'example@foobar.com', Subject => "Error on " . HOST_NAME . ' SNAG::Server::Master', Message => $@ } );
          delete $heap->{connected};
          $kernel->yield('connect' => 60);
        }
        
        print "DONE!\n" if $debug;
      },

     get_server_info => sub
      {
        my ($heap, $kernel, $input) = @_[HEAP, KERNEL, ARG0];

        if($heap->{server_data})
        {
          if(my $info = $heap->{server_data}->{mapping}->{ $input->{name} }->{ $input->{client_host} })
          {
            if($SNAG::flags{debug})
            {
              print "Returning existing mapping\n";
              print Dumper $info;
            }

            return $info;
          }
          else
          {
            ### make a mapping
            my $servers = $heap->{server_data}->{server}->{name}->{ $input->{name} };

            if($servers)
            {
              my ($info, $lowest_count);

              foreach my $ref (@$servers)
              {
                if(not defined $lowest_count || ( $ref->{mappings} < $lowest_count ) )
                {
                  $info = $ref;
                  $lowest_count = $ref->{mappings};
                }
              }
              eval
              {
                $heap->{sth}->{insert_server_mapping}->execute( $info->{id}, $input->{client_host}, $input->{name} ) or die $heap->{dbh}->errstr;

                $heap->{server_data}->{mapping}->{ $input->{name} }->{ $input->{client_host} } = $info;                                                                      $heap->{server_data}->{server}->{id}->{ $info->{id} }->{mappings}++;

                if($SNAG::flags{debug})
                {
                  print "Created new mapping for: host => $input->{client_host}, name => $input->{name} to server_id => $info->{id}\n";
                  print Dumper $info;
                }
              };
              if($@)
              {
                if($@ =~ /$error_regex/) 
                {
                  $kernel->call('logger' => 'alert' => { To => 'SNAGalerts@example.com', Subject => "Error on " . HOST_NAME . ' SNAG::Server::Master', Message => $@ } ); #TODO
                  delete $heap->{connected};
                  $kernel->yield('connect' => 60);
                }
                else
                {
                  $kernel->call('logger' => 'log' => "error inserting server mapping for $input->{client_host}, $info->{name}: $@");
                }
              }
              else
              {
                return $info;
              }
            }
            else
            {
              $kernel->call('logger' => 'log' => "$input->{client_host} requested info for nonexistant '$info->{name}' server");
            }
          }
        }
       else
        {
          #die "remote_hosts data is not currently populated, try again later";
          $kernel->call('logger' => 'log' => "remote_hosts data is not currently populated, try again later");
        }
      },

      build_domain_map => sub
      {
        my ($heap, $kernel) = @_[ HEAP, KERNEL ];
	$kernel->delay($_[STATE] => 300); # run every 5 min

	print "START build_domain_map...\n" if $debug;

	eval
	{
          my $get_nets = $heap->{dbh}->selectall_hashref("select subnet, pop, domain, override from domain_map", "subnet");
	  delete $heap->{netpat};
	  delete $heap->{netmap};
	  $heap->{netpat} = Net::Patricia->new;
	  foreach my $key (keys %$get_nets)
	  {
            $heap->{netpat}->add_string($key);
	  }
	  $heap->{netmap} = $get_nets;
	};
	if($@)
	{
          $kernel->call('logger' => 'log' => "ERROR: " . $@);
	}
      },

      get_domain => sub
      {
        my ($heap, $kernel, $input) = @_[HEAP, KERNEL, ARG0];

        my $ip = $input->{ip};
	my $raw_hostname = $input->{raw_hostname};
	print "Finding domain for IP: $ip and client host $raw_hostname\n" if $SNAG::flags{debug};
        my $return->{hostname} = $input->{raw_hostname};
        print Dumper($heap->{netmap}); 
        if(defined $heap->{netpat} && defined $heap->{netmap} && defined $ip)
	{
	  my $sub = $heap->{netpat}->match_string($ip);
	  if(defined $sub && defined $heap->{netmap}->{$sub})
	  {
	    if(($return->{hostname} =~ /\./) && ($heap->{netmap}->{$sub}->{override} == 1))
	    {
	      $return->{hostname} =~ s/\..*$//g;
	      if(defined $heap->{netmap}->{$sub}->{pop} && $heap->{netmap}->{$sub}->{pop} ne "")
	      {
	        $return->{hostname} .= "." . $heap->{netmap}->{$sub}->{pop};
	      }	
	      if(defined $heap->{netmap}->{$sub}->{domain} && $heap->{netmap}->{$sub}->{domain} ne "")
	      {
	        $return->{hostname} .= "." . $heap->{netmap}->{$sub}->{domain};
              }
	    }
	    elsif($return->{hostname} !~ /\./)
	    {
	      if(defined $heap->{netmap}->{$sub}->{pop} && $heap->{netmap}->{$sub}->{pop} ne "")
	      {
	        $return->{hostname} .= "." . $heap->{netmap}->{$sub}->{pop};
	      }	
	      if(defined $heap->{netmap}->{$sub}->{domain} && $heap->{netmap}->{$sub}->{domain} ne "")
	      {
	        $return->{hostname} .= "." . $heap->{netmap}->{$sub}->{domain};
              }
	    }
	  }
	}
        if($SNAG::flags{debug})
	{
	  print "Returning hostname: " . Dumper($return);
	}
	return $return;
      },

      build_update_queue => sub
      {
        my ($heap, $kernel) = @_[ HEAP, KERNEL ];
        $kernel->delay($_[STATE] => 300);

        print "START build_update_queue... \n" if $debug;

        eval
        {
          my $data = ();

          my $query = $heap->{dbh}->prepare('select * from update_queue,update_payload where NOT is_complete order by time_created desc');
          $query->execute;
          while(my $ref = $query->fetchrow_hashref)
          {
          	next if ($data->{$ref->{host}}); 	
					  $data->{$ref->{host}}->{file} = $ref->{filename};
            $data->{$ref->{host}}->{payload_id} = $ref->{payload_id};
            $data->{$ref->{host}}->{signature} = $ref->{signature};
          }
          print "Update Queue: " . Dumper($data);
          $heap->{update_queue} = $data;
        };
        if($@ =~ /$error_regex/) 
        {
          $kernel->call('logger' => 'alert' => { To => 'SNAGalerts@example.com', Subject => "Error on " . HOST_NAME . ' SNAG::Server::Master', Message => $@ } );
          delete $heap->{connected};
          $kernel->yield('connect' => 60);
        }

        print "DONE!\n" if $debug;
      },

      get_avail_updates => sub
      {
        my ($heap, $kernel, $input) = @_[HEAP, KERNEL, ARG0];
                   
        my $host = $input->{client_host};
        print "Looking for updates for $host\n";
        
        my $return;
        $return->{file} = $heap->{update_queue}->{$host}->{file} || 0;
        $return->{signature} = $heap->{update_queue}->{$host}->{signature} || 0;
        $return->{payload_id} = $heap->{update_queue}->{$host}->{payload_id} || 0;
        print "Sending update info: " . Dumper($return);
				return $return;                                
      },

      connect => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        delete $heap->{connected};
        delete $heap->{dbh};

        eval
        {
          my $dbh;
          $dbh = DBI->connect($args->{dsn}, $args->{user}, $args->{pw}, {RaiseError => 0, AutoCommit => 1}) or die $DBI::errstr;
          $heap->{dbh} = $dbh;
  
          $kernel->yield('build_server_mappings');
          $kernel->yield('build_domain_map');
          $kernel->delay('build_update_queue' => '5');

          $kernel->call('logger' => 'log' => "SystemInfo DB: connected to $args->{dsn}");
          $heap->{connected} = 1;

          $heap->{sth}->{insert_server_mapping} = $heap->{dbh}->prepare('insert into SNAG_server_mappings(server_id, host, name) values(?, ?, ?)');
        };
        if($@)
        {
          $kernel->call('logger' => 'log' => "SystemInfo DB: failed to connect to $args->{dsn}: $@");
          $kernel->delay($_[STATE] => 10 );
        }
      },
    }
  );
}

1;
