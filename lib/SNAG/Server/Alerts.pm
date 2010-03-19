package SNAG::Server::Alerts; 
use base qw(SNAG::Server);

use strict;
use SNAG;
use POE;
use Carp qw(carp croak);
use Date::Format;
use Date::Parse;

use MIME::QuotedPrint;
use HTML::Entities;
use Mail::Sendmail;

use POE::Component::EasyDBI;
use POE::Wheel::Run;

use Apache::DBI::Cache;
use DBI;
use FileHandle;
use DBM::Deep;

my $rec_sep = REC_SEP;
my $debug = $SNAG::flags{debug};

my $state;

my $monitored_procs =
{
  names =>
  {
    'mysqld' => 1,
    'oracle' => 1,
    'postmaster' => 1,
    'masond' => 1,
    'dataserver' => 1,
    'db2sync' => 1,
    'slapd' => 1,
    'dhcpd' => 1,
    'syslog_ng' => 1,
    'httpd' => 1,
    'apache' => 1,
    'apache2' => 1,
    'masond' => 1,
    'libhttpd.ep' => 1,
    'httpd.worker' => 1,
    'tac_plus' => 1,
    'radius' => 1,
    'niddnsd' => 1,
    'niddhcpd' => 1,
    'syslog-ng' => 1,
    'snmptrad' => 1,
    'rsyslog' => 1,
    'fileserver' => 1,
    'bosserver' => 1,
    'ptsserver' => 1,
    'buserver' => 1,
    'volserver' => 1,
    'iscsid' => 1,
    'dmserv' => 1,
    'authd' => 1,
    'verifyd' => 1,
    'MSSQLSERVER' => 1,
    'IIS Admin Service' => 1,
    'Microsoft Exchange Management' => 1,
    'Citrix' => 1,
    'OpenAFS Client Service' => 1,
    'NetApp' => 1,
  },
  regexps =>
  [
    qr/_SNAGs.pl$/,
    qr/_SNAGp.pl$/,
  ]
};

