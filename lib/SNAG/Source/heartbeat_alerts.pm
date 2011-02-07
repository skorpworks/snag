package SNAG::Source::heartbeat_alerts;
use base qw/SNAG::Source/;

use strict;
use SNAG;
use POE;
use POE::Session;
use Carp qw(carp croak);
use Date::Format;
use Date::Parse;
use Date::Manip;
use Data::Dumper;
use Proc::ProcessTable;

use DBI;

my $debug = $SNAG::flags{debug};
my $verbose = $SNAG::flags{verbose};

#################################
sub new
#################################
{
  my $package = shift;
  $package->SUPER::new(@_);

  my $mi = $package . '->new()';

  croak "$mi requires an even number of parameters" if (@_ & 1);
  my %params = @_;

  foreach my $key (keys %params)
  {
    warn "Unknown parameter $key";
  }

  my $args = $params{Source};

  POE::Session->create
  (
    inline_states=>
    {
      _start => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->yield('send_alerts');
      },
     
      send_alerts => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->delay($_[STATE] => 60);

        print "START send_alerts:\n" if $debug;

        my $now = time;
        my $seen = time2str("%Y-%m-%d %T", $now);

        eval
        {
          my $dbh = DBI->connect($args->{dsn}, $args->{user}, $args->{pw}, {PrintError => 1});

          my ($locked, $connected);

          my $check_connections = $dbh->selectall_arrayref("select * from activity() where usename like 'sysinfo_asls_%' and datname = 'sysinfo' and backend_start < ( now() - interval '10 minutes' ) and query_start > ( now() - interval '5 minutes')", { Slice => {} });
        
          if($check_connections && @$check_connections)
          {
            my $check_locks = $dbh->selectall_arrayref("SELECT locktype, relation::regclass, mode, granted FROM pg_locks JOIN pg_database ON (oid = database) WHERE datname = (SELECT current_database()) AND datname = 'sysinfo' ORDER BY datname, relation, mode", { Slice => {} });

            foreach my $ref (@$check_locks)
            {
              ### We'll use RowShareLock to indicate that the server needs more time to allow clients to reconnect
              if(
                  $ref->{relation} =~ /^(server_heartbeats|description|asl)$/
                  && $ref->{mode} =~ /^(ExclusiveLock|AccessExclusiveLock|ShareUpdateExclusiveLock|ShareLock|RowShareLock)$/
                )
              {
                $kernel->post('logger' => 'log' =>  "Relation $ref->{relation} has a $ref->{mode} lock, skipping heartbeat alerts this round");
                $locked = 1;
              }
            }
  
            unless($locked)
            {
              my $heartbeats = $dbh->selectall_arrayref("select heartbeat.*, description.status from heartbeat left join description on heartbeat.host = description.host where heartbeat.server_seen < (now() - interval '180 seconds') and activity='active'", { Slice => {} });
  
              if($heartbeats)
              {
                foreach my $ref (@$heartbeats)
                {  
                  next unless $ref->{host};
      
                  if($ref->{server_seen} && (!$ref->{status} || $ref->{status} eq 'active'))
                  {
                    my $last_seen = $ref->{server_seen};
          
                    my $epoch = UnixDate($last_seen, '%s');
                    my $seconds_old = $now - $epoch;
          
                    my ($critical_thresh, $warning_thresh);

                    $critical_thresh = 600;
                    $warning_thresh = 180;
          
                    my ($alert, $event);
          
                    if($seconds_old > $critical_thresh)
                    {
                      $alert = "Last heartbeat exceeds critical threshhold";
                      $event = "Last heartbeat was at $last_seen (seconds old $seconds_old, critical threshhold $critical_thresh)";
                    }
                    elsif($seconds_old > $warning_thresh)
                    {
                      $alert = "Last heartbeat exceeds warning threshhold";
                      $event = "Last heartbeat was at $last_seen (seconds old $seconds_old, warning threshhold $warning_thresh)";
                    }
                    else
                    {
                      next;
                    }
          
                    $kernel->post('client' => 'dashboard' => 'load' => join REC_SEP, ('events', $ref->{host}, 'sysinfo', 'heartbeat_thresh', $alert, $event, '', $seen) );
                  }
                }
              }
            }
          }
          else
          {
            $kernel->post('logger' => 'log' =>  'No server connections to sysinfo, or connecting timing has not yet reached threshhold');
          }
        };
        if($@)
        {
          $kernel->post("logger" => "log" =>  "Error: $@");
        }
  
        print "DONE send_alerts:\n" if $debug;
      }
    }
  );
}

1;

__END__
SELECT locktype, datname, relation::regclass, mode, granted
FROM pg_locks
JOIN pg_database ON (oid = database)
WHERE datname = (SELECT current_database())
ORDER BY datname, relation, mode;

