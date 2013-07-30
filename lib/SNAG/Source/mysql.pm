package SNAG::Source::mysql; use base qw/SNAG::Source/;

use strict;
use SNAG;

use FreezeThaw qw/freeze/;
use Date::Format;

use POE;
use POE::Wheel::Run;
use Carp qw(carp croak);
use Data::Dumper;
#use URI::Escape;

my $mapping = {
'aborted_clients' => 'd',
'aborted_connects' => 'd',
'bytes_received' => 'd',
'bytes_sent' => 'd',
'com_admin_commands' => 'd',
'com_begin' => 'd',
'com_change_db' => 'd',
'com_check' => 'd',
'com_commit' => 'd',
'com_delete' => 'd',
'com_flush' => 'd',
'com_grant' => 'd',
'com_insert' => 'd',
'com_lock_tables' => 'd',
'com_optimize' => 'd',
'com_purge' => 'd',
'com_rollback' => 'd',
'com_select' => 'd',
'com_set_option' => 'd',
'com_show_charsets' => 'd',
'com_show_collations' => 'd',
'com_show_create_table' => 'd',
'com_show_databases' => 'd',
'com_show_fields' => 'd',
'com_show_grants' => 'd',
'com_show_processlist' => 'd',
'com_show_slave_hosts' => 'd',
'com_show_status' => 'd',
'com_show_tables' => 'd',
'com_show_variables' => 'd',
'com_show_warnings' => 'd',
'com_truncate' => 'd',
'com_unlock_tables' => 'd',
'com_update' => 'd',
'connections' => 'd',
'created_tmp_disk_tables' => 'd',
'created_tmp_files' => 'd',
'created_tmp_tables' => 'd',
'flush_commands' => 'd',
'handler_delete' => 'd',
'handler_read_first' => 'd',
'handler_read_key' => 'd',
'handler_read_next' => 'd',
'handler_read_rnd' => 'd',
'handler_read_rnd_next' => 'd',
'handler_update' => 'd',
'handler_write' => 'd',
'key_blocks_used' => 'd',
'key_read_requests' => 'd',
'key_reads' => 'd',
'key_write_requests' => 'd',
'key_writes' => 'd',
'max_used_connections' => 'g',
'opens' => 'd',
'opened_tables' => 'd',
'open_files' => 'g',
'open_tables' => 'g',
'qcache_free_blocks' => 'g',
'qcache_free_memory' => 'g',
'qcache_hits' => 'd',
'qcache_inserts' => 'd',
'qcache_not_cached' => 'd',
'qcache_queries_in_cache' => 'g',
'qcache_total_blocks' => 'g',
'questions' => 'd',
'queries_per_second_avg' => 'g',
'select_range' => 'd',
'select_scan' => 'd',
'slow_launch_threads' => 'd',
'slow_queries' => 'd',
'sort_merge_passes' => 'd',
'sort_range' => 'd',
'sort_rows' => 'd',
'sort_scan' => 'd',
'table_locks_immediate' => 'd',
'table_locks_waited' => 'd',
'threads_cached' => 'g',
'threads_connected' => 'd',
'threads_created' => 'd',
'threads_running' => 'g',
'uptime' => 'g',
              };

#################################
sub new
#################################
{
  my $package = shift;
  $package->SUPER::new(@_);

  my $mi = $package . '->new()';

  croak "$mi requires an even number of parameters" if ( @_ & 1 );
  my %params = @_;

  croak "$mi needs an Alias parameter" unless exists $params{Alias};
  my $alias = delete $params{Alias};

  foreach my $key ( keys %params )
  {
    warn "Unknown parameter $key";
  }

  my $debug = $SNAG::flags{debug};

  POE::Session->create(
    inline_states => {
      _start => sub
      {
        my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];

        $heap->{epoch}     = int( time() + 1 );
        $heap->{next_time} = $heap->{epoch};
        while ( ++$heap->{next_time} % 60 ) { }

        $kernel->alias_set($alias);
        $kernel->alarm( 'my_server_stats' => $heap->{next_time} );
      },

      my_server_stats => sub
      {
        my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
        $heap->{next_time} += 60;
        $kernel->alarm( $_[STATE] => $heap->{next_time} );

        if ( $heap->{child} )
        {
          $kernel->call('logger' => "log" => "SNAG::Source::mysql: my_server_stats is still running, skipping" );
        }
        else
        {
          $kernel->call('logger' => "log" => "SNAG::Source::mysql: my_server_stats is starting" ) if $debug;
          $heap->{this_time} = $heap->{next_time} - 60;
          $heap->{child} = POE::Wheel::Run->new(
                                                 Program      => ['mysql -u snag --password=snag -e "show status"; mysql -u snag --password=snag -e "status"'],
                                                 StdioFilter  => POE::Filter::Line->new(),
                                                 StderrFilter => POE::Filter::Line->new(),
                                                 StdoutEvent  => 'my_server_stats_stdio',
                                                 StderrEvent  => 'my_server_stats_stderr',
                                                 CloseEvent   => "my_server_stats_close",
                                               );
          $kernel->call('logger' => "log" => "SNAG::Source::mysql: my_server_stats is started" ) if $debug;
          $kernel->sig_child( $heap->{child}->PID, "catch_sigchld" );
        }
      },

      my_server_stats_stdio => sub
      {
        my ( $kernel, $heap, $input ) = @_[ KERNEL, HEAP, ARG0 ];

        if ( $input =~ /^([\w\_]+)\s+(\d+)$/ )
        {
          my ($stat) = lc($1);
          #$kernel->call('logger' => "log" => "SNAG::Source::mysql: $stat: " . uri_escape($input)) if $debug;
          $kernel->post( "client" => "sysrrd" => "load" => join ':', ( HOST_NAME, 'my_' . $stat, '1' . $mapping->{$stat}, $heap->{this_time}, $2) ) if ($mapping->{$stat}) && $2 > 0;
        }
        elsif ($input =~ m/^Threads:/)
        {
          my (@tuples, $tuple);
          @tuples = split /  /, $input;
          foreach $tuple (@tuples)
          {
            if ( $tuple =~ /^([\w\s]+):\s+([\d\.]+)/ )
            {
              my($ds, $value) = (lc($1),$2);
              $ds =~ s/ /_/g;
              $kernel->post( "client" => "sysrrd" => "load" => join ':', ( HOST_NAME, 'my_' . lc($ds), '1' . $mapping->{$ds}, $heap->{this_time}, $value ) ) if ($mapping->{$ds});
            }
          }
        }
      },

      my_server_stats_stderr => sub
      {
        my ( $kernel, $heap, $input ) = @_[ KERNEL, HEAP, ARG0 ];
        $kernel->call('logger' => "log" => "SNAG::Source::mysql: $input" ) if $debug;
      },

      my_server_stats_close => sub
      {
        my ( $kernel, $heap, $wid ) = @_[ KERNEL, HEAP, ARG0 ];
        my $child = delete $heap->{child};
        $kernel->call('logger' => "log" => "SNAG::Source::mysql: completed" ) if $debug;
      },

      catch_sigchld => sub
      {
        my ( $kernel, $heap, $wid ) = @_[ KERNEL, HEAP, ARG0 ];
        my $child = delete $heap->{child};
        $kernel->call('logger' => "log" => "SNAG::Source::mysql: completed" ) if $debug;
      },

    }
  );
}

1;

