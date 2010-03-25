package SNAG::Source::monitor;
use base qw/SNAG::Source/;

use strict;
use SNAG;

use FreezeThaw qw/freeze/;
use Date::Format;
use IO::Socket::INET;
use Proc::ProcessTable;

use POE;
use POE::Wheel::Run;
use POE::Filter::Reference;
use Carp qw(carp croak);
use Data::Dumper;

my $debug = $SNAG::flags{debug};

my $rrd_del = ':';

#################################
sub new
#################################
{
  my $package = shift;
  $package->SUPER::new(@_);

  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        $kernel->sig( CHLD => 'catch_sigchld' );

        $kernel->yield('sync_monitor_defs');
        $kernel->delay('run_monitor' => 5);
      },

      sync_monitor_defs => sub
      {
        my ($kernel, $heap, $session) = @_[ KERNEL, HEAP, SESSION ];
        $kernel->delay($_[STATE] => 600);

        $kernel->post('client' => 'sysinfo' => 'sync_monitor_defs' => { function => 'sync_monitor_defs', host => HOST_NAME, postback => $session->postback('add_monitor_defs') } );
      },

      add_monitor_defs => sub
      {
        my ($kernel, $heap, $ref) = @_[ KERNEL, HEAP, ARG1 ];

        if($ref->[0])
        {
          $SNAG::Dispatch::shared_data->{monitor_defs} = $ref->[0];

          if($debug)
          {
            print "GOT NEW MONITOR DEFINITIONS!\n";
            print Dumper $SNAG::Dispatch::shared_data->{monitor_defs};
          }
        }
      },

      run_monitor => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->delay($_[STATE] => 60);

        my $monitor_defs = $SNAG::Dispatch::shared_data->{monitor_defs};

        return unless $monitor_defs;

        if($heap->{run_monitor_wheel})
        {
          $kernel->post("logger" => "log" =>  "SNAG::Source::monitor: run_monitor_wheel is still running, skipping");
        }
        else
        {
          $heap->{run_monitor_wheel} = POE::Wheel::Run->new
          (
            Program => \&run_monitor,
            ProgramArgs  => [ $monitor_defs ],
            StdioFilter  => POE::Filter::Reference->new(),
            StderrFilter => POE::Filter::Line->new(),
            Conduit      => 'pipe',
            StdoutEvent  => 'wheel_stdio',
            StderrEvent  => 'wheel_stderr',
            CloseEvent   => 'wheel_close',
          );
        }
      },

      wheel_stdio => sub
      {
        my ($kernel, $heap, $input) = @_[KERNEL, HEAP, ARG0];

        if(%$input)
        {
          my $now = time;
          my $seen = time2str("%Y-%m-%d %T", $now);

          if(my $port_status = $input->{ports}) 
          {
            foreach my $ref (@$port_status)
            {
              if($ref->{status} eq 'success')
              {
                $kernel->post('client' => 'sysrrd' => 'load' => join ':', (HOST_NAME, 'monport_' . $ref->{port}, '1g', $now, '1'));
              }
              else
              {
                $kernel->post('client' => 'sysrrd' => 'load' => join ':', (HOST_NAME, 'monport_' . $ref->{port}, '1g', $now, '0'));
  
                $ref->{error} =~ s/ at .+ line \d+\.$//;
                $ref->{error} =~ s/IO::Socket::INET: connect: //;
  
                my $alert = "Could not connect to monitored port on localhost";
                my $event = "TCP port $ref->{port}: $ref->{error}";
                
                $kernel->post('client' => 'dashboard' => 'load' => join REC_SEP, ('events', HOST_NAME, 'snag', 'monitor_port', $alert, $event, '', $seen) );
              }
            }
          }

          if(my $proc_status = $input->{procs}) 
          {
            foreach my $ref (@$proc_status)
            {
              if($ref->{count} < 1)
              {
                my $alert = $ref->{alert} || "Monitored process not running on localhost";
                my $event = "Field: $ref->{field}, Match: $ref->{arg}, IDX: $ref->{idx}";

                $kernel->post('client' => 'dashboard' => 'load' => join REC_SEP, ('events', HOST_NAME, 'snag', 'monitor_proc', $alert, $event, '', $seen) );
              }

              $kernel->post('client' => 'sysrrd' => 'load' => join ':', (HOST_NAME, 'monproc_' . $ref->{idx}, '1g', $now, $ref->{count}) );
            }
          }
          
        }
      },

      wheel_stderr => sub
      {
        my ($kernel, $heap, $input) = @_[KERNEL, HEAP, ARG0];

        $kernel->post("logger" => "log" =>  "SNAG::Source::monitor: $input");
      },

      wheel_close => sub
      {
       #### this needs to be addressed
        my ($kernel, $heap, $wheel_id) = @_[KERNEL, HEAP, ARG0];

        delete $heap->{run_monitor_wheel};
      },

      catch_sigchld => sub
      {
      },

    }
  );
}

#          'ports' => {
#                       '3306' => '1',
#                       '188' => '1'
#                     },

sub run_monitor
{
  my $monitor_defs = shift;

  my $status = {};

  if(my $ports = $monitor_defs->{ports})
  {
    foreach my $port (keys %$ports)
    {  
      my $ref = { port => $port };

      eval
      {
        my $sock = IO::Socket::INET->new(
                                          PeerPort  => $port,
                                          PeerAddr  => 'localhost',
                                          Proto     => 'tcp',
                                          Timeout   => 2,
                                        ) or die $@;
        $sock->close;
      };
      if($@)
      {  
        $ref->{error} = $@;
        $ref->{status} = 'failure';
      }
      else
      {
        $ref->{status} = 'success';
      }

      push @{$status->{ports}}, $ref;
    }
  }


#          'procs' => {
#                       'fname:masond' => {
#                                           'arg' => 'masond',
#                                           'field' => 'fname'
#                                         },
#                       'cmndline:qr/adfadsfds/' => {
#                                                     'arg' => 'qr/adfadsfds/',
#                                                     'field' => 'cmndline'
#                                                   }
#                     }
#        };
#


  if(my $procs = $monitor_defs->{procs})
  {
    my $get_procs = new Proc::ProcessTable;

    while(my ($proc_key, $ref) = each %$procs)
    {
      $ref->{count} = 0;

      eval
      {
        foreach my $proc ( @{$get_procs->table} )
        {
          if(ref $ref->{arg} eq 'Regexp')
          {
            if($proc->{ $ref->{field} } =~ /$ref->{arg}/)
            {
              $ref->{count}++;
            }
          }
          else
          {
            if($proc->{ $ref->{field} } eq $ref->{arg})
            {
              $ref->{count}++;
            }
          }
        }   

      };
      if($@)
      {
        print STDERR "$@\n";
        $ref->{error} = $@;
      }

      push @{$status->{procs}}, $ref;
    }
  }

  my $filter = POE::Filter::Reference->new('Storable');
  my $return = $filter->put( [ $status ] );
  print @$return;
}

1;
