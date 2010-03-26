package SNAG::Server::SNAGDBI; 
use base qw(SNAG::Server);

use strict;
use SNAG;
use POE;
use Carp qw(carp croak);

use DBI;
use FileHandle;
use Devel::Size qw(total_size);

my $rec_sep = REC_SEP;
my $monthly_tables; ## defined below
my $debug = $SNAG::flags{debug};
my ($stat_ref, $stats);

################################
sub new
################################
{
  my $type = shift;
  $type->SUPER::new(@_);

  my %params = @_;
  my $args = delete $params{Args};
  my $alias = delete $params{Alias};

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

        my $loadsub = 'load_' . $driver;
        no strict 'refs';
        $kernel->state('load' => \&{$loadsub});
        print "Using load method '$loadsub'\n" if $debug;

        $kernel->yield('connect');

        my $target_time = time();
        while(++$target_time % 60){}
        $heap->{stats_next_time} = int ( $target_time + 60 );
        $kernel->alarm('stats' => $heap->{stats_next_time});
      },

      connect => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        delete $heap->{dbh};

        eval
        {
          $heap->{dbh} = DBI->connect($args->{dsn}, $args->{user}, $args->{pw}, { AutoCommit => 0 }) or die $!;
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
      stats => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
      
        $heap->{stats_next_time} += 60;
        $kernel->alarm('stats' => $heap->{stats_next_time});

        my $stat_ref = ();
        my $stat_prefix = HOST_NAME . "[$alias]";
        my $time = time();
        $kernel->post('client' => 'sysrrd' => 'load' => $stat_prefix . ":db_trans:1g:$time:" . $stats->{ins});
        $stats->{ins} = 0;
        $kernel->post('client' => 'sysrrd' => 'load' => $stat_prefix . ":snags_mem_heap:1g:$time:" . (total_size($heap) + 0));
      },
    }
  );
}

