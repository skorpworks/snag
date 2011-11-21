package SNAG::Server::SystemInfo;
use base qw(SNAG::Server);

use strict;
use SNAG;
use POE;
use Carp qw(carp croak);
use FreezeThaw qw(thaw freeze cmpStr cmpStrHard);
use Date::Format;
use Date::Parse;
use Data::Dumper;

use DBI;
use Text::Diff;

my $rec_sep = REC_SEP;
my $debug   = $SNAG::flags{debug};
my $verbose = $SNAG::flags{verbose};

#### Specify any special instructions here
my $instructions = {
  conf => {
    'kernel_settings' => { 'nohistory' => 1, },

    'prtdiag' => { 'nohistory' => 1, },
  },

  arp => {
           'nohistory'   => 1,
           'nodashboard' => 1,
  },

  brmac => {
             'nohistory'   => 1,
             'nodashboard' => 1,
  },

  listening_ports => {
                       'nodashboard' => 1,
                       'nohistory'   => 1,
  },

  netapp_df => { 'ignore' => ['used'], },

  process => {
           'nohistory'   => 1,
           'nodashboard' => 1,
  },

};

################################
sub new
################################
{
  my $type = shift;
  $type->SUPER::new(@_);

  my %params = @_;
  my $args   = delete $params{Args};
  my $alias  = $params{Alias};

  croak "Args must be a hashref" if $args and ref $args ne 'HASH';

  my $database_info;
  my $name = delete $args->{name};
  $database_info->{$name} = $args;

  POE::Session->create(
    inline_states => {
      _start => sub {
        my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
        $kernel->alias_set('object');

        $kernel->yield('connect');
      },

      sysinfo_query => sub {
        my ( $kernel, $heap, $coderef, $sender ) = @_[ KERNEL, HEAP, ARG0, ARG1 ];

        if ( $heap->{dbh} && $heap->{connected} )
        {
          eval {
            $heap->{dbh}->begin_work();

            $coderef->(@_);

            $heap->{dbh}->commit();
          };
          if ($@)
          {
            $heap->{dbh}->rollback();

            ## What other 'server died' messages are there?
            if (    $@ =~ /terminating connection due to administrator command/
                 || $@ =~ /no connection to the server/
                 || $@ =~ /the database system is shutting down/
                 || $@ =~ /message type 0x[\d]+ arrived from server/
                 || $@ =~ /could not connect to server/
                 || $@ =~ /server closed the connection unexpectedly/ )
            {
              $kernel->post( 'logger' => 'alert' => { To => 'SNAGalerts@example.com', Subject => "Error on " . HOST_NAME . "::sysinfo::sysinfo_query::$sender", Message => $@ } );
              $kernel->post( 'logger' => 'log' => "$sender via sysinfo_query failed: $@" );
              delete $heap->{connected};
              $kernel->yield( 'connect' => 60 );
            }
          }
        }
        else
        {
          $kernel->post( 'logger' => 'log' => "Could not run $sender via $_[STATE], not connected to server" );
        }
      },

      build_monitor_defs => sub {
        my ( $heap, $kernel ) = @_[ HEAP, KERNEL ];

        my $coderef = sub {
          print "START build_monitor_defs ... " if $debug;

          my ( $heap, $kernel ) = @_[ HEAP, KERNEL ];

          my $monitor_defs;

          my $get_monitor_defs = $heap->{dbh}->selectall_arrayref( 'select * from monitor_defs', { Slice => {} } );
          foreach my $ref (@$get_monitor_defs)
          {
            next unless $ref->{toggle} eq 'on';

            my ($rules) = thaw( $ref->{rules} );

            $monitor_defs->{ $ref->{host} } = $rules;
          }

          $heap->{monitor_defs} = $monitor_defs;

          $kernel->delay( 'build_monitor_defs' => 600 );

          print "DONE!\n" if $debug;
        };

        $kernel->yield( 'sysinfo_query' => $coderef, $_[STATE] );
      },

      build_xen_uuids => sub {
        my ( $heap, $kernel ) = @_[ HEAP, KERNEL ];

        my $coderef = sub {
          print "START build_xen_uuids ... " if $debug;

          my ( $heap, $kernel ) = @_[ HEAP, KERNEL ];

          my $xen_uuids;

          my $get_uuids = $heap->{dbh}->selectall_arrayref('select lower(uuid) as uuid,host from device where vendor = \'Xen\'', { Slice => {} } );
          foreach my $ref (@$get_uuids)
          {
            $xen_uuids->{$ref->{uuid}} = $ref->{host};
          }

          $heap->{xen_uuids} = $xen_uuids;

          $kernel->delay( 'xen_uuids' => 600 );

          print "DONE!\n" if $debug;
        };

        $kernel->yield( 'sysinfo_query' => $coderef, $_[STATE] );
      },

      build_remote_hosts => sub {
        my ( $heap, $kernel ) = @_[ HEAP, KERNEL ];

        my $coderef = sub {
          print "START build_remote_hosts ... " if $debug;

          my ( $heap, $kernel ) = @_[ HEAP, KERNEL ];

          my ( $remote_hosts, $host_ips );

          my $get_ips = $heap->{dbh}->selectall_arrayref( "select iface.host as host, iface.ip as ip from iface, heartbeat where iface.host = heartbeat.host and heartbeat.activity = 'active'", { Slice => {} } );
          foreach my $ref (@$get_ips)
          {
            next unless $ref->{ip};

            push @{ $host_ips->{ $ref->{host} } }, $ref->{ip};

            $remote_hosts->{ips}->{ $ref->{ip} } = $ref->{host};
          }

          my $get_ports = $heap->{dbh}->selectall_arrayref( "select distinct(port) as port from heartbeat, listening_ports where listening_ports.host = heartbeat.host and heartbeat.activity = 'active'", { Slice => {} } );
          foreach my $ref (@$get_ports)
          {
            $remote_hosts->{ports}->{ $ref->{port} } = 1;
          }
          
          ## TODO put in remote IP and port kludge overrides

          ## TODO this can be to intensive to perform on the client side
          #$heap->{host_ips}     = $host_ips;
          #$heap->{remote_hosts} = $remote_hosts;
          $heap->{host_ips} = {};  
          $heap->{remote_hosts} = {};

          $kernel->delay( 'build_remote_hosts' => 3600 );

          print "DONE!\n" if $debug;
        };

        $kernel->yield( 'sysinfo_query' => $coderef, $_[STATE] );
      },

      ### THESE ARE THE SERVER FUNCTIONS
      host_passwd_login => sub {
        my ( $heap, $kernel, $input ) = @_[ HEAP, KERNEL, ARG0 ];

        my $coderef = sub {
          my ( $heap, $kernel, $input ) = @_[ HEAP, KERNEL, ARG2 ];

          print "STARTING host_passwd_login for $input->{uid} to $input->{dns} at $input->{seen}\n" if $debug;

          $heap->{sth}->{passwd_login}->execute( $input->{seen}, $input->{dns}, $input->{uid} ) or die $heap->{dbh}->errstr;

          $kernel->post( 'logger' => 'log' => "host_passwd_login: $input->{uid} to $input->{dns} at $input->{seen}" );

          print "DONE!\n" if $debug;
        };

        $kernel->yield( 'sysinfo_query' => $coderef, $_[STATE], $input );
      },

      sync_remote_hosts => sub {
        my ( $heap, $kernel, $input ) = @_[ HEAP, KERNEL, ARG0 ];

        unless ( $heap->{remote_hosts} )
        {

          #die "remote_hosts data is not currently populated, try again later";
          $kernel->post( 'logger' => 'log' => "remote_hosts data is not currently populated, try again later" );
        }

        return $heap->{remote_hosts};
      },
     
      sync_xen_uuids => sub {
        my ( $heap, $kernel, $input ) = @_[ HEAP, KERNEL, ARG0 ];

        unless ( $heap->{xen_uuids} )
        {
          $kernel->post( 'logger' => 'log' => "xen_uuids data is not currently populated, try again later" );
        }

        return $heap->{xen_uuids};
      },


      sync_monitor_defs => sub {
        my ( $heap, $kernel, $input ) = @_[ HEAP, KERNEL, ARG0 ];

        my $return;

        if ( $input->{host} )
        {
          $return = $heap->{monitor_defs}->{ $input->{host} } || {};
        }

        return $return;
      },

      load => sub {
        my ( $heap, $kernel, $parcel ) = @_[ HEAP, KERNEL, ARG0 ];

        die "Not connected to DB" unless $heap->{connected};

        eval {
          die "DBI->ping failed: no connection to the server" unless $heap->{dbh}->ping();

          $heap->{dbh}->begin_work();

          foreach my $row (@$parcel)
          {
            my ($system_info) = thaw($row);

            print Dumper $system_info if ( $debug && $verbose );

            unless ( $system_info->{host} )
            {
              die "system_info did not contain key 'host'\n" . Dumper $system_info;
            }
            unless ( $system_info->{seen} )
            {
              die "system_info did not contain key 'seen'\n" . Dumper $system_info;
            }

            my $host = delete $system_info->{host};
            $heap->{host} = $host;
            my $seen = delete $system_info->{seen};
            $heap->{seen} = $seen;
            my $no_heartbeat = delete $system_info->{no_heartbeat};

            unless ($no_heartbeat)
            {
              my $source = SCRIPT_NAME . ':load';

              unless ( $heap->{sth}->{hb_update}->execute( $seen, $host, $alias, $source ) == 1 )
              {
                $heap->{sth}->{hb_insert}->execute( $host, $alias, $source, $seen ) or die "Unable to update heartbeat: " . $heap->{sth}->errstr;

                $kernel->post( 'client' => 'dashboard' => 'load' => join $rec_sep, ( 'events', $host, 'sysinfo', 'new_host', 'new host reported in!', 'new host reported in!', '', $seen ) );
              }
            }

            print "$host\n" if $debug;

            foreach my $table ( keys %{$system_info} )
            {
              unless ( $heap->{cols}->{$table} )
              {
                $kernel->post( 'logger' => 'log' => "No table: $table" );
                next;
              }

              if ( $table eq 'tags' )
              {
                print "  updating tags\n" if $debug;

                my $new = $system_info->{tags};        
                my $cat;

                if($new->[0]->{category})
                {
                  $cat = $new->[0]->{category}; 
                  shift @$new;
                }
                else
                {
                  $cat = 'sysinfo';
                }

                if (@$new)
                {
                  $heap->{sth}->{tags_delete}->execute($host, $cat) or die $heap->{dbh}->errstr . ": Could not delete $host data from tags";

                  foreach my $ref (@$new)
                  {
                    $heap->{sth}->{tags_insert}->execute( $host, $seen, $ref->{tag}, $cat,( $ref->{multi} || '' ) ) or die ": Could not update tags table on host '$host': " . $heap->{dbh}->errstr . "\n" . Dumper $new;
                  }
                }
              }
              elsif ( $table eq 'conf' )
              {
                foreach my $conf ( keys %{ $system_info->{$table} } )
                {
                  print "  conf $conf ... " if $debug;

                  my ( $new_contents, $old_contents );

                  unless ( $new_contents = $system_info->{$table}->{$conf}->{contents} )
                  {
                    $new_contents = '';
                  }

                  my $fetch_old = $heap->{dbh}->selectrow_hashref("select * from $table where host = '$host' and source = '$conf'");
                  if ($fetch_old)
                  {
                    $old_contents = $fetch_old->{contents};
                  }
                  else
                  {
                    $old_contents = '';
                  }

                  unless ( $old_contents eq $new_contents )
                  {
                    print "changed!\n" if $debug;

                    $heap->{sth}->{$table}->{'delete'}->execute( $host, $conf ) or die $heap->{dbh}->errstr;

                    my $insert_args = { host => $host, seen => $seen, source => $conf, contents => $new_contents, table => $table };

                    $heap->{sth}->{$table}->{insert}->execute( map { $insert_args->{$_} } @{ $heap->{cols}->{$table} } ) or die ": Could not insert new data on host '$host', table '$table': " . $heap->{dbh}->errstr;

                    unless ( $instructions->{$table}->{$conf}->{nohistory} )
                    {
                      $old_contents .= "\n" if ( $old_contents && $old_contents !~ /\n$/ );
                      $new_contents .= "\n" if ( $new_contents && $new_contents !~ /\n$/ );

                      my $diff = diff \$old_contents, \$new_contents, { CONTEXT => 0 };
                      print "$diff\n" if $debug;

                      $heap->{sth}->{archive}->execute( $host, $table, $conf, $new_contents, $diff, $seen ) or die $heap->{dbh}->errstr;

                      unless ( $instructions->{$table}->{$conf}->{nodashboard} )
                      {
                        my $new_hid = $heap->{dbh}->last_insert_id( undef, undef, undef, undef, { sequence => 'hist_index_seq' } );
                        $kernel->post( 'client' => 'dashboard' => 'load' => join $rec_sep, ( 'events', $host, 'sysinfo', 'config_change', 'sysinfo configuration change', "$conf was changed", $new_hid, $seen ) );
                      }
                    }

                    ### post processing!
                    if ( $conf eq '/etc/passwd' )
                    {
                      my ( $passwd, $seen_uids );

                      foreach my $line ( split /\n/, $old_contents )
                      {
                        next if $line =~ /^\s*$/;
                        next if $line =~ /^#/;

                        my @fields = split /:/, $line;

                        next if $seen_uids->{old_contents}->{ $fields[0] }++;

                        $passwd->{old_contents}->{ shift @fields } = \@fields;
                      }

                      foreach my $line ( split /\n/, $new_contents )
                      {
                        next if $line =~ /^\s*$/;
                        next if $line =~ /^#/;

                        my @fields = split /:/, $line;

                        next if $seen_uids->{new_contents}->{ $fields[0] }++;

                        $passwd->{new_contents}->{ shift @fields } = \@fields;
                      }

                      foreach my $uid ( keys %{ $passwd->{old_contents} } )
                      {
                        unless ( $passwd->{new_contents}->{$uid} )
                        {
                          $kernel->post( 'logger' => 'log' => "host_passwd: removed $uid from $host" );
                          $heap->{sth}->{passwd_remove}->execute( $seen, $host, $uid ) or die $heap->{dbh}->errstr;
                        }
                      }

                      foreach my $uid ( keys %{ $passwd->{new_contents} } )
                      {
                        unless ( cmpStr( $passwd->{old_contents}->{$uid}, $passwd->{new_contents}->{$uid} ) == 0 )
                        {
                          my @args = @{ $passwd->{new_contents}->{$uid} };

                          if ( defined $passwd->{old_contents}->{$uid} )
                          {
                            $kernel->post( 'logger' => 'log' => "host_passwd: changed $uid on $host" );
                            $heap->{sth}->{passwd_change}->execute( @args[ 0 .. 5 ], $host, $uid ) or die $heap->{dbh}->errstr;
                          }
                          else
                          {
                            $kernel->post( 'logger' => 'log' => "host_passwd: added $uid to $host" );
                            $heap->{sth}->{passwd_add}->execute( $host, $uid, @args[ 0 .. 5 ], $seen ) or die $heap->{dbh}->errstr;
                          }
                        }
                      }
                    }
                  }
                  else
                  {
                    print "no change\n" if $debug;
                  }
                }
              }
              else
              {
                my ( $new_data, $old_data );

                print "  $table ... " if $debug;

                if ( $new_data = $system_info->{$table} )
                {
                  unless ( ref $new_data eq 'ARRAY' )
                  {
                    $new_data = [$new_data];
                  }

                  foreach my $ref (@$new_data)
                  {
                    while ( my ( $key, $val ) = each %$ref )
                    {
                      unless ( defined $val )
                      {
                        delete $ref->{$key};
                      }

                      if ( $table eq 'iface' )
                      {
                        if ( $val eq '' )
                        {
                          delete $ref->{$key};
                        }

                        if ( $key eq 'mac' and $val eq '00' )
                        {
                          $ref->{$key} = '00:00:00:00:00:00';
                        }
                      }
                    }

                    if ( defined $instructions->{$table}->{ignore} )
                    {
                      if ( ref $instructions->{$table}->{ignore} eq 'ARRAY' )
                      {
                        foreach my $key ( @{ $instructions->{$table}->{ignore} } )
                        {
                          delete $ref->{$key};
                        }
                      }
                      else
                      {
                        $kernel->post( 'logger' => 'log' => "ignore key for $table needs to be an arrayref" );
                      }
                    }
                  }
                }
                else
                {
                  $new_data = [];
                }

                my $fetch_old = $heap->{dbh}->selectall_arrayref( "select * from $table where host = '$host'", { Slice => {} } );
                if ($fetch_old)
                {
                  foreach my $ref (@$fetch_old)
                  {
                    delete $ref->{seen};
                    delete $ref->{host};

                    while ( my ( $key, $val ) = each %$ref )
                    {
                      unless ( defined $val )
                      {
                        delete $ref->{$key};
                      }
                    }
                  }

                  $old_data = $fetch_old;
                }
                else
                {
                  $old_data = [];
                }

                unless ( cmpStr( $old_data, $new_data ) == 0 )
                {
                  my $old_data_flat = flatten_struct( $old_data, $heap->{cols}->{$table} );
                  my $new_data_flat = flatten_struct( $new_data, $heap->{cols}->{$table} );

                  $old_data_flat .= "\n" if ( $old_data_flat && $old_data_flat !~ /\n$/ );
                  $new_data_flat .= "\n" if ( $new_data_flat && $new_data_flat !~ /\n$/ );

                  if ( my $diff = diff \$old_data_flat, \$new_data_flat, { CONTEXT => 0 } )
                  {
                    print "changed!\n" if $debug;
                    print "$diff\n"    if $debug;

                    $heap->{sth}->{$table}->{'delete'}->execute($host) or die $heap->{dbh}->errstr;

                    foreach my $ref (@$new_data)
                    {
                      next unless %$ref;
                      my $insert_args = { host => $host, seen => $seen, %$ref, table => $table };
                      $heap->{sth}->{$table}->{insert}->execute( map { $insert_args->{$_} } @{ $heap->{cols}->{$table} } )
                        or die ": Could not insert new data on host '$host', table '$table': " . $heap->{dbh}->errstr . "\n========Dump of problem data hash===========\n" . Dumper $insert_args;
                    }

                    unless ( $instructions->{$table}->{nohistory} )
                    {
                      $heap->{sth}->{archive}->execute( $host, $table, '', $new_data_flat, $diff, $seen ) or die $heap->{dbh}->errstr;

                      unless ( $instructions->{$table}->{nodashboard} )
                      {
                        my $new_hid = $heap->{dbh}->last_insert_id( undef, undef, undef, undef, { sequence => 'hist_index_seq' } );
                        $kernel->post( 'client' => 'dashboard' => 'load' => join $rec_sep, ( 'events', $host, 'sysinfo', 'config_change', 'sysinfo configuration change', "$table was changed", $new_hid, $seen ) );
                      }
                    }
                  }
                  else
                  {
                    print "no change (check 2)\n" if $debug;
                  }
                }
                else
                {
                  print "no change (check 1)\n" if $debug;
                }
              }
            }
          }

          $heap->{dbh}->commit();
        };
        if ($@)
        {
          $heap->{dbh}->rollback();

          ## What other 'server died' messages are there?
          if (    $@ =~ /terminating connection due to administrator command/
               || $@ =~ /no connection to the server/
               || $@ =~ /the database system is shutting down/
               || $@ =~ /message type 0x[\d]+ arrived from server/
               || $@ =~ /could not connect to server/
               || $@ =~ /server closed the connection unexpectedly/ )
          {
            $kernel->post( 'logger' => 'alert' => { From => 'SNAGcnb@asu.edu', To => 'sporkworks@asu.edu', Subject => "Error on " . HOST_NAME . "::sysinfo", Message => $@ } );
            $kernel->post( 'logger' => 'log' => $@ );
            delete $heap->{connected};
            $kernel->yield( 'connect' => 60 );
            return "Lost DB Connection";
          }
          elsif ( $@ =~ /Do not know how to thaw data with code/ )
          {
            $kernel->post( 'logger' => 'log' => "Problem thawing, skipping this one: $@" );
          }
          else
          {
            my $msg = "DB Load Error: $@: ";
            $kernel->post( 'client' => 'dashboard' => 'load' => join $rec_sep, ( 'events', $heap->{host}, 'sysinfo', 'database error', 'DB load error', $@, '', $heap->{seen} ) );
            print "$msg\n" if $debug;
            $kernel->post( 'logger' => 'log' => $msg );
          }
        }
        return 0;
      },

      connect => sub {
        my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];

        delete $heap->{connected};
        delete $heap->{dbh};

        my $db_args = $database_info->{sysinfo};

        eval {
          my $dbh;
          $dbh = DBI->connect( $db_args->{dsn}, $db_args->{user}, $db_args->{pw}, { RaiseError => 0, AutoCommit => 1 } ) or die $DBI::errstr;
          $heap->{dbh} = $dbh;

          my $get_tables = $heap->{dbh}->table_info( '', 'public', '%', 'TABLE' );
          my $tables = $heap->{dbh}->selectcol_arrayref( $get_tables, { Columns => [3] } );

          foreach my $table (@$tables)
          {
            my $get_cols = $heap->{dbh}->column_info( '', '', $table, '' ) or die $heap->{dbh}->errstr;
            $heap->{cols}->{$table} = $heap->{dbh}->selectcol_arrayref( $get_cols, { Columns => [4] } );

            my $insert_sql = "insert into $table (" . ( join ", ", @{ $heap->{cols}->{$table} } ) . ") " . "values (" . ( join ", ", map { '?' } map { s/\"//g } @{ $heap->{cols}->{$table} } ) . ")";

            $heap->{sth}->{$table}->{insert} = $heap->{dbh}->prepare($insert_sql);

            if ( $table eq 'conf' )
            {
              $heap->{sth}->{$table}->{'delete'} = $heap->{dbh}->prepare("delete from $table where host = ? and source = ?");
            }
            else
            {
              $heap->{sth}->{$table}->{'delete'} = $heap->{dbh}->prepare("delete from $table where host = ?");
            }
          }

          $heap->{sth}->{hb_insert} = $heap->{dbh}->prepare("insert into server_heartbeats(host, server, source, seen, server_seen) values(?, ?, ?, ?, now() )");
          $heap->{sth}->{hb_update} = $heap->{dbh}->prepare("update server_heartbeats set seen = ?, server_seen = now() where host = ? and server = ? and source = ?");

          $heap->{sth}->{archive} = $heap->{dbh}->prepare("insert into hist(host, tab, source, data, diff, seen) values(?, ?, ?, ?, ?, ?)");

          $heap->{sth}->{tags_delete} = $heap->{dbh}->prepare("delete from tags where host = ? and category = ?");
          $heap->{sth}->{tags_insert} = $heap->{dbh}->prepare("insert into tags (host, seen, tag, category, multi) values (?, ?, ?, ?, ?)");

          $heap->{sth}->{passwd_add}    = $heap->{dbh}->prepare("insert into host_passwd(host, name, passwd, uid, gid, gecos, dir, shell, date_added) values(?, ?, ?, ?, ?, ?, ?, ?, ?)");
          $heap->{sth}->{passwd_remove} = $heap->{dbh}->prepare("update host_passwd set date_removed = ? where host = ? and name = ?");
          $heap->{sth}->{passwd_change} = $heap->{dbh}->prepare("update host_passwd set passwd = ?, uid = ?, gid = ?, gecos = ?, dir = ?, shell = ? where host = ? and name = ?");
          $heap->{sth}->{passwd_login}  = $heap->{dbh}->prepare("update host_passwd set last_login = ? where host = (select heartbeat.host from dns_aliases, heartbeat where heartbeat.host = dns_aliases.host and alias = ? order by heartbeat.seen desc limit 1) and name = ?");
        };
        if ($@)
        {
          $kernel->post( 'logger' => 'log' => "SystemInfo DB: failed to connect to $db_args->{dsn}: $@" );
          $kernel->delay( $_[STATE] => 10 );
        }
        else
        {
          $kernel->post( 'logger' => 'log' => "SystemInfo DB: connected to $db_args->{dsn}" );
          $heap->{connected} = 1;

          $kernel->delay( 'build_remote_hosts' => 5 );
          $kernel->delay( 'build_monitor_defs' => 5 );
        }
      },
    }
  );
}

sub flatten_struct
{
  my ( $data, $table_cols ) = @_;

  my $return = '';

  #if data is just an empty arrayref, just pass back empty string
  if ( $data && @$data )
  {
    if ( $#$data == 0 )
    {
      my $exist_keys = scalar keys %{ $data->[0] };
      unless ($exist_keys)
      {
        return $return;
      }
    }

    ### if the first col exists in table_cols, sort data by it, if not, leave alone
    eval {
      my $first_col = $table_cols->[1];
      if ( exists $data->[0]->{$first_col} )
      {
        $data = [ sort { $a->{$first_col} cmp $b->{$first_col} } @$data ];
      }
    };

    $return = join "---------------------------------------\n", map {
      my $flat;

      foreach my $col (@$table_cols)
      {
        next if $col eq 'host';
        next if $col eq 'seen';

        $flat .= "$col:  $_->{$col}\n";
      }

      $flat
    } @$data;
  }

  return $return;
}

1;
