package SNAG::Server::VPNDBI; 
use base qw(SNAG::Server);

use strict;
use utf8;
use SNAG;
use POE;
use Carp qw(carp croak);

use DBI;
use Socket qw(inet_aton);
use FileHandle;
use Devel::Size qw(total_size);

use Data::Dumper;

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

				$kernel->yield('connect');
			},

			connect => sub
			{
				my ($kernel, $heap) = @_[KERNEL, HEAP];

				delete $heap->{dbh};

				eval
				{
					$heap->{dbh} = DBI->connect($args->{dsn}, $args->{user}, $args->{pw}, { AutoCommit => 1, RaiseError => 1, mysql_auto_reconnect => 1 }) or die $!;

					$heap->{geo_update} = $heap->{dbh}->prepare("update geo set updated = ? where goid = ?");
					$heap->{geo_modify} = $heap->{dbh}->prepare("update geo set city = ?, country = ?, proxy_flag = ?, modified = ?, updated = ? where goid = ?");
					$heap->{geo_create} = $heap->{dbh}->prepare('insert into geo(snid, ip, aton, provider, city, country, proxy_flag, created, modified, updated) values(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
					$heap->{geo_history} = $heap->{dbh}->prepare('insert into geo_history(event, snid, ip, aton, provider, city, country, proxy_flag, prev_city, prev_country, prev_proxy_flag, timestamp) values(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
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

			load => sub
			{
				my ($heap, $kernel, $parcel) = @_[HEAP, KERNEL, ARG0];

				foreach my $row (@$parcel)
				{
					my %data = map { split /\=/, $_, 2 } split /;/, $row;

					eval
					{
						my $now = $data{timestamp} || time;

						if( $data{ip} && $data{provider} && $data{country} )
						{
							$data{city} ||= 'Unknown';

							my $proxy_flag = $data{country} eq 'A1' ? 1 : 0;
							my $city = normalize_city($data{city});

							my $country = normalize_country($data{country}, $heap->{dbh});

							if( my $ref = $heap->{dbh}->selectrow_hashref('select * from geo where ip = ? and provider = ?', undef, $data{ip}, $data{provider}) )
							{
								if( $ref->{updated} > $now )
								{
									print "ignoring stale update: now=$now db=$ref->{timestamp} row=$row\n" if $debug;
								}
								elsif( ( $ref->{city} eq $city )
								    && ( $ref->{country} eq $country )
								    && ( $ref->{proxy_flag} == $proxy_flag )
								  )
								{
									$heap->{geo_update}->execute($now, $ref->{goid}) or die $!;
								}
								else
								{
									print "changed: ip=$ref->{ip} provider=$ref->{provider} city_before=$ref->{city} city_now=$city country_before=$ref->{country} country_now=$country proxy_before=$ref->{proxy_flag} proxy_now=$proxy_flag\n" if $debug;
									$heap->{geo_modify}->execute($city, $country, $proxy_flag, $now, $now, $ref->{goid}) or die $!;
									$heap->{geo_history}->execute('modify', $ref->{snid}, $ref->{ip}, $ref->{aton}, $ref->{provider}, $city, $country, $proxy_flag, $ref->{city}, $ref->{country}, $ref->{proxy_flag}, $now) or die $!;
								}
							}
							else
							{
								my $aton = unpack "N", inet_aton($data{ip});

								if( my $get_snid = $heap->{dbh}->selectrow_hashref('select * from subnet where aton_st <= ? and aton_en >= ? order by cidr desc limit 1', undef, $aton, $aton) )
								{
									$heap->{geo_create}->execute($get_snid->{snid}, $data{ip}, $aton, $data{provider}, $city, $country, $proxy_flag, $now, $now, $now) or die $!;
									$heap->{geo_history}->execute('create', $get_snid->{snid}, $data{ip}, $aton, $data{provider}, $city, $country, $proxy_flag, undef, undef, undef, $now) or die $!;
								}
								else
								{
									$kernel->post('logger' => 'log' => "could not find a network for: ip=$data{ip}");
								}
							}
						}
						else
						{
							print "not sure what to do with this: $row" if $debug;
						}
					};
					if($@)
					{
						if($@ =~ /MySQL server has gone away/ || $@ =~ /Lost connection to MySQL server during query/)
						{
							$kernel->call('logger' => 'log' => $@);
							delete $heap->{connected};
							$kernel->delay("connect" => 10);
							return "Lost DB Connection"; 
						}
						else
						{
							$kernel->call('logger' => 'alert' => { To => 'jason.lavold@omicronmedia.com', Message => $@ } );
							$kernel->call('logger' => 'log' => $@);
							return "Uncaught Error"; ## This needs to stay
						}
					}
				}
				
				return 0; ## SUCCESS
			},
		}
	);
}

sub normalize_city
{
	my $city = shift;

	$city = join ' ', map { ucfirst(lc($_)) } split /[\s\_\-]/, $city;

	if($city eq 'Capelle%20aan%20den%20ijssel')
	{
		$city = 'Capelle';
	}
	elsif( $city eq 'Losangeles' )
	{
		$city = 'Los Angeles';
	}
	elsif( $city eq 'Zuerich' || $city =~ /^Z.rich$/ )
	{
		$city = 'Zurich';
	}
	elsif( $city eq 'Reykjav%edk')
	{
		$city = 'Reykjavik';
	}
	elsif( $city eq 'Lasvegas' )
	{
		$city = 'Las Vegas';
	}
	elsif( $city eq 'Budapest Vii. Keruelet')
	{
		$city = 'Budapest';
	}
	elsif( $city eq 'Bucuresti' )
	{
		$city = 'Bucharest';
	}
	elsif( $city eq 'Buenosaires' )
	{
		$city = 'Buenos Aires';
	}
	elsif( $city eq 'Frankfurt Am Main' )
	{
		$city = 'Frankfurt';
	}
	elsif( $city eq 'Miami Springs' )
	{
		$city = 'Miami';
	}
	elsif( $city eq 'Newyork' )
	{
		$city = 'New York';
	}
	elsif( $city eq 'North Atlanta' )
	{
		$city = 'Atlanta';
	}
	elsif( $city eq 'Sanjose' )
	{
		$city = 'San Jose';
	}
	elsif( $city eq 'Winterpark' )
	{
		$city = 'Winter Park';
	}
	elsif( $city eq 'New York City' )
	{
		$city = 'New York';
	}
	elsif( $city =~ /^S.o Paulo$/ || $city eq 'Saopaulo' )
	{
		$city = 'Sao Paulo';
	}
	elsif( $city =~ /^K.benhavn$/ )
	{
		$city = 'Copenhagen';
	}
	elsif( $city eq 'Lisboa' )
	{
		$city = 'Lisbon';
	}
	elsif( $city eq 'Panama' || $city eq 'Panamacity' )
	{
		$city = 'Panama City';
	}
	elsif( $city eq 'Sanpablo' )
	{
		$city = 'San Pablo';
	}

	return $city;
}

sub normalize_country
{
	my ($country, $dbh) = @_;

	$country = join ' ', map { ucfirst(lc($_)) } split /[\s\_\-]/, $country;

	if( my $get_code = $dbh->selectrow_hashref('select * from countries where country = ?', undef, $country ) )
	{
		$country = $get_code->{iso}; 
	}
	else
	{
		if( $country eq 'United States' )
		{
			$country = 'US';
		}
		elsif( $country eq 'Hong Kong' )
		{
			$country = 'HK';
		}
		elsif( $country eq 'Moldova, Republic Of' )
		{
			$country = 'MD';
		}
		elsif( $country eq 'A1' )
		{
			$country = 'XX';
		}
		elsif( $country eq 'A2' )
		{
			$country = 'XX';
		}
		elsif( $country eq 'O1' )
		{
			$country = 'XX';
		}

	}

	return uc($country);
}

1;
