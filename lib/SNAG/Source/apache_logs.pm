package SNAG::Source::apache_logs;
use base qw/SNAG::Source/;

use strict;

use SNAG;
use SNAG::Source::File::web_error_log;
use SNAG::Source::DailyFile::web_error_log;
use SNAG::Source::File::web_access_log;
use SNAG::Source::DailyFile::web_access_log;

use LWP::UserAgent;
use File::Basename;
use URI::Escape;

use POE;
use Carp qw(carp croak);
use Data::Dumper;

my $period = 60;
my $wait_thresh = 120; ### Number of seconds to wait after a minute is over before sending the accumulated stats

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

  my $debug = $SNAG::flags{debug};

  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        $kernel->alias_set('apache_logs');

        $kernel->sig( CHLD => 'catch_sigchld' );

        $kernel->yield('log_search');
        $kernel->yield('send');
      },

      log_search => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->delay($_[STATE] => 43200);

        open my $logs, "/usr/sbin/lsof -nP | /bin/egrep 'access_log|error_log' | /bin/awk '{print \$9}' | /bin/sort -u |";

	      while(<$logs>)
	      {
	        chomp;
	        my $log = $_;

          next if $log =~ m#^/var/rrd/#;

	        (my $type) = ($log =~ /(access_log|error_log)/);
	        die "This should never happen" unless $type;
      
	        if($log =~ s/\.[\d\-\_\:\.]+$//)
	        {
	          ### Daily
	          my $alias = $log . '.num';
	          my $match = $log . '.' . '[\d\-\_\:\.]+$';
            my $log_dir = dirname($log);

	          unless($heap->{already_open}->{$alias})
	          {
	            if($type eq 'access_log')
	            {
		            print "Opening $alias with SNAG::Source::DailyFile::web_access_log\n" if $debug;
      
                SNAG::Source::DailyFile::web_access_log->new
                (
                  Alias   => uri_escape($alias),
                  Source  => { file_match => $match, dir => $log_dir },
                  Options => { startatendifnew => 1 },
                );
	            }
	            else
	            {
		            print "Opening $alias with SNAG::Source::DailyFile::web_error_log\n" if $debug;

                SNAG::Source::DailyFile::web_error_log->new
                (
                  Alias   => uri_escape($alias),
                  Source  => { file_match => $match, dir => $log_dir },
                  Options => { startatendifnew => 1 },
                );
	            }

	            $heap->{already_open}->{$alias} = 1;
	          }
	        }
	        elsif(/$type$/)
	        {
	          ### Not Daily, must end with $type (access_log, error_log) or we don't trust it
	          unless($heap->{already_open}->{$log})
	          {
	            if($type eq 'access_log')
	            {
		            print "Opening $log with SNAG::Source::File::web_access_log\n" if $debug;

	              SNAG::Source::File::web_access_log->new
	              (
	 	              Alias   => uri_escape($log),
		              Source  => $log,
                  Options => { startatendifnew => 1 },
	              );
	            }
	            else
	            {
		            print "Opening $log with SNAG::Source::File::web_error_log\n" if $debug;

	              SNAG::Source::File::web_error_log->new
	              (
	  	            Alias   => uri_escape($log),
		              Source  => $log,
                  Options => { startatendifnew => 1 },
	              );
	            }

	            $heap->{already_open}->{$log} = 1;
	          }
	        }
	      }
          close $logs;
      },

      add_msg => sub
      {
        my ($kernel, $heap, $sender, $ref) = @_[KERNEL, HEAP, SENDER, ARG0];

        my $alias = $heap->{get_alias}->{ $sender->ID } ||= ($kernel->alias_list( $sender->ID ))[0];

        $heap->{data}->{ $alias }->{ $ref->{type} }->{ $ref->{minute} }++;
      },

      send => sub
      {
        no strict;

        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->delay($_[STATE] => $period);

        my $time = time;

        ### Send log stats
	      foreach my $alias (keys %{$heap->{data}})
	      {
          foreach my $type (keys %{$heap->{data}->{$alias}})
	        {
            foreach my $minute (sort keys %{$heap->{data}->{$alias}->{$type}})
            {
              next if $minute >= ($time - $wait_thresh);

              ### Send a zero for the last period on inactive logs so that this point won't be lost
              my $last_period = $minute - $period;
              if($heap->{last_minute}->{$alias}->{$type} < $last_period)
              {
	              $kernel->post('client' => 'sysrrd' => 'load' => join ':', (HOST_NAME . "[$alias]", $type, '1g', $last_period, '0'));
              }

	            my $count = delete $heap->{data}->{$alias}->{$type}->{$minute};
                     
	            $kernel->post('client' => 'sysrrd' => 'load' => join ':', (HOST_NAME . "[$alias]", $type, '1g', $minute, $count));

              $heap->{last_minute}->{$alias}->{$type} = $minute;
	          }
	        }
        }
      },

      catch_sigchld => sub
      {
      },

    }
  );
}


1;
