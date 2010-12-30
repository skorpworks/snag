package SNAG::Source::mysql; use base qw/SNAG::Source/;

use strict;
use SNAG;

use FreezeThaw qw/freeze/;
use Date::Format;

use POE;
use POE::Wheel::Run;
use Carp qw(carp croak);
use Data::Dumper;

my $mapping = {
                'Aborted_clients'        => 'c',
                'Aborted_connects'       => 'c',
                'Connections'            => 'c',
                'Max_used_connections'   => 'g',
                'Open_tables'            => 'g',
                'Questions'              => 'c',
                'Table_locks_immediate'  => 'c',
                'Table_locks_waited'     => 'c',
                'Threads_connected'      => 'g',
                'Threads_created'        => 'c',
                'Threads_running'        => 'g',
                'Uptime'                 => 'g',
                'Slow_queries'           => 'c',
                'Opens'                  => 'c', 
                'Queries_per_second_avg' => 'g',
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
        $kernel->alarm( 'server_stats' => $heap->{next_time} );
      },

      server_stats => sub
      {
        my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
        $heap->{next_time} += 60;
        $kernel->alarm( $_[STATE] => $heap->{next_time} );

        if ( $heap->{child} )
        {
          $kernel->post( "logger" => "log" => "SNAG::Source::mysql: server_stats is still running, skipping" );
        }
        else
        {
          $kernel->post( "logger" => "log" => "SNAG::Source::mysql: server_stats is starting" ) if $debug;
          $heap->{this_time} = $heap->{next_time} - 60;
          $heap->{child} = POE::Wheel::Run->new(
                                                 Program      => 'echo "status;show status;" | mysql -u snag --password=snag',
                                                 StdioFilter  => POE::Filter::Line->new(),
                                                 StderrFilter => POE::Filter::Line->new(),
                                                 StdoutEvent  => 'server_stats_stdio',
                                                 StderrEvent  => 'server_stats_stderr',
                                                 CloseEvent   => "server_stats_close",
                                               );
          $kernel->post( "logger" => "log" => "SNAG::Source::mysql: server_stats is started" ) if $debug;
          $kernel->sig_child( $heap->{child}->PID, "catch_sigchld" );
        }
      },

      server_stats_stdio => sub
      {
        my ( $kernel, $heap, $input ) = @_[ KERNEL, HEAP, ARG0 ];

        if ( $input =~ /^([\w\_]+)\s+(\d+)$/ )
        {
	  $kernel->post( "client" => "sysrrd" => "load" => join ':', ( HOST_NAME, 'my_' . lc($1), '1' . $mapping->{$1}, $heap->{this_time}, $2) ) if ($mapping->{$1}) && $1 > 0;
        }
	elsif ($input =~ m/^Threads:/) 
	{
	  my (@tuples, $tuple);
	  @tuples = split /  /, $input; 
	  foreach $tuple (@tuples) 
	  { 
            if ( $tuple =~ /^([\w\s]+):\s+([\d\.]+)/ )
	    {
	    print "2!!!!!!!!! $1 !!!!!!!!!!\n";
	      my($ds, $value) = ($1,$2);
	      $ds =~ s/ /_/g;
	      $kernel->post( "client" => "sysrrd" => "load" => join ':', ( HOST_NAME, 'my_' . lc($ds), '1' . $mapping->{$ds}, $heap->{this_time}, $value ) ) if ($mapping->{$ds});
	    }
	  } 
        }
      },

      server_stats_stderr => sub
      {
        my ( $kernel, $heap, $input ) = @_[ KERNEL, HEAP, ARG0 ];
        $kernel->post( "logger" => "log" => "SNAG::Source::mysql: $input" ) if $debug;
      },

      server_stats_close => sub
      {
        my ( $kernel, $heap, $wid ) = @_[ KERNEL, HEAP, ARG0 ];
        my $child = delete $heap->{child};
        $kernel->post( "logger" => "log" => "SNAG::Source::mysql: completed" ) if $debug;
      },

      catch_sigchld => sub
      {
        my ( $kernel, $heap, $wid ) = @_[ KERNEL, HEAP, ARG0 ];
        my $child = delete $heap->{child};
        $kernel->post( "logger" => "log" => "SNAG::Source::mysql: completed" ) if $debug;
      },

    }
  );
}

1;
