package SNAG::Source::apache;
use base qw/SNAG::Source/;

use strict;
use Date::Manip;
use SNAG;

use FreezeThaw qw/freeze/;
use LWP::UserAgent;
use Date::Manip;
use Date::Format;

use POE;
use POE::Wheel::Run;
use Carp qw(carp croak);
use Data::Dumper;
use Config::General;

my %scoreboard_keys =
(
  '_' => 'web_sb_waiting',
  'S' => 'web_sb_starting',
  'R' => 'web_sb_reading',
  'W' => 'web_sb_sending',
  'K' => 'web_sb_keepalive',
  'D' => 'web_sb_dns',
  'C' => 'web_sb_closing',
  'L' => 'web_sb_logging',
  'G' => 'web_sb_graceful',
  'I' => 'web_sb_idlecleanup',
  '\.' => 'web_sb_open',
);

#################################
sub new
#################################
{
  my $package = shift;
  $package->SUPER::new(@_);

  my $mi = $package . '->new()';

  croak "$mi requires an even number of parameters" if (@_ & 1);
  my %params = @_;

  croak "$mi needs an Alias parameter" unless exists $params{Alias};
  my $alias = delete $params{Alias};

  ## Set this flag if there are multiple web servers on this host
  ##   If set, the host/port string will be sent as a 'multi' to the rrd server
  my $multi_flag = delete $params{Multiple};

  foreach my $key (keys %params)
  {
    warn "Unknown parameter $key";
  }

  my $debug = $SNAG::flags{debug};

  my $rrd_dest = HOST_NAME;
  if($multi_flag)
  {
    $rrd_dest .= '[' . $alias . ']';
    $rrd_dest =~ s/:/_/g;
  }

  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        $heap->{ua} = LWP::UserAgent->new;
        $heap->{ua}->agent('SNAG Client ' . VERSION);

        $kernel->sig( CHLD => 'catch_sigchld' );

        $kernel->yield('server_stats');
        $kernel->yield('server_info');
      },

      server_stats => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->delay($_[STATE] => 60);

        if($heap->{server_stats_wheel})
        {
          $kernel->post("logger" => "log" =>  "SNAG::Source::apache: server_stats is still running, skipping");
        }
        else
        {
	  $heap->{server_stats_wheel} = POE::Wheel::Run->new
	  (
	    Program => sub
		       {
                         my $status_url = "http://localhost/server-status?auto";
			 my $get_status = $heap->{ua}->request( HTTP::Request->new(GET => $status_url) );

			 if($get_status->is_success)
			 {
			   my $content = $get_status->content;
			   print "$content\n";
			 }
                         else
                         {
                           print STDERR "could not get $status_url\n";
                         }
		       },
	    StdioFilter  => POE::Filter::Line->new(),
	    StderrFilter => POE::Filter::Line->new(),
	    Conduit      => 'pipe',
	    StdoutEvent  => 'server_stats_stdio',
	    StderrEvent  => 'stderr',
	    CloseEvent   => "server_stats_close",
          );
        }
      },

      server_stats_stdio => sub
      {
        my ($kernel, $heap, $input) = @_[KERNEL, HEAP, ARG0];

	my ($key, $val) = ($input =~ /^([\w\s]+): (.+)$/);

        my $time = time;

	if($key && $val)
	{
	  if($key eq 'Total Accesses')
	  {
	    $kernel->post("client" => "sysrrd" => "load" => join ':', ($rrd_dest, 'web_accesses', '1d', $time, $val));
	  }
	  elsif($key eq 'Total kBytes')
	  {
            $kernel->post("client" => "sysrrd" => "load" => join ':', ($rrd_dest, 'web_kbytes', '1d', $time, $val));
	  }
	  elsif($key eq 'Uptime')
	  {
            $kernel->post("client" => "sysrrd" => "load" => join ':', ($rrd_dest, 'web_uptime', '1g', $time, $val));
	  }
	  elsif($key eq 'BusyWorkers' || $key eq 'BusyServers')
	  {
            $kernel->post("client" => "sysrrd" => "load" => join ':', ($rrd_dest, 'web_busy', '1g', $time, $val));
	  }
	  elsif($key eq 'IdleWorkers' || $key eq 'IdleServers')
	  {
            $kernel->post("client" => "sysrrd" => "load" => join ':', ($rrd_dest, 'web_idle', '1g', $time, $val));
	  }
	  elsif($key eq 'Scoreboard')
	  {
            while( my ($key, $rrd) = each %scoreboard_keys)
	    {
              my $count;
              $count++ while $val =~ /$key/g;

              if($count)
              {
                $kernel->post("client" => "sysrrd" => "load" => join ':', ($rrd_dest, $rrd, '1g', $time, $count));
              }
            }
          }
        }
      },

      stderr => sub
      {
        my ($kernel, $heap, $input) = @_[KERNEL, HEAP, ARG0];

        $kernel->post("logger" => "log" =>  "SNAG::Source::apache: $input");
      },

      server_stats_close => sub
      {
        my ($kernel, $heap, $input) = @_[KERNEL, HEAP, ARG0];

        delete $heap->{server_stats_wheel};
      },

      server_info => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->delay($_[STATE] => 3600);

        if($heap->{server_info_wheel})
        {
          $kernel->post("logger" => "log" =>  "SNAG::Source::apache: server_info is still running, skipping");
        }
        else
        {
	  $heap->{server_info_wheel} = POE::Wheel::Run->new
	  (
	    Program => sub
		       {
                         my $info_url = "http://127.0.0.1:80/server-info";
                         my $get_info = $heap->{ua}->request( HTTP::Request->new(GET => $info_url) );

			 if($get_info->is_success)
			 {
			   my $content = $get_info->content;
                           $content =~ s/\<[^\>]+\>//gm;
			   print "$content\n";
			 }
                         else
                         {
                           print STDERR "could not get $info_url\n";
                         }
		       },
	    StdioFilter  => POE::Filter::Line->new(),
	    StderrFilter => POE::Filter::Line->new(),
	    Conduit      => 'pipe',
	    StdoutEvent  => 'server_info_stdio',
	    StderrEvent  => 'stderr',
	    CloseEvent   => "server_info_close",
          );
        }
      },

      server_info_stdio => sub
      {
        my ($kernel, $heap, $input) = @_[KERNEL, HEAP, ARG0];
   
        $heap->{info_content} .= "$input\n";
      },

      server_info_close => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP ];

        my $key;

        if($multi_flag)
        {
          $key = $alias . '_apache_server_info';
        }
        else
        {
          $key = 'apache_server_info';
        }


        if($heap->{info_content} ne $heap->{apache_data}->{$key})
        {
          my $info;

          $info->{host} = HOST_NAME;
          $info->{seen} = time2str("%Y-%m-%d %T", time);

          $info->{conf}->{$key} = { 'contents' => $heap->{info_content} };

          $heap->{apache_data}->{$key} = $heap->{info_content};
          ## Populate meta-info
          if($heap->{info_content} =~ m/Config File: (.*\.conf)/)
          {
            $heap->{apache_conf} = $1;
          }

          my @split = split(/\//, $heap->{apache_conf});
          my $level = 0;
          foreach my $s (@split)
          { 
            ## Find where in our path is the base apache install
            last if ($s =~ /apache/);
            $level++;
          }

          my $base;
          my $cur = 1;
          while($cur <= $level)
          { 
            $base .= "/$split[$cur]";
            $cur++;
          }

          my @path;
          push (@path, $base);
          push (@path, $base . "/conf");
          push (@path, $base . "/conf/extra");
          push (@path, $base . "/conf/vhosts.d");
          eval
          {
            $kernel->post("logger" => "log" =>  "SNAG::Source::apache: Parsing log file: $heap->{apache_conf}");
            my $conf = new Config::General(
                  -ConfigFile => "$heap->{apache_conf}",
                  -ConfigPath => \@path,
                  -UseApacheInclude => 1,
                  -IncludeRelative => 1,
                  -IncludeDirectories => 1,
                  -IncludeGlob => 1,
                  -SlashIsDirectory => 1,
                  -SplitPolicy => 'equalsign',
                  -CComments => 0,
                  -BackslashEscape => 1,
                    );
            my %config = $conf->getall;
          
           my $vhost = $config{VirtualHost};
           if(!$config{VirtualHost})
           { 
             $vhost = $config{NameVirtualHost};
           }
           my ($obj, $port, $dup, $cert);
           # Need to use DUP to check for duplicate entries so we don't violate pkey
           while( my ($key, $value) = each %$vhost)
           {  
             $port = $key;
             $port =~ s/\D+//g;
             
             if(ref $value eq 'HASH')
             {                      
               my $copy = $value;  
               $value = ();       
               foreach my $key (%$copy)
               {                      
                 push(@$value, $key);
               }                    
             }                     
             
             foreach my $val (@$value)
             { 
               $obj = ();
               $obj->{port} = $port;
               if($val =~  m/^SSLCertificateFile (\S+)$/)
               { 
                 $cert->{$1} = 1;
               }
               if(ref $val eq 'HASH')
               {
								 foreach my $k (keys %$val)
								 {
									 if($k =~ m/^SSLCertificateFile (\S+)$/)
									 { 
										 $cert->{$1} = 1;
									 }
									 if($k =~ m/^(ServerName|ServerAlias)\s+(\S+)$/)
									 {
										 push (@{$obj->{name}}, $2);
									 }
									 if($k =~ m/^DocumentRoot (\S+)$/)
									 {
										 $obj->{docroot} = $1;
									 }
									 if($k =~ /^(RewriteRule|Redirect) (\S+) (\S+)/)
									 {
										 push (@{$obj->{redirect}}, {match => $2, destination => $3});
									 }
									 if($k =~ /^Alias (\S+) (\S+)/)
									 {
										 push (@{$obj->{alias}}, {address => $1, source => $2});
									 }
								 }
               }

               foreach my $name (@{$obj->{name}})
               {
                 if(!$dup->{vhost}->{$name}->{$obj->{port}}->{$obj->{docroot}})
                 { 
                   if(!$obj->{docroot})
                   {
                     $kernel->post('client' => 'dashboard' => 'load' => join REC_SEP, ('events', HOST_NAME, 'snag', 'apache', 
                     'apache vhost without defined docroot',
                     "vhost: $name port: $obj->{port} config directive contains no docroot", '', time2str("%Y-%m-%d %T", time)) );
                   }
                   else
                   {
                     push @{$info->{'meta_web_vhost'}}, { meta_name => $name,
                                                          port => $obj->{port},
                                                          doc_root => $obj->{docroot} };
                     $dup->{vhost}->{$name}->{$obj->{port}}->{$obj->{docroot}} = 1;
                   }
                 }
                 foreach my $red (@{$obj->{redirect}})
                 {
                   if(!$dup->{redirect}->{$name}->{$red->{match}}->{$red->{destination}})
                   {
                     push @{$info->{'meta_web_redirect'}}, { meta_name => $name,
                                                             match => $red->{match},
                                                             destination => $red->{destination} };
                     $dup->{redirect}->{$name}->{$red->{match}}->{$red->{destination}} = 1;
                   }
                 }

                 foreach my $alias (@{$obj->{alias}})
                 {
                   if(!$dup->{alias}->{$name}->{$alias->{address}}->{$alias->{source}})
                   {
                     push @{$info->{'meta_web_alias'}}, { meta_name => $name,
                                                          address => $alias->{address},
                                                          source => $alias->{source} };
                     $dup->{alias}->{$name}->{$alias->{address}}->{$alias->{source}} = 1;
                   }
                 }
               }
             }
           } ## End Meta Fun
           $dup = ();
           foreach my $key (keys %$cert)
           {
             my $ci = `openssl x509 -text -in $key`;
             $kernel->post("logger" => "log" => "found cert: $key");
             $info->{conf}->{$key} = { contents => $ci };
           } 
         };
         if($@)
         {
           $kernel->post("logger" => "log" =>  "SNAG::Source::apache: ERROR: $@");   
         }

         $kernel->post('client' => 'sysinfo' => 'load' => freeze($info));
        }

        delete $heap->{apache_conf};
        delete $heap->{info_content};
        delete $heap->{server_info_wheel};
      },

      catch_sigchld => sub
      {
      },

    }
  );
}


1;