################################
sub new
################################
{
  my $type = shift;
  $type->SUPER::new(@_);

  my %params = @_;
  my $args = delete $params{Args};

  croak "Args must be a hashref" if $args and ref $args ne 'HASH';
  croak "Args must contain values for 'dsn', 'user', and 'pw'" unless ($args->{dsn} && $args->{user} && $args->{pw});

  $args->{dsn} =~ /^DBI:(\w+):/i;
  my $driver = lc $1;
  croak "Unsupported DB driver ($driver)" unless $driver =~ /^(pg|mysql)$/;

  my $package = $type;
  $package =~ s/\:\:/\./g;

  # Tie State to dbm::deep hash
 # $state = DBM::Deep->new("/var/tmp/ram/alerts.state");

  POE::Component::EasyDBI->spawn(
    alias           => 'sysinfodbi',
    dsn             => $args->{dsn},
    username        => $args->{user},
    password        => $args->{pw},
    options         => { RaiseError => 1 },
    max_retries => -1,
  );

  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->alias_set('object');

        my $loadsub = 'load_' . $driver;
        no strict 'refs';
        $kernel->state('load' => \&{$loadsub});
        print "Using load method '$loadsub'\n" if $debug;

        $kernel->yield('query_alert_state');
        $kernel->yield('status_timer');
        $kernel->delay('alert_expire' => 900);
        $kernel->yield('connect');
      },

      connect => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        delete $heap->{dbh};

        eval
        {
          $heap->{dbh} = DBI->connect($args->{dsn}, $args->{user}, $args->{pw}, { RaiseError => 1, AutoCommit => 1 }) or die $!;
        };
        if($@)
        {
          $kernel->post('logger' => 'log' => "$type: failed to connect to $args->{dsn}: $@");
          $kernel->delay($_[STATE] => 10 );
        }
        else
        {
          $kernel->post('logger' => 'log' => "$type: connected to $args->{dsn}");
          $heap->{connected} = 1;
        }
      },

      status_timer => sub
      {
        my ($heap, $kernel) = @_[ HEAP, KERNEL ];
        $heap->{time} = time();
        $kernel->delay($_[STATE] => 5);
      },

      query_alert_state => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        my $seen = time2str("%Y-%m-%d %T\n", time() - 3600 * 2);

        $kernel->post('logger' => 'log' => "DEBUG: Alerts: query_alert_state: Query State") if $debug;

        my $sql = "SELECT aid, host, source, category, alert, count, first_seen, last_seen from alerts where last_seen > (SELECT first_seen from alerts where first_seen IS NOT NULL order by last_seen desc limit 1)  - interval '2 hour' order by last_seen desc";
        print "Executing: $sql\n" if $debug;

        $kernel->post('sysinfodbi',
                       arrayhash => {
                                      sql => $sql,
                                      event => 'alerts_state',
                                    }
                     );
        $kernel->delay($_[STATE] => 3600);
      },

      alerts_state => sub
      {
        my ($kernel, $heap, $dbires) = @_[KERNEL, HEAP, ARG0];

        if($dbires->{error})
        {
          die "sysinfodbi error: $dbires->{error}\n";
        }
        else
        {
          my ($row, $alert_string, $fs, $ls);
          foreach $row (@{$dbires->{result}})
          {
            $alert_string = "$row->{host}.$row->{source}.$row->{category}.$row->{alert}";
            $alert_string =~ s/\s+//g;
            $alert_string =~ s/\s+//g;

            #possible that a host/alert may exist twice in the result set
            #we want the most recent one only
            next if defined $state->{alerts}->{"$alert_string"}->{aid};
            #relies on the query in query_alerts_state to order by last_seen desc

            eval
            {
              $fs = str2time($row->{first_seen});
              $ls = str2time($row->{last_seen});
              $state->{alerts}->{"$alert_string"}->{count} = $row->{count};
              $state->{alerts}->{"$alert_string"}->{first_seen} = $fs;
              $state->{alerts}->{"$alert_string"}->{last_seen}  = $ls;
              $state->{alerts}->{"$alert_string"}->{aid} = $row->{aid};
              $kernel->post('logger' => 'log' => "DEBUG: Alerts: alert_state: setting state for aid $row->{aid} to fs:$fs ls:$ls c:$row->{count}") if $debug;
            };
            if ($@)
            {
              die "Error update state->{'alert_state'}: $@\n";
            }
          }
        }
      },

      alert_expire => sub
      {
        my ($heap, $kernel) = @_[ HEAP, KERNEL ];

        my ($a_ids, $key, $value, $alert);

        $a_ids = $heap->{a_ids}->{seen};

        while (($key, $value) = each %$a_ids)
        {
          #$heap->{a_ids}->{seen}->{$state->{alerts}->{$alert_string}->{aid}} = 0;
          #$heap->{a_ids}->{alert}->{$state->{alerts}->{$alert_string}->{aid}} = $alert_string;
          #$state->{alerts}->{$alert_string}->{count} = 1;
          #$state->{alerts}->{$alert_string}->{first_seen} = $curr_seen;
          #$state->{alerts}->{$alert_string}->{last_seen}  = $curr_seen;

          $heap->{a_ids}->{seen}->{$key} += 60;

          if ($value >= (60 * 60))
          {
            $alert = $heap->{a_ids}->{alert}->{$key};
            $kernel->post('logger' => 'log' => "DEBUGGING: aid: $key  hseen: $heap->{a_ids}->{seen}->{$key}  fseen: $state->{alerts}->{$alert}->{first_seen}  lseen: $state->{alerts}->{$alert}->{last_seen} alert: $alert\n") if $debug;
            delete $heap->{a_ids}->{seen}->{$key};
            delete $heap->{a_ids}->{alert}->{$key};
            if ($state->{alerts}->{"$alert"}->{aid} == $key)
            {
              $kernel->post('logger' => 'log' => "DEBUGGING: deleting state for $key : $alert\n") if  $debug;
              delete $state->{alerts}->{"$alert"}->{count};
              delete $state->{alerts}->{"$alert"}->{first_seen};
              delete $state->{alerts}->{"$alert"}->{last_seen};
              delete $state->{alerts}->{"$alert"}->{aid};
              delete $state->{alerts}->{"$alert"};
            }
          }
        }

        $kernel->delay($_[STATE] => 120);
      },

    }
  );

  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        $kernel->alias_set('notifier');
        $kernel->yield('query_alert_settings');
      },

      query_alert_settings => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        my $sql = "SELECT source, category, alert, severity, email from alert_settings";
        print "Executing: $sql\n" if $debug;

        $kernel->post('sysinfodbi',
                       arrayhash => {
                                      sql => $sql,
                                      event => 'alerts_settings',
                                    }
                     );
        $kernel->delay($_[STATE] => 3600);
      },


      alerts_settings => sub
      {
        my ($kernel, $heap, $dbires) = @_[KERNEL, HEAP, ARG0];

        if($dbires->{error})
        {
          die "sysinfodbi error: $dbires->{error}\n";
        }
        else
        {
          my ($row, $alert_string);
          foreach $row (@{$dbires->{result}})
          {
            $alert_string = "$row->{source}.$row->{category}.$row->{alert}";
            $kernel->post('logger' => 'log' => "NOTIFY: alert_settings ($alert_string) with sev:$row->{'severity'} and email: $row->{'email'}\n") if $debug;
            eval
            {
              $state->{'alert_settings'}->{'sev'}->{"$alert_string"} = $row->{'severity'};
              $state->{'alert_settings'}->{'email'}->{"$alert_string"} = $row->{'email'};
            };
            if ($@)
            {
              die "Error update state->{'alert_settings'}: $@\n";
            }
          }
        }
      },

      notify => sub
      { 
        my ($kernel, $heap, $msg) = @_[ KERNEL, HEAP, ARG0 ];

        my $alert_string = "$msg->{source}.$msg->{category}.$msg->{alert}";

        return unless (defined $state->{'alert_settings'}->{'email'}->{"$alert_string"} && $state->{'alert_settings'}->{'email'}->{"$alert_string"} ne '');

        my $host_name = $msg->{host} || HOST_NAME;

                         #To      => $state->{'alert_settings'}->{'email'}->{$alert_string},
        my $boundary = "====" . time() . "====";
        my %mail = (
                         smtp    => 'smtp.asu.edu',
                         To      => $state->{'alert_settings'}->{'email'}->{"$alert_string"},
                         From    => 'foo@example.com',
                         Subject => "SNAG " . $state->{'alert_settings'}->{'sev'}->{"$alert_string"} . " alert from " . $host_name . "!",
                         'content-type' => "multipart/alternative; boundary=\"$boundary\"",
                       );

        my $text  = "Alert     : $msg->{alert}\n";
        $text    .= "Event     : $msg->{event}\n\n";
        $text    .= "Occured   : $msg->{timestamp}\n";   
        $text    .= "Processed : " . time2str("%Y-%m-%d %X", time()) . "\n";     
                                                                                                                                                                                                                
        my $plain = encode_qp ($text);                                                                                                                                                                          
                                                                                                                                                                                                                
        $msg->{alert} = encode_entities($msg->{alert});  
        $msg->{event} = encode_entities($msg->{event});
        $msg->{timestamp} = encode_entities($msg->{timestamp});

        my $html = "<table>\n";
        $html   .= "<tr><td colspan=2>&nbsp;</td></tr>\n";
        $html   .= "<tr><td>Alert &nbsp;&nbsp;</td><td>: <strong>$msg->{alert}</strong></td></tr>\n";
        $html   .= "<tr><td>Event &nbsp;&nbsp;</td><td>: <strong>$msg->{event}</strong></td></tr>\n";
        $html   .= "<tr><td colspan=2>&nbsp;</td></tr>\n";
        $html   .= "<tr><td>Occured &nbsp;&nbsp;</td><td>: $msg->{timestamp}</td></tr>\n";   
        $html   .= "<tr><td>Processed &nbsp;&nbsp;</td><td>: " . encode_entities(time2str("%Y-%m-%d %X", time())) . "</td></tr>\n"; 
        $html   .= "</table>\n";

        $boundary = '--'. $boundary;

$mail{body} = <<END_OF_BODY;
$boundary
Content-Type: text/plain; charset="iso-8859-1"
Content-Transfer-Encoding: quoted-printable

$plain

$boundary
Content-Type: text/html; charset="iso-8859-1"
Content-Transfer-Encoding: quoted-printable

<html>$html</html>
$boundary--
END_OF_BODY

        unless($heap->{notify_wheel})
        {
          $heap->{mail_args} = \%mail;

          $heap->{notify_wheel} = POE::Wheel::Run->new
          (
            Program => sub
                       {
                         sendmail(%mail) or die $Mail::Sendmail::error;
                       },
            StdioFilter  => POE::Filter::Line->new(),
            StderrFilter => POE::Filter::Line->new(),
            Conduit      => 'pipe',
            StdoutEvent  => 'notify_stdio',
            StderrEvent  => 'notify_stderr',
            CloseEvent   => "notify_close",
          );
        }
        else
        {
          $kernel->yield('log' => "Could not send alert because an alert wheel is already running.  Subject: $mail{Subject}, Message: $mail{Message}");
        }
      },

      notify_stdio => sub
      {
        my ($kernel, $heap, $error) = @_[ KERNEL, HEAP, ARG0 ];
        $kernel->post('logger' => 'log' => "DEBUG: Notfiy: $error");
      },

      notify_stderr => sub
      {
        my ($kernel, $heap, $error) = @_[ KERNEL, HEAP, ARG0 ];
        $kernel->post('logger' => 'log' => "Could not send alert because of an error.  Error: $error, Subject: $heap->{mail_args}->{Subject}, Message: $heap->{mail_args}->{Message}");
      },

      notify_close => sub
      {
        my ($kernel, $heap) = @_[ KERNEL, HEAP ];
        delete $heap->{notify_wheel};
      },

    }
  );

}

