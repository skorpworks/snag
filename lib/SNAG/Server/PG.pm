package SNAG::Server::PG; 
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

use FreezeThaw qw/freeze thaw/;

#use Apache::DBI::Cache;
use DBI;
use FileHandle;
use Data::Dumper;
my $rec_sep = REC_SEP;
my $debug = $SNAG::flags{debug};
my $verbose = $SNAG::flags{debug};

my $state;

my ($type, $module, $alias, $SNAGalias, $args);
my ($info, @vals, $query, $sql);
################################
sub new
################################
{
  $type = shift;
  $type->SUPER::new(@_);

  $alias = $type;
  $alias =~ s/.*\:\:([\w\.\-]+)$/$1/;

  $type = $type;
  $type =~ s/\:\:/\./g;
  $type =~ s/\:\:/\./g;

  $module = $type;
  $module =~ s/\:\:/\//g;
  $module .= '.pm';

  my %params = @_;
  my $source = delete $params{Source};
  $args = delete $params{Args};

  $SNAGalias = delete $params{Alias};
  $SNAGalias = $alias . '-' . $SNAGalias;

  croak "Args must be a hashref" if $args and ref $args ne 'HASH';
  croak "Args must contain values for 'dsn', 'user', and 'pw'" unless ($args->{dsn} && $args->{user} && $args->{pw});

  $args->{dsn} =~ /^DBI:(\w+):/i;
  my $driver = lc $1;
  croak "Unsupported DB driver ($driver)" unless $driver =~ /^(pg|mysql)$/;

  my $package = $type;
  $package =~ s/\:\:/\./g;

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

        $kernel->yield('status_timer');
        $kernel->yield('connect');
      },

      connect => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        delete $heap->{dbh};

        eval
        {
          $heap->{dbh} = DBI->connect($args->{dsn}, $args->{user}, $args->{pw}, { RaiseError => 1, AutoCommit => 1 }) or die $!;
          my $get_tables = $heap->{dbh}->table_info('', 'public', '%', 'TABLE');    
          my $tables = $heap->{dbh}->selectcol_arrayref($get_tables, { Columns => [3] }); 
                                           
        };
        if($@)
        {
          delete $heap->{connected};
          $heap->{failed_connect}++;
          $kernel->post('logger' => 'log' => "$type: failed to connect to $args->{dsn}: $@");
          $kernel->post('logger' => 'alert' => { From => 'SNAGcnb@example.com', 
                                                 To => 'foo@example.com', 
                                                 Subject => "Error on " . HOST_NAME . "::$SNAGalias" . "::connect", 
                                                 Message => $@ ,
                                               } ) if $heap->{failed_connect} >= 12;
          $kernel->delay($_[STATE] => 10 );
        }
        else
        {
          $kernel->post('logger' => 'log' => "$type: connected to $args->{dsn}");
          $heap->{connected} = 1;
          $heap->{failed_connect} = 0;
        }
      },

      status_timer => sub
      {
        my ($heap, $kernel) = @_[ HEAP, KERNEL ];
        $heap->{time} = time();
        $kernel->delay($_[STATE] => 5);
      },
    }
  );
}

sub load_pg
{
  my ($heap, $kernel, $parcel, $commit_after_insert) = @_[HEAP, KERNEL, ARG0, ARG1];

              
  eval
  {
    local $SIG{__WARN__} = sub
    {
      die @_;
    };

    die "DBI->ping failed: no connection to the server" unless $heap->{dbh}->ping();

    foreach my $row (@$parcel)
    {
      unless($row)
      {
        print "Empty Row\n" if $debug;
        next;
      }
			
			# We are a freezethaw ref
			if($row =~ m/^F/)
			{
        ($info) = thaw($row);
				(@vals) = split /,/, $info->{values};
				if($info->{type} eq 'insert')
				{
        	$query = "INSERT INTO $info->{table} ($info->{columns}) values (" . join(',', map('?', @vals)). ")";
					print "QUERY: $query\n" if $debug;
					print "VALS: " . join(':', @vals) . "\n" if $debug;
					$sql = $heap->{dbh}->prepare($query) || die "failed to prepare query: $query";
					$sql->execute(@vals) || die "failed to execute  query: $query";					
				}

			}
			else  ## Legacy way of passing information.  All new sources should pass frozen refs
			{
      	my ($ins_table, $ins_cols, $ins_tuple) = split /!_!/, $row;
             
      	my ($table, $foo) = split /:/, $ins_table;
      	my (@cols) = split /:/, $ins_cols;
      	my (@vals) = split /:/, $ins_tuple;

      	my $insert = "INSERT INTO $table (" . join(',', @cols) .  ") values (" . join(',', map('?', @cols)) . ")";
      	if($debug)
      	{
        	print "Query: $insert\n";
        	foreach (@vals)
        	{
          	print $_ . "\n";
        	}
      	}
      	my $query = $heap->{dbh}->prepare($insert);
      	$query->execute(@vals);
			}
    } #row
  };
  ## What other 'server died' messages are there?
  if($@ =~ /terminating connection due to administrator command/
     || $@ =~ /no connection to the server/
     || $@ =~ /the database system is shutting down/
     || $@ =~ /message type 0x[\d]+ arrived from server/
     || $@ =~ /could not connect to server/
     || $@ =~ /server closed the connection unexpectedly/
     || $@ =~ /failed to connect to/
    )
  {
    $kernel->post('logger' => 'log' => $@);
    $kernel->post('logger' => 'alert' => { From=> 'SNAGcnb@example.com',
                                           To => 'foo@example.com', 
                                           Subject => "Error - " . HOST_NAME . "::$SNAGalias" . "::load", 
                                           Message => $@ ,
                                         } );
    delete $heap->{connected};
    delete $heap->{sth};
    delete $heap->{dbh};
    $kernel->delay("connect" => 60);
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
  elsif($@ =~ /will create implicit index/)
  {
    print "$@\n" if $debug;
    $kernel->post('logger' => 'log' => "caught index: $@");
   
    # since the db handle is misbehaving, let's try killing it
    delete $heap->{connected};
    delete $heap->{sth};
    delete $heap->{dbh};
    $kernel->delay("connect" => 60);
    return -1;
  }
  elsif($@)
  {
    #$heap->{dbh}->rollback;
    print "$@\n" if $debug;
    $kernel->post('logger' => 'alert' => { To => 'SNAGdev@example.com', 
                                           Subject => "Uncaught error - " . HOST_NAME . "::$SNAGalias" . "::load",
                                           Message => $@ 
                                         } );
    $kernel->post('logger' => 'log' => "Uncaught Error: $@");
    return -1;
  }
  return 0; ## SUCCESS
}

1;
