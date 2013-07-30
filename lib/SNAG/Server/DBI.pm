package SNAG::Server::DBI; 
use base qw(SNAG::Server);

use strict;
use SNAG;
use POE;
use Carp qw(carp croak);

use DBI;
use FileHandle;

my $rec_sep = REC_SEP;
my $debug = $SNAG::flags{debug};

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
        print "Using load method '$loadsub'\n" if $debug;

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
          $kernel->call('logger' => 'log' => "$type: failed to connect to $args->{dsn}: $@");
          $kernel->delay($_[STATE] => 10 );
        }
        else
        {
          $kernel->call('logger' => 'log' => "$type: connected to $args->{dsn}");
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
    push @{$values->{$table}}, \@c;
  }

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
    $kernel->call('logger' => 'log' => $@);
    delete $heap->{connected};
    $kernel->delay("connect" => 10);
    return "Lost DB Connection"; 
  }
  elsif($@)
  {
    #$kernel->call('logger' => 'alert' => { To => 'jlavold@asu.edu', Message => $@ } );
    $kernel->call('logger' => 'log' => $@);
    return "Uncaught Error"; ## This needs to stay
  }

  return 0; ## SUCCESS
}

sub load_pg
{
  my ($heap, $kernel, $parcel, $commit_after_insert) = @_[HEAP, KERNEL, ARG0, ARG1];

  return "Not connected to DB" unless $heap->{connected};

  eval
  {
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

      my $sql = "insert into " . (shift @c) . " values('" . (join "\', \'", @c) . "\')";
      $heap->{dbh}->do($sql) or die "Failed loading \'$sql\':" . $heap->{dbh}->errstr;
      $heap->{dbh}->commit if $commit_after_insert;
    }
    $heap->{dbh}->commit unless $commit_after_insert;
  };
  if($@ =~ /terminating connection due to administrator command/) ## What other 'server died' messages are there?
  {
    $kernel->call('logger' => 'log' => $@);
    delete $heap->{connected};
    $kernel->delay("connect" => 10);
    return "Lost DB Connection";
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
    print "$@\n" if $debug;
    $kernel->call('logger' => 'log' => $@);
    return "Uncaught Error";
  }

  return 0; ## SUCCESS
}

1;