sub load_mysql
{
  die 'Tried to load mysql';
}

sub load_pg
{
  my ($heap, $kernel, $parcel, $commit_after_insert) = @_[HEAP, KERNEL, ARG0, ARG1];

  return -1 unless $heap->{connected};


  #CREATE TABLE events ( 
      #event text,
      #params text,
      #seen timestamp without time zone DEFAULT now(),
      #aid bigint NOT NULL,
      #eid bigint NOT NULL
  #);  

  #CREATE TABLE alerts (
      #aid bigint NOT NULL,
      #host character varying(256),
      #source text,
      #category text,
      #alert text,
      #first_seen timestamp without time zone,
      #last_seen timestamp without time zone
  #);

  # OLD
  #CREATE TABLE events (
      #host character varying(256),		0
      #source text,				1
      #event_type text,				2
      #event_desc text,				3
      #event_full text,				4
      #event_param text,			5
      #seen timestamp without time zone,	6
      #eid integer NOT NULL			7
  #);

  my $row;
  eval
  {
    local $SIG{__WARN__} = sub
    {
      die @_;
    };

    die "DBI->ping failed: no connection to the server" unless $heap->{dbh}->ping();

    foreach $row (@$parcel)
    {
      unless($row)
      {
        print "Empty Row\n" if $debug;
        next;
      }

      $kernel->post('logger' => 'log' => "DEBUG: Alerts: received row: $row") if $debug;

      if ($row =~ m/^heartbeat_syslog/)
      {
        my ($p_table, $p_host, $p_fqdn, $p_loghost, $p_seen) = split /$rec_sep/, $row, -1;
        unless (defined $heap->{hbs_s_sth})
        {
          $heap->{hbs_s_sth} = $heap->{dbh}->prepare('SELECT count(*) from heartbeat_syslog where host= ? and fqdn = ? and loghost= ?');
          $heap->{hbs_i_sth} = $heap->{dbh}->prepare('INSERT INTO heartbeat_syslog values (?, ?, ?, ?)');
          $heap->{hbs_u_sth} = $heap->{dbh}->prepare('UPDATE heartbeat_syslog set seen = ? where host= ? and fqdn = ? and loghost= ?');
          $kernel->post('logger' => 'log' => "DEBUG: Alerts: preparing hbs_*_sth") if $debug;
        }
        unless (defined $heap->{hbs_ids}->{"$p_host.$p_fqdn.$p_loghost"})
        {
          $kernel->post('logger' => 'log' => "DEBUG: Alerts: inserting to hbs_i_sth: $p_host.$p_fqdn.$p_loghost") if $debug;
          $heap->{hbs_s_sth}->execute($p_host, $p_fqdn, $p_loghost) or die "hbs_s_sth failed: " . $heap->{dbh}->errstr;
          my $ary_ref = $heap->{hbs_s_sth}->fetchall_arrayref() or die "hbs_s_sth failed: ";
          if (defined $ary_ref && ${$ary_ref}[0][0] > 0)
          {
            $kernel->post('logger' => 'log' => "DEBUG: Alerts: updating to hbs_u_sth: $p_host.$p_fqdn.$p_loghost") if $debug;
            $heap->{hbs_u_sth}->execute($p_seen, $p_host, $p_fqdn, $p_loghost) or die "hbs_u_sth 1 failed: " . $heap->{dbh}->errstr;
          }
          else
          {
            $kernel->post('logger' => 'log' => "DEBUG: Alerts: inserting to hbs_i_sth: $p_host.$p_fqdn.$p_loghost") if $debug;
            $heap->{hbs_i_sth}->execute($p_host, $p_fqdn, $p_loghost, $p_seen) or die "hbs_i_sth failed: " . $heap->{dbh}->errstr;
          }
          $heap->{hbs_ids}->{"$p_host.$p_fqdn.$p_loghost"} = "${$ary_ref}[0][0]";
        }
        else
        {
          $kernel->post('logger' => 'log' => "DEBUG: Alerts: updating to hbs_u_sth: $p_host.$p_fqdn.$p_loghost") if $debug;
          $heap->{hbs_u_sth}->execute($p_seen, $p_host, $p_fqdn, $p_loghost) or die "hbs_u_sth 2 failed: " . $heap->{dbh}->errstr;
        }
      }
      elsif ($row =~ m/^heartbeat_SNAG/)
      {
      }
      else
      {
        unless (defined $heap->{evt_sth})
        {
          $heap->{evt_sth} = $heap->{dbh}->prepare('INSERT INTO events values (?, ?, ?, ?)');
          $kernel->post('logger' => 'log' => "DEBUG: Alerts: preparing evt_sth") if $debug;
        }
        unless (defined $heap->{create_alrt_sth})
        {
          $heap->{create_alrt_sth} = $heap->{dbh}->prepare("INSERT INTO alerts (host, source, category, alert, count, first_seen, last_seen) values (?, ?, ?, ?, '1', ?, ?)");
          $kernel->post('logger' => 'log' => "DEBUG: Alerts: preparing create_alrt_sth") if $debug;
        }
        unless (defined $heap->{update_alrt_sth})
        {
          $heap->{update_alrt_sth} = $heap->{dbh}->prepare('UPDATE alerts set count = ?, last_seen = ? where aid = ?');
          $kernel->post('logger' => 'log' => "DEBUG: Alerts: preparing update_alrt_sth") if $debug;
        }

        my ($p_table, $p_host, $p_source, $p_category, $p_alert, $p_full, $p_param, $p_seen) = split /$rec_sep/, $row, -1;
        my ($alert_string, $curr_seen);

        if($p_alert eq 'service state change')
        {
          if($p_full =~ /^(service|proc) (.+?) is not running.\s+usual run rate is \d+\%$/)
          {
            my $proc = $2;
 
            if($monitored_procs->{names}->{$proc})
            {
              $p_category = 'monitored_service_state';
              $p_alert = "Monitored process ($proc) no longer running";
            }
            else
            {
              foreach my $regexp (@{$monitored_procs->{regexp}})
              {
                if($proc =~ /$regexp/)
                {
                  $p_category = 'monitored_service_state';
                  $p_alert = "Monitored process ($proc) no longer running";

                  last;
                }
              }
            }
          }
        }

        #$alert_string = "$row->{host}.$row->{source}.$row->{category}.$row->{alert}";
        #  $state->{alerts}->{"$alert_string"}->{count} = $row->{count};
        #  $state->{alerts}->{"$alert_string"}->{first_seen} = $row->{first_seen};
        #  $state->{alerts}->{"$alert_string"}->{last_seen}  = $row->{last_seen};
        #  $state->{alerts}->{"$alert_string"}->{aid} = $row->{aid};

        $alert_string = "$p_host.$p_source.$p_category.$p_alert";
        $alert_string =~ s/\s+//g;
        $alert_string =~ s/\s+//g;
  
        $curr_seen = str2time($p_seen);
  
        $heap->{dbh}->begin_work() or die "begin_work failed: " . $heap->{dbh}->errstr;
        unless (defined $state->{alerts}->{"$alert_string"}->{first_seen} && ($curr_seen - $state->{alerts}->{"$alert_string"}->{last_seen} < 660))
        {
          #$kernel->post('notifier' => 'notify' => { 'host' => $p_host, 'source' => $p_source, 'category' => $p_category, 'alert' => $p_alert, 'timestamp' => $curr_seen } );
          $kernel->post('notifier' => 'notify' => { 
                                                    'host'      => $p_host, 
                                                    'source'    => $p_source, 
                                                    'category'  => $p_category, 
                                                    'alert'     => $p_alert, 
                                                    'event'     => $p_full, 
                                                    'timestamp' => $p_seen 
                                                  } 
                       );
          $heap->{create_alrt_sth}->execute($p_host, $p_source, $p_category, $p_alert, $p_seen, $p_seen) or die "create_alrt_sth failed: " . $heap->{dbh}->errstr;
          my $aid = $heap->{dbh}->last_insert_id(undef,undef,'alerts',undef);

          $kernel->post('logger' => 'log' => "DEBUG: Alerts: creating new alert $aid for #$alert_string# #cs:$curr_seen# #fs:$state->{alerts}->{$alert_string}->{first_seen}# #ls:$state->{alerts}->{$alert_string}->{last_seen}# #aid:$heap->{a_ids}->{seen}->{$state->{alerts}->{$alert_string}->{aid}}#");
          $state->{alerts}->{"$alert_string"}->{count} = 1;
          $state->{alerts}->{"$alert_string"}->{first_seen} = $curr_seen;
          $state->{alerts}->{"$alert_string"}->{last_seen}  = $curr_seen;
          $state->{alerts}->{"$alert_string"}->{aid} = $aid;
          $heap->{a_ids}->{seen}->{$state->{alerts}->{"$alert_string"}->{aid}} = 0;
          $heap->{a_ids}->{alert}->{$state->{alerts}->{"$alert_string"}->{aid}} = $alert_string;
        }
        else
        {
          $kernel->post('logger' => 'log' => "DEBUG: Alerts: reusing alert $state->{alerts}->{$alert_string}->{aid} for #$alert_string#  #$state->{alerts}->{$alert_string}->{first_seen}# $state->{alerts}->{$alert_string}->{last_seen}# #$heap->{a_ids}->{seen}->{$state->{alerts}->{$alert_string}->{aid}}#: $p_seen");
          $state->{alerts}->{"$alert_string"}->{count}++;
          $state->{alerts}->{"$alert_string"}->{last_seen}  = $curr_seen;
          $heap->{a_ids}->{seen}->{$state->{alerts}->{"$alert_string"}->{aid}} = 0;
          $heap->{a_ids}->{alert}->{$state->{alerts}->{"$alert_string"}->{aid}} = $alert_string unless defined $heap->{a_ids}->{alert}->{$state->{alerts}->{"$alert_string"}->{aid}};
          $heap->{update_alrt_sth}->execute($state->{alerts}->{"$alert_string"}->{count}, $p_seen, $state->{alerts}->{"$alert_string"}->{aid}) or die "update_alrt_sth failed: " . $heap->{dbh}->errstr;
        } 
        #$heap->{dbh}->commit();
        #$heap->{dbh}->begin_work();
        $heap->{evt_sth}->execute($p_full, $p_param, $p_seen, $state->{alerts}->{"$alert_string"}->{aid}) or die "Failed loading: event: \'$row\' :" . $heap->{dbh}->errstr;
        $heap->{dbh}->commit();
      } ## assumed events table
    } #
  };
  ## What other 'server died' messages are there?
  if($@ =~ /terminating connection due to administrator command/
     || $@ =~ /no connection to the server/
     || $@ =~ /the database system is shutting down/
     || $@ =~ /message type 0x[\d]+ arrived from server/
     || $@ =~ /could not connect to server/
     || $@ =~ /server closed the connection unexpectedly/
    )
  {
    $kernel->post('logger' => 'alert' => { To => 'SNAGalerts@asu.edu', Subject => "Error on " . HOST_NAME . "::alerts", Message => $@ } );
    delete $heap->{connected};
    delete $heap->{hbs_s_sth};
    delete $heap->{evt_sth};
    delete $heap->{create_alrt_sth};
    delete $heap->{update_alrt_sth};
    $kernel->delay("connect" => 60);
    #return "Lost DB Connection";
    return -1;
  }
  elsif($@ =~ /key violates unique constraint/)
  {
    $heap->{dbh}->rollback;
    if($commit_after_insert)
    {
      print "Primary key violation in single insert mode: $@\n" if $debug;
    }
    else
    {
      print "Primary key violation in transaction mode, reverting to single insert mode\n" if $debug;
      $kernel->call('object' => 'load' => $parcel, 1);
    }
  }
  elsif($@)
  {
    $heap->{dbh}->rollback;
    $kernel->post('logger' => 'alert' => { To => 'SNAGdev@asu.edu', Message => $@ } );
    $kernel->post('logger' => 'log' => "Uncaught Error: error --> $@");
    $kernel->post('logger' => 'log' => "Uncaught Error: row ----> $row");
    #return "Uncaught Error";
    return -1;
  }
  return 0; ## SUCCESS
}

1;
