package SNAG::Dispatch;

use strict;
use POE qw/Session/;
use Data::Dumper;
use Carp qw(carp croak);
use SNAG;
use File::Spec::Functions qw/catfile/;

our $shared_data = {};

my $state;

my $debug = $SNAG::flags{debug};

### Need to have new sub here to make it fit in with the other sources, once we get Dispatch
###  fully fleshed out, we won't need it anymore
##################################
sub new
##################################
{
  my $type = shift;

  my $mi = $type . '->new()';

  croak "$mi requires an even number of parameters" if (@_ & 1);
  my %params = @_;

  #croak "$mi needs an Alias parameter" unless exists $params{Alias};

  my $alias = delete $params{Alias};
  my $source = delete $params{Source};
  my $options = delete $params{Options};

  foreach my $p (keys %params)
  {
    warn "Unknown parameter $p";
  }

  #set shared_data defaults
  $shared_data->{systemstats_step} = 60;

  POE::Session->create
  (
    inline_states=>
    {
      _start => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        $kernel->post("logger" => "log" => "Dispatch: starting") if $debug;
        $heap->{epoch} = time() + 5; #trying to  avoid a race condition when epoch %60 would be a time just passed
        $shared_data->{timer_60} = $heap->{epoch};
        $shared_data->{timer_300} = $heap->{epoch};  
        while(++$shared_data->{timer_60} % 60){}   
        while(++$shared_data->{timer_300} % 300){}   
                                                                                                                                                                              
        $shared_data->{timer_60} = int ($shared_data->{timer_60});
        $shared_data->{timer_300} = int ($shared_data->{timer_300});

        $kernel->alarm('timer' => $shared_data->{timer_60});

        ### Populate all the static tags here
        $shared_data->{tags}->{'entity'}->{'system'} = 1;
 
        $shared_data->{tags}->{'os'}->{ lc(&OS) }->{ lc(&OSDIST) }->{ lc(&OSVER) } = 1;

        my $version = $SNAG::VERSION;
        $version =~ s/\.//;
        $shared_data->{tags}->{'version'}->{'snagc'}->{$version} = 1;
        $shared_data->{tags}->{'version'}->{'snagp'} = 1;

	$kernel->delay('delayed_start' => 10);
      },

      delayed_start => sub 
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        if(OS eq 'Windows')
        {
          require Win32::Service;
          import Win32::Service;

          $kernel->yield('check_win_services');
        }
        else
        {
          ### This is the only way to reliably determine if a linux host is a vmware guest
          if(OS eq 'Linux')
          {
            my $dmi_bin;
            if(-e '/usr/sbin/dmidecode')  {
              $dmi_bin = '/usr/sbin/dmidecode';
            }
            else
            {
              $dmi_bin = BASE_DIR . '/sbin/dmidecode';
            }	  
            foreach(`$dmi_bin`)
            {
              if(/Product Name:\s+(.+)\s*/)
              {
                my $model = $1;
                if($model eq 'VMware Virtual Platform')
                {
                  $shared_data->{tags}->{virtual}->{vmware}->{guest} = 1;
                  last;
                }
              }
            }
          }

	  $shared_data->{uuid} = UUID;

          require Proc::ProcessTable;

          $kernel->yield('check_process_table');
          $kernel->yield('check_mounts');
          $kernel->yield('check_virtual');
          $kernel->yield('check_checkpoint');
          $kernel->yield('check_bins');

          $kernel->delay('check_listening_ports' => 60); ### Give SystemStats enough time to start running
        }

        unless($SNAG::flags{nosysinfo})
        {
          $kernel->yield( 'dispatcher' => 'SNAG::Source::SystemInfo' );
        }

        unless($SNAG::flags{nosysstats})
        {
          $kernel->yield( 'dispatcher' => 'SNAG::Source::SystemStats' );
        }

        #if(HOST_NAME eq 'troz')
        #{
          #$kernel->yield( 'dispatcher' => 'SNAG::Source::update');
        #}
        #$kernel->yield('check_open_files');
      },
      
      timer => sub
      {  
        my ($kernel, $heap) = @_[KERNEL, HEAP];

        $shared_data->{timer_60} += 60;
        $shared_data->{timer_300} += 300 unless ($shared_data->{timer_60} % 300);

        $kernel->alarm('timer' => $shared_data->{timer_60});
      },

      dispatcher => sub
      {
        no strict 'refs';

        my ($kernel, $heap, $module) = @_[KERNEL, HEAP, ARG0];
        my $args = $_[ARG1] || {};

        my $source_key = $module;
        $source_key .= ",Alias=$args->{Alias}" if $args->{Alias};

        unless($heap->{running_sources}->{$source_key})
        {
          $kernel->post('logger' => 'log' => "Dispatch: loading: $source_key") if $SNAG::flags{debug};

          (my $module_file = $module) =~ s/::/\//g;
          $module_file .= ".pm";

          require $module_file;
          $module->new( %$args );

          $heap->{running_sources}->{$source_key} = 1;
        }
      },

      check_bins => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        #if(HOST_NAME =~ m/^s05-/)
        #{
        #  if ( -e '/usr/sbin/smartctl')
        #  {
        #    $kernel->yield( 'dispatcher' => 'SNAG::Source::Manager::smartctl', {Alias => 'snagc'}  );
        #  }
        #}
      },

      check_checkpoint => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->delay($_[STATE] => 3600);

        if(-e '/etc/cp-release')
        {
          $shared_data->{tags}->{service}->{firewall}->{checkpoint} = 1;
          $kernel->yield('dispatcher' => 'SNAG::Source::checkpoint' );
        } 

        #kludge for old-school stat gathering that resulted in 300sec rrds vs current 60
        if(-d '/home/admin/fwmonitor2')
        {
          $shared_data->{systemstats_step} = 300;
        }
      },

      check_virtual => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->delay($_[STATE] => 3600);

        if(-e '/usr/bin/xenstore-read')
        {
          my $release = `/usr/bin/xenstore-read domid`;
          chomp $release;

          if($release eq '0')
          {
            $shared_data->{tags}->{'virtual'}->{xen}->{host} = 1;
            $kernel->yield('dispatcher' => 'SNAG::Source::xen' );
          }
          elsif($release)
          {
            $shared_data->{tags}->{'virtual'}->{xen}->{guest} = 1;
          }
        }

        if(-e '/usr/sbin/vserver-stat')
        {
          $shared_data->{tags}->{'virtual'}->{vserver}->{host} = 1;
          $kernel->yield('dispatcher' => 'SNAG::Source::vserver' );
        }

        if(-e '/proc/vmware/vm/' || -e '/var/lib/vm/guests/')
        {
          $shared_data->{tags}->{'virtual'}->{vmware}->{host} = 1;
        }
      },

      check_mounts => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->delay($_[STATE] => 3600);

        my @mount_output;

        if(OS eq 'Linux')
        {
          @mount_output = `/bin/mount -v`;
        }
        else
        {
          @mount_output = `/sbin/mount -v`;
        }

        my $mounts;
        foreach my $mount_line (@mount_output)
        {
          my ($dev, $mount, $type, $args) = ($mount_line =~ m#^(\S+) on (\S+) type (\w+) (.+)$#);
    
          if($type eq 'nfs')
          {
            $shared_data->{tags}->{storage}->{nfs}->{client} = 1;
          }

          next unless $type =~ /^(ufs|ext\d|tmpfs|xfs|jfs|reiserfs|nfs)$/;

          $dev =~ s#/dev/##;
          $mounts->{$dev} = { mount => $mount, type => $type, args => $args };
        }

        $shared_data->{mounts} = $mounts;
      },

      check_listening_ports => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->delay($_[STATE] => 3600);

        my @server_uris;

        foreach my $port (sort keys %{$shared_data->{listening_ports}})
        {
          if($port =~ /^(80)$/) ### Known web ports
          {
            foreach my $address (sort keys %{$shared_data->{listening_ports}->{$port}})
            {
              my $key = ($address eq '*' ? 'localhost' : $address) . ':' . $port;
              push @server_uris, $key;
            }
          }
        }

        my $multi_flag = scalar @server_uris > 1 ? 1 : 0;

        foreach my $alias (@server_uris)
        {
					unless(OS eq 'Windows')
					{
            $kernel->yield('dispatcher' => 'SNAG::Source::apache', { Alias => $alias, Multiple => $multi_flag } );
					}
        }

      },

      check_process_table => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->delay($_[STATE] => 3600);

        my $procs = new Proc::ProcessTable; 
        my %fields = map { $_ => 1 } $procs->fields;

        my $already_started; #kludge, id like to rework this later

        foreach my $proc ( @{$procs->table} )
        {
          if($proc->fname eq 'mysqld')
          {
            $kernel->yield('dispatcher' => 'SNAG::Source::mysql', {Alias => 'mysql'} );
            $shared_data->{tags}->{service}->{database}->{mysql} = 1;
          }

          if($proc->fname eq 'nrpe')
          {
            $shared_data->{tags}->{service}->{nagios}->{client} = 1;
          }
	 
          if($proc->fname eq 'stunnel')
          {
            $shared_data->{tags}->{service}->{stunnel} = 1;
          }

          if($proc->fname eq 'tornadod')
          {
            $shared_data->{tags}->{service}->{nntp}->{tornado} = 1;
          }

          if($proc->fname eq 'cycloned')
          {
            $shared_data->{tags}->{service}->{nntp}->{cyclone} = 1;
          }

          if($proc->fname eq 'nntpAdapter')
          {
            $shared_data->{tags}->{service}->{nntp}->{nntpAdapter} = 1;
          }

          if($proc->fname eq 'hw_stormcellard')
          {
            $shared_data->{tags}->{service}->{nntp}->{stormcellar} = 1;
          }
          if($proc->fname eq 'ntp')
          {
            $shared_data->{tags}->{service}->{ntp} = 1;
          }

          if($proc->fname eq 'oracle')
          {
            $shared_data->{tags}->{service}->{database}->{oracle} = 1;
          }

          if($proc->fname eq 'postmaster' && $proc->cmndline =~ /postgres/)
          {
            $shared_data->{tags}->{service}->{database}->{postgres} = 1;
          }

          if($proc->fname eq 'dataserver' && $proc->cmndline =~ /sybase/) 
          {
            $shared_data->{tags}->{service}->{database}->{sybase} = 1;
          }

          if($proc->fname eq 'db2sysc')
          {
            $shared_data->{tags}->{service}->{database}->{db2} = 1;
          }

          if($proc->fname eq 'java' && $proc->cmndline =~ /was/)
          {
            $shared_data->{tags}->{service}->{web}->{websphere} = 1;

            $kernel->yield('dispatcher' => 'SNAG::Source::websphere' );
          }

          if($proc->fname eq 'java' && $proc->cmndline =~ /tomcat/)
          {
            $shared_data->{tags}->{service}->{web}->{tomcat} = 1;

            $kernel->yield('dispatcher' => 'SNAG::Source::tomcat' );
          }

          if($proc->fname eq 'java' && $proc->cmndline =~ /EDNAServer/)
          {
            $shared_data->{tags}->{service}->{edna}->{server} = 1;

            $kernel->yield( 'dispatcher' => 'SNAG::Source::edna_server' );

            foreach my $file ('/usr/local/EDNA/logs/AuditLog')
            {
              if(-e $file)
              {
                $kernel->yield('dispatcher' => 'SNAG::Source::File::edna', { Alias => 'edna', Source => $file } );
              }
            }
          }

          if($proc->fname eq 'java' && $fields{cwd} && $proc->cwd =~ /jboss/)
          {
            $shared_data->{tags}->{service}->{web}->{jboss} = 1;
          }

          if($proc->fname eq 'java' && $fields{cwd} && $proc->cwd =~ /SaAppServController/)
          {
            $shared_data->{tags}->{service}->{web}->{sapphire} = 1;
          }

          if($proc->fname eq 'slapd')
          {
            $shared_data->{tags}->{service}->{ldap} = 1;
          }

          if($proc->fname eq 'named')
          {
            $shared_data->{tags}->{service}->{dns}->{named} = 1;
          }
          if($proc->fname eq 'dhcpd')
          {
            $shared_data->{tags}->{service}->{dhcp}->{dhcpd} = 1;
          }

          if($proc->fname eq 'syslog-ng')
          {
            $shared_data->{tags}->{service}->{syslog} = 1;
          }

          ###libhttpd.ep if from bb8 env
          if($proc->fname eq 'httpd' || $proc->fname eq 'masond' || $proc->fname eq 'apache' || $proc->fname eq 'apache2' || $proc->fname eq 'libhttpd.ep')
          {
             $shared_data->{tags}->{service}->{web}->{apache} = 1;
            #$kernel->yield('dispatcher' => 'SNAG::Source::apache_logs' );
          }

          if($proc->fname eq 'webservd' && $proc->cmndline =~ /iplanet/)
          {
            $shared_data->{tags}->{service}->{web}->{iplanet} = 1;
          }

          if($proc->fname eq 'httpd.worker' && ($proc->cmndline =~ m[/perfigo/control/] | $proc->cmndline =~ m[/perfigo/access/]))
          {
            if($proc->cmndline =~ m[/perfigo/control/])
            {
              $shared_data->{tags}->{service}->{perfigo}->{sm} = 1;

              $kernel->yield('dispatcher' => 'SNAG::Source::perfigo' );
            }
            else
            {
              $shared_data->{tags}->{service}->{perfigo}->{ss} = 1;
            }
          }

          #if($proc->fname eq 'vmware-serverd')
          #{
            #$shared_data->{tags}->{'system'}->{vmware}->{host} = 1;
          #}

          #if($proc->fname eq 'vmware-guestd')
          #{
            ## Also checked for in dmidecode results, see SNAG::Source::SystemInfo::Linux
          #  $shared_data->{tags}->{'virtual'}->{vmware}->{guest} = 1;
          #}

          if($proc->fname =~ /tac_plus/)
          {
            $shared_data->{tags}->{service}->{tacacs} = 1;
          }

          if($proc->fname eq 'radius')
          {
            $shared_data->{tags}->{service}->{radius} = 1;
          }

          if($proc->fname eq 'niddnsd')
          {
            $shared_data->{tags}->{service}->{dns}->{netid} = 1;
          }

          if($proc->fname eq 'niddhcpd')
          {
            $shared_data->{tags}->{service}->{dhcp}->{netid} = 1;

            foreach my $file ('/opt/netid4.3.2/log/niddhcp.log')
            {
              if(-e $file)
              {
                $kernel->yield('dispatcher' => 'SNAG::Source::File::dhcp', { Alias => 'dhcp', Source => $file } );
              }
            }
          }

          if($proc->fname eq 'nfsd' && !$shared_data->{tags}->{storage}->{nfs}->{server}) ### Keep it from running exportfs for every nfsd proc in the table
          {
            my $exports = `/usr/sbin/exportfs -v`;
            chomp $exports;

            if($exports)
            {
              $shared_data->{tags}->{storage}->{nfs}->{server} = 1;
            }
          }

          if($proc->cmndline =~ m#^/usr/afs/bin/fileserver\s*#)
          {
            $shared_data->{tags}->{storage}->{afs}->{fileserver} = 1;

            unless($already_started->{afs_server})
            {
              $kernel->yield('dispatcher' => 'SNAG::Source::afs_server' );
              $already_started->{afs_server} = 1;
            }
          }

          if($proc->cmndline =~ m#^/usr/afs/bin/bosserver\s*#)
          {
            $shared_data->{tags}->{storage}->{afs}->{bosserver} = 1;

            unless($already_started->{afs_server})
            {
              $kernel->yield('dispatcher' => 'SNAG::Source::afs_server' );
              $already_started->{afs_server} = 1;
            }
          }

          if($proc->cmndline =~ m#^/usr/afs/bin/kaserver\s*#)
          {
            $shared_data->{tags}->{storage}->{afs}->{kaserver} = 1;

            unless($already_started->{afs_server})
            {
              $kernel->yield('dispatcher' => 'SNAG::Source::afs_server' );
              $already_started->{afs_server} = 1;
            }
          }

          if($proc->cmndline =~ m#^/usr/afs/bin/ptserver\s*#)
          {
            $shared_data->{tags}->{storage}->{afs}->{ptserver} = 1;

            unless($already_started->{afs_server})
            {
              $kernel->yield('dispatcher' => 'SNAG::Source::afs_server' );
              $already_started->{afs_server} = 1;
            }
          }

          if($proc->cmndline =~ m#^/usr/afs/bin/buserver\s*#)
          {
            $shared_data->{tags}->{storage}->{afs}->{buserver} = 1;

            unless($already_started->{afs_server})
            {
              $kernel->yield('dispatcher' => 'SNAG::Source::afs_server' );
              $already_started->{afs_server} = 1;
            }
          }

          if($proc->cmndline =~ m#^/usr/afs/bin/vlserver\s*#)
          {
            $shared_data->{tags}->{storage}->{afs}->{vlserver} = 1;

            unless($already_started->{afs_server})
            {
              $kernel->yield('dispatcher' => 'SNAG::Source::afs_server' );
              $already_started->{afs_server} = 1;
            }
          }

          if($proc->cmndline =~ m#^/usr/afs/bin/volserver\s*#)
          {
            $shared_data->{tags}->{storage}->{afs}->{volserver} = 1;

            unless($already_started->{afs_server})
            {
              $kernel->yield('dispatcher' => 'SNAG::Source::afs_server' );
              $already_started->{afs_server} = 1;
            }
          }

          if($proc->fname eq 'iscsid')
          {
            $shared_data->{tags}->{storage}->{iscsi}->{client} = 1;
          }

          if($proc->fname eq 'dsmserv')
          {
            $shared_data->{tags}->{storage}->{tsm}->{server} = 1;
          }

          if($proc->fname eq 'authd')
          {
            $shared_data->{tags}->{service}->{webauth} = 1;

            foreach my $file ('/usr/local/webauth/etc/authlog')
            {
              if(-e $file)
              {
                $kernel->yield('dispatcher' => 'SNAG::Source::File::authd', { Alias => 'authd', Source => $file } );
              }
            }

            foreach my $file ('/usr/local/webauth/etc/verifylog')
            {
              if(-e $file)
              {
                $kernel->yield('dispatcher' => 'SNAG::Source::File::verifyd', { Alias => 'verifyd', Source => $file } );
              }
            }
          }

          if($proc->fname eq 'verifyd')
          {
            $shared_data->{tags}->{service}->{webauth} = 1;
          }

          if($proc->fname eq 'krb5kdc')
          {
            $shared_data->{tags}->{service}->{kerberos} = 1;

            foreach my $file ('/usr/local/var/krb5kdc/krb5kdc.log')
            {
              if(-e $file)
              {
                $kernel->yield('dispatcher' => 'SNAG::Source::File::krb', { Alias => 'krb', Source => $file } );
              }
            }
          }

          if($proc->fname eq 'kaserver')
          {
            $shared_data->{tags}->{service}->{klog} = 1;

            foreach my $file ('/usr/afs/logs/AuthLog')
            {
              if(-e $file)
              {
                $kernel->yield('dispatcher' => 'SNAG::Source::File::klog', { Alias => 'klog', Source => $file } );
              }
            }
          }

          ### PHP?  MASON?  mod_perl?
        }
      },

      check_open_files => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->delay($_[STATE] => 3600);

        #my $open_files;

        #open LSOF, 'lsof |';
        #my @keys = split /\s+/, <LSOF>; 

        #while(<LSOF>)
        #{
          #my @values = split /\s+/, <LSOF>;
#
          #my $line;
          #@$line{@keys} = @values;
          #push @$open_files, $line;
        #}
      },

      check_win_services => sub
      {
        my ($kernel, $heap) = @_[KERNEL, HEAP];
        $kernel->delay($_[STATE] => 3600);

        my $services = {};
        Win32::Service::GetServices('', $services);

        foreach my $service (sort keys %$services)
        {
          if($service =~ /MSSQLSERVER/)
          {
            $shared_data->{tags}->{service}->{database}->{mssql} = 1;
          }

          if($service =~ /IIS Admin Service/)
          {
            $shared_data->{tags}->{service}->{web}->{iis} = 1;
          }

          if($service =~ /Microsoft Exchange Management/)
          {
            $shared_data->{tags}->{service}->{exchange} = 1;
          }

          if($service =~ /Citrix/)
          {
            $shared_data->{tags}->{service}->{citrix} = 1;
          }

          if($service =~ /OpenAFS Client Service/)
          {
            $shared_data->{tags}->{storage}->{afs}->{client} = 1;
          }

          if($service =~ /NetApp/)
          {
            $shared_data->{tags}->{storage}->{iscsi}->{client} = 1;
          }
          #print "$service => $services->{$service}\n"; 
        }
      },
    }
  );
}

1;