sub load_mysql
{
  my ($heap, $kernel, $parcel) = @_[HEAP, KERNEL, ARG0];

  return "Not connected to DB" unless $heap->{connected};

  my $values;
  foreach my $row (@$parcel)
  {
    print "$row\n" if $debug;

    unless($row)
    {
      print "Empty Row\n" if $debug;
      next;
    }

    #$row =~ s/([\'\"])/\\$1/g;
    $row =~ s/([\'\"\\])/\\$1/g;
    my @c = split /$rec_sep/, $row, -1;
    my $table = shift @c;

    if($monthly_tables->{$table})
    {

      my $month;
      unless($c[-1])
      {
        ### If the last column is empty, its an autoincrement placeholder
        ###   The date column will be the third from the last
        ($month) = ($c[-3] =~ /^(\d+\D+\d+)/);
        $month =~ s/\D+/_/;
      }
      else
      {
        ### Otherwise timestamp will be the second to last column
        ($month) = ($c[-2] =~ /^(\d+\D+\d+)/);
        $month =~ s/\D+/_/;
      }

      $table .= "_$month";
    }

    push @{$values->{$table}}, \@c;
  }

LOAD:
  eval
  {
    while (my ($table, $arrayref) = each %$values)
    {
      my $sql = "replace into $table values" . join ",", map { " ('" . (join "', '",  @$_) . "')" } @$arrayref;
      $heap->{dbh}->do($sql) or die "Failed loading \'$sql\':" . $heap->{dbh}->errstr;
      $stats->{ins}++;
    }
  };
  if($@ =~ /MySQL server has gone away/ || $@ =~ /Lost connection to MySQL server during query/)
  {
    $kernel->post('logger' => 'log' => $@);
    delete $heap->{connected};
    $kernel->delay("connect" => 10);
    return "Lost DB Connection"; 
  }
  elsif($@ =~ /Table \'SNAG\.(\w+)\' doesn\'t exist/)
  {
    my $table = $1;
    my ($prefix, $date) = split /_/, $table, 2;

    if($monthly_tables->{$prefix})
    {
      eval
      {
        print "Creating table: $table ($date)\n" if $debug;
        $heap->{dbh}->do($monthly_tables->{$prefix}->($date)) or die $heap->{dbh}->errstr;
        goto LOAD;
      };
      if($@)
      {
        return "Unable to create montly table: $@";
      }
    }
    else
    {
      return "Table $table does not exist";
    }
  }
  elsif($@)
  {
    $kernel->post('logger' => 'alert' => { To => 'rjstrong@asu.edu', Message => $@ } );
    $kernel->post('logger' => 'log' => $@);
    return "Uncaught Error"; ## This needs to stay
  }

  return 0; ## SUCCESS
}

$monthly_tables =
{
  'acllog' => sub
  {
    my $date = shift;
return <<END_ACLLOG
CREATE TABLE `acllog_$date` (
  `sip` varchar(16) NOT NULL default '',
  `sport` int(11) default NULL,
  `dip` varchar(16) NOT NULL default '',
  `dport` int(11) default NULL,
  `proto` varchar(128) default NULL,
  `acl` varchar(128) default NULL,
  `action` varchar(128) default NULL,
  `seen` datetime NOT NULL default '0000-00-00 00:00:00',
  `server` varchar(255) default NULL,
  KEY `acllog_sip_seen_idx` (`sip`,`seen`),
  KEY `acllog_dip_idx` (`dip`,`seen`),
  KEY `acllog_seen_idx` (`seen`),
  KEY `acllog_server_idx` (`server`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1
END_ACLLOG
  },

  'apselfsub' => sub
  {
    my $date = shift;

return <<END_APSELFSUB
CREATE TABLE `apselfsub_$date` (
  `ip` varchar(50) NOT NULL default '',
  `uid` varchar(128) NOT NULL default '',
  `opt` varchar(255) default NULL,
  `type` varchar(50) NOT NULL default '',
  `seen` datetime NOT NULL default '0000-00-00 00:00:00',
  `server` varchar(128) NOT NULL default '',
  PRIMARY KEY  (`ip`,`seen`,`uid`(16),`type`(16)),
  KEY `uid_seen_idx` (`uid`(16),`seen`),
  KEY `type_seen_idx` (`type`,`seen`),
  KEY `opt_seen_idx` (`opt`,`seen`),
  KEY `server_seen_idx` (`server`,`seen`),
  KEY `time_idx` (`seen`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1
END_APSELFSUB

  },

  'dhcp' => sub
  {
    my $date = shift;

return <<END_DHCP
CREATE TABLE `dhcp_$date` (
  `ip` varchar(15) NOT NULL default '',
  `expires` int(10) unsigned default NULL,
  `mac` varchar(17) NOT NULL default '',
  `fqdn` varchar(255) default NULL,
  `type` varchar(25) NOT NULL default '',
  `seen` datetime NOT NULL default '0000-00-00 00:00:00',
  `server` varchar(128) default NULL,
  PRIMARY KEY  (`ip`,`seen`,`mac`,`type`),
  KEY `time_idx` (`seen`),
  KEY `idx_mac_seen` (`mac`,`seen`),
  KEY `server_seen_idx` (`server`,`seen`),
  KEY `type_seen_idx` (`type`,`seen`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1
END_DHCP

  },

  'dhcptmp' => sub
  {
    my $date = shift;

return <<END_DHCPTMP
CREATE TABLE `dhcptmp_$date` (
  `ip` varchar(15) NOT NULL default '',
  `expires` int(10) unsigned default NULL,
  `mac` varchar(17) NOT NULL default '',
  `fqdn` varchar(255) default NULL,
  `type` varchar(25) NOT NULL default '',
  `seen` datetime NOT NULL default '0000-00-00 00:00:00',
  `server` varchar(128) default NULL,
  PRIMARY KEY  (`ip`,`seen`,`mac`,`type`),
  KEY `time_idx` (`seen`),
  KEY `idx_mac_seen` (`mac`,`seen`),
  KEY `server_seen_idx` (`server`,`seen`),
  KEY `type_seen_idx` (`type`,`seen`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1
END_DHCPTMP

  },

  'cpvpn' => sub
  {
    my $date = shift;

return <<END_CPVPN
CREATE TABLE `cpvpn_$date` (
  `sip` varchar(15) NOT NULL default 'na',
  `dip` varchar(15) NOT NULL default 'na',
  `nat_sip` varchar(15) NOT NULL default 'na',
  `nat_dip` varchar(15) NOT NULL default 'na',
  `peer_gw` varchar(15) NOT NULL default 'na',
  `uid` varchar(128) NOT NULL default 'na',
  `opt_uid` varchar(128) NOT NULL default 'na',
  `detail` varchar(64) default NULL,
  `proto` varchar(32) default NULL,
  `sport` varchar(32) NOT NULL default 'na',
  `dport` varchar(32) NOT NULL default 'na',
  `icmp_type` int(5) default NULL,
  `icmp_code` int(5) default NULL,
  `rule` varchar(5) default NULL,
  `pool` varchar(255) default NULL,
  `ike` varchar(255) default NULL,
  `reason` varchar(255) default NULL,
  `enc_fail` varchar(255) default NULL,
  `route` varchar(255) default NULL,
  `msg` varchar(255) default NULL,
  `type` varchar(32) NOT NULL default '',
  `seen` datetime NOT NULL default '0000-00-00 00:00:00',
  `server` varchar(128) NOT NULL default '',
  PRIMARY KEY  (`uid`,`seen`,`type`,`dip`,`dport`,`server`),
  KEY `type_seen_idx` (`type`,`seen`),
  KEY `server_seen_idx` (`server`,`seen`),
  KEY `seen_idx` (`seen`),
  KEY `sip_idx` (`sip`),
  KEY `peer_gw_idx` (`peer_gw`),
  KEY `dip_idx` (`dip`),
  KEY `nat_sip_idx` (`nat_sip`),
  KEY `nat_dip_idx` (`nat_dip`),
  KEY `opt_uid_idx` (`opt_uid`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 MAX_ROWS=1000000000
END_CPVPN

  },

  'imap' => sub
  {
    my $date = shift;

return <<END_IMAP
CREATE TABLE `imap_$date` (
  `ip` varchar(50) NOT NULL default '',
  `uid` varchar(128) NOT NULL default '',
  `type` varchar(32) NOT NULL default '',
  `seen` datetime NOT NULL default '0000-00-00 00:00:00',
  `server` varchar(128) NOT NULL default '',
  PRIMARY KEY  (`ip`,`seen`,`uid`(16),`type`(16),`server`(16)),
  KEY `uid_seen_idx` (`uid`(16),`seen`),
  KEY `ip_seen_idx` (`ip`,`seen`),
  KEY `server_seen_idx` (`server`,`seen`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 MAX_ROWS=1000000000
END_IMAP

  }, 

  'klog' => sub
  {
    my $date = shift;

return <<END_KLOG
CREATE TABLE `klog_$date` (
  `ip` varchar(15) NOT NULL default '',
  `uid` varchar(128) NOT NULL default '',
  `opt` varchar(128) default NULL,
  `type` varchar(32) NOT NULL default '',
  `seen` datetime NOT NULL default '0000-00-00 00:00:00',
  `server` varchar(128) default NULL,
  PRIMARY KEY  (`ip`,`seen`,`uid`(16),`type`(16)),
  KEY `idx_uid_seen` (`uid`(16),`seen`),
  KEY `idx_seen` (`seen`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 MAX_ROWS=1000000000
END_KLOG

  },

  'krb' => sub
  {
    my $date = shift;

return <<END_KRB
CREATE TABLE `krb_$date` (
  `ip` varchar(15) NOT NULL default '',
  `uid` varchar(128) NOT NULL default '',
  `principal` varchar(255) NOT NULL default '',
  `type` varchar(10) default NULL,
  `seen` datetime NOT NULL default '0000-00-00 00:00:00',
  `server` varchar(128) default NULL,
  PRIMARY KEY  (`ip`,`seen`,`uid`,`principal`(16)),
  KEY `time_idx` (`seen`),
  KEY `idx_uid_seen` (`uid`(16),`seen`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 MAX_ROWS=1000000000
END_KRB

  },

  'nat' => sub
  {
    my $date = shift;

return <<END_NAT
CREATE TABLE `nat_$date` (
  `ip` varchar(50) NOT NULL default '',
  `xip` varchar(50) NOT NULL default '',
  `type` varchar(50) NOT NULL default '',
  `seen` datetime NOT NULL default '0000-00-00 00:00:00',
  `server` varchar(128) NOT NULL default '',
  PRIMARY KEY  (`ip`,`xip`,`type`,`seen`,`server`(16)),
  KEY `ip_seen_idx` (`ip`,`seen`),
  KEY `xip_seen_idx` (`xip`,`seen`),
  KEY `server_seen_idx` (`server`,`seen`),
  KEY `type_idx` (`type`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 
END_NAT
  },


  'nidpool' => sub
  {
    my $date = shift;

return <<END_NIDPOOL
CREATE TABLE `nidpool_$date` (
  `mac` varchar(17) NOT NULL default '',
  `pool` varchar(128) NOT NULL default '',
  `type` varchar(32) NOT NULL default '',
  `seen` datetime NOT NULL default '0000-00-00 00:00:00',
  `server` varchar(255) default NULL,
  PRIMARY KEY  (`mac`,`seen`,`pool`,`type`),
  KEY `pool_idx` (`pool`),
  KEY `time_idx` (`seen`),
  KEY `server_seen_idx` (`server`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1
END_NIDPOOL

  },

  'perfigo' => sub
  {
    my $date = shift;

return <<END_PERFIGO
CREATE TABLE `perfigo_$date` (
  `ip` varchar(15) NOT NULL default '',
  `mac` varchar(17) NOT NULL default '',
  `uid` varchar(128) NOT NULL default '',
  `type` varchar(32) NOT NULL default '',
  `seen` datetime NOT NULL default '0000-00-00 00:00:00',
  `server` varchar(128) default NULL,
  PRIMARY KEY  (`ip`,`seen`,`uid`,`mac`,`type`),
  KEY `uid_seen_idx` (`uid`,`seen`),
  KEY `mac_seen_idx` (`mac`,`seen`),
  KEY `time_idx` (`seen`),
  KEY `type_seen_idx` (`type`,`seen`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1
END_PERFIGO

  },

  'pop' => sub
  {
    my $date = shift;

return <<END_POP
CREATE TABLE `pop_$date` (
  `ip` varchar(50) NOT NULL default '',
  `uid` varchar(128) NOT NULL default '',
  `type` varchar(32) NOT NULL default '',
  `seen` datetime NOT NULL default '0000-00-00 00:00:00',
  `server` varchar(128) NOT NULL default '',
  PRIMARY KEY  (`ip`,`seen`,`uid`(16),`type`(16),`server`(16)),
  KEY `uid_seen_idx` (`uid`(16),`seen`),
  KEY `ip_seen_idx` (`ip`,`seen`),
  KEY `server_seen_idx` (`server`,`seen`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1
END_POP

  },

  'ppp' => sub
  {
    my $date = shift;

return <<END_PPP
CREATE TABLE `ppp_$date` (
  `ip` varchar(15) default NULL,
  `uid` varchar(128) NOT NULL default '',
  `type` varchar(50) NOT NULL default '',
  `seen` datetime NOT NULL default '0000-00-00 00:00:00',
  `server` varchar(128) default NULL,
  PRIMARY KEY  (`uid`(16),`seen`,`type`),
  KEY `time_idx` (`seen`),
  KEY `idx_uid_seen` (`uid`(16),`seen`),
  KEY `idx_ip_seen` (`ip`,`seen`),
  KEY `server_seen_idx` (`server`,`seen`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1
END_PPP

  }, 

  'spaz' => sub
  {
    my $date = shift;

return <<END_SPAZ
CREATE TABLE `spaz_$date` (
  `ip` varchar(15) default NULL,
  `uid` varchar(128) default NULL,
  `port` varchar(255) default NULL,
  `old_val` varchar(255) default NULL,
  `new_val` varchar(255) default NULL,
  `type` varchar(255) default NULL,
  `seen` datetime default NULL,
  `server` varchar(128) default NULL,
  `seq` bigint(20) NOT NULL auto_increment,
  PRIMARY KEY  (`seq`),
  KEY `time_idx` (`seen`),
  KEY `server_seen_idx` (`server`(16),`seen`),
  KEY `uid_seen_idx` (`uid`(16),`seen`),
  KEY `ip_seen_idx` (`ip`,`seen`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1
END_SPAZ

  }, 

  'ssh' => sub
  {
    my $date = shift;

return <<END_SSH
CREATE TABLE `ssh_$date` (
  `ip` varchar(50) NOT NULL default '',
  `uid` varchar(128) NOT NULL default '',
  `type` varchar(50) NOT NULL default '',
  `seen` datetime NOT NULL default '0000-00-00 00:00:00',
  `server` varchar(128) NOT NULL default '',
  PRIMARY KEY  (`ip`,`uid`(16),`type`,`seen`,`server`(16)),
  KEY `uid_seen_idx` (`uid`(16),`seen`),
  KEY `ip_seen_idx` (`ip`,`seen`),
  KEY `server_seen_idx` (`server`,`seen`),
  KEY `server_uid_idx` (`server`,`uid`),
  KEY `type_idx` (`type`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1
END_SSH

  },

  'su' => sub
  {
    my $date = shift;
 
return <<END_SU
CREATE TABLE `su_$date` (
  `uid_su` varchar(128) NOT NULL default '',
  `uid` varchar(128) NOT NULL default '',
  `type` varchar(50) default NULL,
  `seen` datetime NOT NULL default '0000-00-00 00:00:00',
  `server` varchar(128) NOT NULL default '',
  PRIMARY KEY  (`uid`(16),`seen`,`uid_su`(16),`server`(16)),
  KEY `uid_su_seen_idx` (`uid_su`(16),`seen`),
  KEY `server_seen_idx` (`server`,`seen`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1
END_SU

  },

  'webauth' => sub
  {
    my $date = shift;

return <<END_WEBAUTH
CREATE TABLE `webauth_$date` (
  `ip` varchar(15) default NULL,
  `uid` varchar(128) default NULL,
  `callapp` text default NULL,
  `type` varchar(50) default NULL,
  `seen` datetime default NULL,
  `server` varchar(128) default NULL,
  `seq` bigint(20) NOT NULL auto_increment,
  PRIMARY KEY  (`seq`),
  KEY `time_idx` (`seen`),
  KEY `idx_ip_seen` (`ip`,`seen`),
  KEY `idx_uid_seen` (`uid`(16),`seen`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 MAX_ROWS=1000000000
END_WEBAUTH
  },

  'winlogon' => sub
  {
    my $date = shift;

return <<END_WEBAUTH
CREATE TABLE `winlogon_$date` (
  `ip` varchar(15) default NULL,
  `uid` varchar(128) default NULL,
  `domain` varchar(128) default NULL,
  `event_id` varchar(15) default NULL,
  `logon_type` varchar(15) default NULL,
  `logon_id` varchar(64) default NULL,
  `opt` text default NULL,
  `type` varchar(50) default NULL,
  `seen` datetime default NULL,
  `server` varchar(128) default NULL,
  `seq` bigint(20) NOT NULL auto_increment,
  PRIMARY KEY  (`seq`),
  KEY `time_idx` (`seen`),
  KEY `idx_ip_seen` (`ip`,`seen`),
  KEY `idx_uid_seen` (`uid`(16),`seen`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 MAX_ROWS=1000000000
END_WEBAUTH
  },

  'winauth' => sub
  {
    my $date = shift;

return <<END_WEBAUTH
CREATE TABLE `winauth_$date` (
  `ip` varchar(15) default NULL,
  `uid` varchar(128) default NULL,
  `domain` varchar(128) default NULL,
  `event_id` varchar(15) default NULL,
  `opt` text default NULL,
  `type` varchar(50) default NULL,
  `seen` datetime default NULL,
  `server` varchar(128) default NULL,
  `seq` bigint(20) NOT NULL auto_increment,
  PRIMARY KEY  (`seq`),
  KEY `time_idx` (`seen`),
  KEY `idx_ip_seen` (`ip`,`seen`),
  KEY `idx_uid_seen` (`uid`(16),`seen`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 MAX_ROWS=1000000000
END_WEBAUTH
  },

  'authd' => sub
  {
    my $date = shift;

return <<END_AUTHD
CREATE TABLE `authd_$date` (
  `ip` varchar(15) default NULL,
  `uid` varchar(128) default NULL,
  `callapp` text default NULL,
  `callhost` varchar(255) default NULL,
  `opt` varchar(255) default NULL,
  `type` varchar(50) default NULL,
  `seen` datetime default NULL,
  `server` varchar(128) default NULL,
  `seq` bigint(20) NOT NULL auto_increment,
  PRIMARY KEY  (`seq`),
  KEY `time_idx` (`seen`),
  KEY `idx_ip_seen` (`ip`,`seen`),
  KEY `idx_uid_seen` (`uid`(16),`seen`)
)  ENGINE=MyISAM DEFAULT CHARSET=latin1 MAX_ROWS=1000000000
END_AUTHD
  },

  'edna' => sub
  {
    my $date = shift;

return <<END_EDNA
CREATE TABLE `edna_$date` (
  `ip` varchar(15) NOT NULL default '',
  `uid` text NOT NULL,
  `service_path` text NOT NULL,
  `function_name` text NOT NULL,
  `http_clientip` text NOT NULL,
  `http_url` text NOT NULL,
  `transaction_id` text NOT NULL,
  `message` text NOT NULL,
  `opt` text NOT NULL,
  `type` varchar(50) default NULL,
  `seen` datetime NOT NULL default '0000-00-00 00:00:00',
  `server` varchar(128) NOT NULL default '',
  `seq` bigint(20) NOT NULL auto_increment,
  PRIMARY KEY  (`seq`),
  KEY `ip_seen_idx` (`ip`,`seen`),
  KEY `uid_seen_idx` (`uid`(64),`seen`),
  KEY `http_url_seen_idx` (`http_url`(256),`seen`),
  KEY `service_path_seen_idx` (`service_path`(256),`seen`),
  KEY `server_seen_idx` (`server`,`seen`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 MAX_ROWS=1000000000
END_EDNA
  },

  'win' => sub
  {
    my $date = shift;

return <<END_WIN
CREATE TABLE `win_$date` (
  `ip` varchar(15) default NULL,
  `uid` varchar(128) default NULL,
  `domain` varchar(128) default NULL,
  `logon_type` varchar(128) default NULL,
  `type` varchar(128) default NULL,
  `seen` datetime default NULL,
  `server` varchar(128) default NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1
END_WIN

  },

  'sslvpn' => sub
  {
    my $date = shift;
return <<END_SSLVPN
CREATE TABLE `sslvpn_$date` (                                                                                                           
  `in_ip` varchar(15) NOT NULL default '',
  `in_port` int(6) NOT NULL default '0',
  `out_ip` varchar(15) NOT NULL default '',
  `out_port` int(6) NOT NULL default '0',
  `protocol` varchar(128) default NULL,
  `uid` varchar(128) NOT NULL default '',                                                                                                  
  `seen` datetime NOT NULL default '0000-00-00 00:00:00',                                                                                  
  `server` varchar(128) NOT NULL default '',                                                                                               
  PRIMARY KEY  (`in_ip`, `out_ip`,`seen`,`uid`(16)),
  KEY `uid_seen_idx` (`uid`(16),`seen`),                                                                                                   
  KEY `ip_out_seen_idx` (`out_ip`,`seen`),
  KEY `ip_in_seen_idx` (`in_ip`,`seen`),
  KEY `server_seen_idx` (`server`,`seen`),                                                                                                 
  KEY `time_idx` (`seen`)                                                                                                                  
) ENGINE=MyISAM DEFAULT CHARSET=latin1 
END_SSLVPN

  },

 'wifi' => sub
  {
    my $date = shift;

return <<END_WIFI
CREATE TABLE `wifi_$date` (                                                                                                           
  `mac` varchar(17) NOT NULL default '00:00:00:00:00:00',
  `ap` varchar(50) NOT NULL default '',
  `type` varchar(50) NOT NULL default '',
  `seen` datetime NOT NULL default '0000-00-00 00:00:00',                                                                                  
  `wism` varchar(50) NOT NULL default '',
  PRIMARY KEY  (`mac`, `ap`,`type`,`seen`),
  KEY `mac_seen_idx` (`mac`(17),`seen`),                                                                                                   
  KEY `time_idx` (`seen`)                                                                                                                  
) ENGINE=MyISAM DEFAULT CHARSET=latin1 
END_WIFI

  },

};


1;
