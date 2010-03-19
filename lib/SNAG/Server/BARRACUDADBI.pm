package SNAG::Server::BARRACUDADBI; 
use base qw(SNAG::Server);

use strict;
use SNAG;
use POE;
use Carp qw(carp croak);

use DBI;
use FileHandle;

my $rec_sep = REC_SEP;
my $daily_tables; ## defined below

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
        print "Using load method '$loadsub'\n" if $SNAG::flags{debug};

        $kernel->yield('connect');
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
    print "$row\n" if $SNAG::flags{debug};

    unless($row)
    {
      print "Empty Row\n" if $SNAG::flags{debug};
      next;
    }

    #$row =~ s/([\'\"])/\\$1/g;
    $row =~ s/([\'\"\\])/\\$1/g;
    my @c = split /$rec_sep/, $row, -1;
    my $table = shift @c;

    #messages~_~2007/06/14 16:39:46~_~NA~_~~_~~_~2~_~3~_~ (sbl-xbl.spamhaus.org)~_~0~_~host-62-229-220-24.midco.net[24.220.229.62]~_~1181864386-22337-8-0~_~bcnet1~_~2007-06-14 16:39:45~_~

    if($daily_tables->{$table})
    {
      my ($day) = ($c[-2] =~ /^(\d+\D+\d+\D+\d+)/);
      $day =~ s/\D+/_/g;

      $table .= "_$day";
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
    }
  };
  if($@ =~ /MySQL server has gone away/ || $@ =~ /Lost connection to MySQL server during query/)
  {
    $kernel->post('logger' => 'log' => $@);
    delete $heap->{connected};
    $kernel->delay("connect" => 10);
    return "Lost DB Connection"; 
  }
  elsif($@ =~ /Table \'barracuuuda\.(\w+)\' doesn\'t exist/)
  {
    my $table = $1;
    my ($prefix, $date) = split /_/, $table, 2;

    if($daily_tables->{$prefix})
    {
      eval
      {
        print "Creating table: $table\n" if $SNAG::flags{debug};
        $heap->{dbh}->do($daily_tables->{$prefix}->($date)) or die $heap->{dbh}->errstr;
        goto LOAD;
      };
      if($@)
      {
        return "Unable to create daily table: $@";
      }
    }
    else
    {
      return "Table $table does not exist";
    }
  }
  elsif($@)
  {
    $kernel->post('logger' => 'alert' => { To => 'jlavold@asu.edu', Message => $@ } );
    $kernel->post('logger' => 'log' => $@);
    return "Uncaught Error"; ## This needs to stay
  }

  return 0; ## SUCCESS
}

$daily_tables =
{
  'messages' => sub
  {
    my $day = shift;
return <<END_MESSAGES
CREATE TABLE `messages_$day` (
  `recieved` datetime default NULL,
  `from` varchar(255) NOT NULL default '',
  `mailto` varchar(255) default NULL,
  `subject` text,
  `action` int(11) NOT NULL default '0',
  `reason` int(11) NOT NULL default '0',
  `reason_extra` text,
  `score` int(11) default NULL,
  `post_server` varchar(255) default NULL,
  `id` varchar(255) default NULL,
  `server` varchar(255) default NULL,
  `seen` datetime default NULL,
  `mid` bigint(20) NOT NULL auto_increment,
  PRIMARY KEY  (`mid`),
  KEY `idx_from_recieved` (`mailto`,`recieved`, `reason`, `action`),
  KEY `idx_action` (`action`)
) ENGINE=MyISAM AUTO_INCREMENT=330815532 DEFAULT CHARSET=latin1 MAX_ROWS=1000000000
END_MESSAGES
  },
};


1;
