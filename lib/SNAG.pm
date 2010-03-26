package SNAG;

our @ISA = qw(Exporter);

our @EXPORT = qw( VERSION PARCEL_SEP REC_SEP LOG_DIR LINE_SEP RRD_SEP INFO_SEP SCRIPT_NAME CHECK_HOST_NAME HOST_NAME BASE_DIR CFG_DIR STATE_DIR MOD_DIR OS OSDIST OSVER OSLONG SITE_PERL logger daemonize already_running TMP_DIR SMTP SENDTO);

use Exporter;

use File::Basename;
use Sys::Hostname;
use Getopt::Long;
use POE;
use FileHandle;
use Date::Format;
use Mail::Sendmail;
use File::Spec::Functions qw/rootdir catpath catfile devnull catdir/;
use Config::General qw/ParseConfig/;

our %flags;

our $VERSION = '4.2';
sub VERSION { $VERSION };

my $conf = (ParseConfig(-ConfigFile => "snag.conf")); 

my ($os, $dist, $ver);
if($^O =~ /linux/i)
{
  $os = "Linux";

  my $release;
  if(-e '/etc/redhat-release')
  {
    {
      local $/;

      open FILE, "/etc/redhat-release";
      $release = <FILE>;
      close FILE;
    }

    $long = $release;
    chomp $long;

    ###Red Hat Enterprise Linux AS release 3 (Taroon Update 5)
    ###Red Hat Enterprise Linux AS release 4 (Nahant Update 1)
    ###Red Hat Enterprise Linux WS release 3 (Taroon Update 5)
    if($release =~ /Red Hat Enterprise Linux \w+ release ([\.\d]+)/)
    {
      ($ver = $1) =~ s/\.//g;
      $dist = 'RHEL';
    }
    ###Red Hat Linux release 7.2 (Enigma)
    elsif($release =~  /Red Hat Linux release ([\d\.]+)/)
    {
      ($ver = $1) =~ s/\.//g;
      $dist = 'RH';
    }
    #Fedora Core release 4 (Stentz)
    elsif($release =~ /Fedora Core release (\d+)/)
    {
      $ver = $1;
      $dist = 'FC';
    }
    elsif($release =~ /Cisco Clean Access /)
    {
      $dist = 'CCA';
    }
    #XenServer release 3.2.0-2004d (xenenterprise)
    elsif($release  =~ /XenServer release (\d+)/)
    {
      #$ver = $1;
      $dist = 'XenSource';
    }
  }
  elsif(-e '/etc/gentoo-release')
  {
    {
      local $/;

      open FILE, "/etc/gentoo-release";
      $release = <FILE>;
      close FILE;
    }

    $long = $release;
    chomp $long;

    #Gentoo Base System version 1.6.13
    #Gentoo Base System release 1.12.9
    if($release =~ /Gentoo Base System (version|release) ([\.\d]+)/)
    {
      #($ver = $2) =~ s/\.//g;
      $dist = "GENTOO";
    }    
  }
  elsif(-e '/etc/cp-release')
  {
    {
      local $/;

      open FILE, "/etc/cp-release";
      $release = <FILE>;
      close FILE;
    }

    $long = $release;
    chomp $long;

    #Check Point SecurePlatform NGX (R62)
    if($release =~ /Check Point SecurePlatform NGX \((\w+)\)/)
    {
      ($ver = $1) =~ s/\.//g;
      $dist = "CP";
    }
  }
  elsif(-e '/proc/vmware/version')
  {
    $long = `vmware -v`;
    chomp $long;
    if($long =~ /VMware ESX Server (.+?)/)
    {
      $dist = 'VMwareESX';
      #$ver = $1;
    }
  }
}
elsif($^O =~ /solaris/i || $^O =~ /SunOS/i)
{
  $os = $dist = "SunOS";

  my $release = `uname -a`;
  chomp $release;

  #SunOS dhcp2 5.8 Generic_108528-15 sun4u sparc SUNW,UltraAX-i2
  if($release =~ /SunOS [\w\.\-]+ ([\d\.]+)/)
  {
    $long = "SunOS $1";
    ($ver = $1) =~ s/\.//g;
  }
}
elsif($^O =~ /MSWin32/i)
{
  $os = "Windows";

  my $get_dist =
  {
    '4' =>
    {
      '0' => 'NT4',
    },
    '5' =>
    {
      '0' => '2K',
      '1' => 'XP',
      '2' => 'Server2003',
    },
    '6' =>
    {
      '0' => 'Vista',
    },
  };

  require Win32;

  my ($string, $major, $minor, $build, $id) = Win32::GetOSVersion();
  $dist = $get_dist->{ $major }->{ $minor } || $os;

  #$ver = $build;
}
else
{
  $os = $^O;
}

sub OS { $os };
sub OSDIST { $dist };
sub OSVER { $ver };
sub OSLONG { $long };

sub CHECK_HOST_NAME
{
  if(OS eq 'Windows')
  {
    require Win32::OLE;
    import Win32::OLE qw/in/;
  
    my $wmi = Win32::OLE->GetObject("winMgmts:{(Security)}!//");
  
    my $get_computer_system = $wmi->ExecQuery('select * from Win32_ComputerSystem');
    foreach my $ref ( in $get_computer_system )
    {
      $host = $ref->{Name} . '.' . $ref->{Domain};
    }
  }
  else
  {
    eval
    {
      require Sys::Hostname::FQDN;
      import  Sys::Hostname::FQDN qw(fqdn);
      $host = fqdn() or die "Fatal: Could not get host name!";
    };
    if($@)
    {
      #print "Sys::Hostname::FQDN not found, defaulting to Sys::Hostname\n";
      $host = hostname or die "Fatal: Could not get host name!";
    }
  }
 
  if(defined $conf->{network}->{domain})
  {
    $host =~ s/\.$conf->{network}->{domain}//gi;
  }
  $host = lc($host);

  $host_name = $host;

  return $host;
}

my $host_name = CHECK_HOST_NAME;

sub HOST_NAME { $host_name };

my $name = basename $0;
sub SCRIPT_NAME { $name };


sub REC_SEP { '~_~' };
sub RRD_SEP { ':' };
sub LINE_SEP { '_@%_' };
sub PARCEL_SEP { '@%~%@' };
sub INFO_SEP { ':%:' };

sub SMTP { $conf->{message}->{smtp} };
sub SENDTO { $conf->{message}->{email} };

sub BASE_DIR 
{ 
  return $conf->{directory}->{base_dir};
};

sub LOG_DIR  
{ 
  return $conf->{directory}->{log_dir};
};

sub TMP_DIR  
{ 
  return $conf->{directory}->{tmp_dir};
};

sub STATE_DIR  
{ 
  return $conf->{directory}->{state_dir};
};

sub CFG_DIR  
{ 
  return $conf->{directory}->{conf_dir};
};

sub daemonize
{
  if(OS eq 'Windows')
  {
    ## Can't do service stuff here because Win32::Daemon can't be required in at runtime, something is missed and it never responds to the SCM 
  }
  else
  {
    umask(0);

    chdir '/' or die $!;

    open(STDIN,  "+>" . File::Spec->devnull());
    open(STDOUT, "+>&STDIN");
    open(STDERR, "+>&STDIN");
  
    foreach my $sig ($SIG{TSTP}, $SIG{TTIN}, $SIG{TTOU}, $SIG{HUP}, $SIG{PIPE})
    {
      $sig = 'IGNORE';
    }
  
    my $pid = &safe_fork;
    exit if $pid;
    die("Daemonization failed!") unless defined $pid;
  
    POSIX::setsid() or die "SERVER:  Can't start a new session: $!";
  }
}

sub safe_fork
{
  my $pid;
  my $retry = 0;

  FORK:
  {
    if(defined($pid=fork))
    {
      return $pid;
    }
    elsif($!=~/No more process/i)
    {
      if(++$retry>(3))
      {
        die "Cannot fork process, retry count exceeded: $!";
      }

      sleep (5);
      redo FORK;
    }
    else
    {
      die "Cannot fork process: $!";
    }
  }
}

sub already_running
{
  if(OS eq 'Windows')
  {
  #  print "RUNNING already_running!\n";
  #  require Win32::Process::Info;

  #  my $script_name = SCRIPT_NAME;

  #  return grep { $_->{CommandLine} =~ /perl.+$script_name/ && $_->{ProcessId} != $$ } @{Win32::Process::Info->new()->GetProcInfo()};
  }
  else
  {
    require Proc::ProcessTable;

    my $full_script = "$^X $0";

    #return grep { $_->fname eq SCRIPT_NAME && $_->pid != $$ } @{(new Proc::ProcessTable)->table};
    return grep { $_->cmndline =~ /^$full_script/ && $_->pid != $$ } @{(new Proc::ProcessTable)->table};
  }
}

sub logger
{
  ###########################
  ## SET UP LOGGER
  ###########################
  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
	my ($kernel, $heap) = @_[KERNEL, HEAP];

	$kernel->alias_set('logger');

	$SIG{__WARN__} = sub
	{
	  $kernel->call('logger' => 'log' => "SNAG warning: @_");
	};
      },

      log => sub
      {
        my ($kernel, $heap, $msg) = @_[ KERNEL, HEAP, ARG0 ];

        my ($fh, $logfile, $logdate, $time);

        $time = time();

        $logdate = time2str("%w", $time);

        if ($heap->{logdate} ne $logdate)
        {
          if (defined $heap->{'log'})
          {
            $heap->{'log'}->close();
            delete $heap->{'log'};
          }
        }

        unless($fh = $heap->{'log'})
        {
          ### Needs to be a 2 liner because as a windows service, SCRIPT_NAME only returns 'SNAG'
          (my $logname = SCRIPT_NAME) =~ s/\.\w+$//;
          $logname .= '.log';

          $logfile = catfile(LOG_DIR, "$logname.$logdate");

          if ($heap->{logdate} ne $logdate)
          {
            # Check if logfile was modified in the last day, so we can append rather than overwrite
            if(time() - (stat($logfile))[9] < 3600)
            {
              $fh = new FileHandle ">> $logfile" or die "Could not open log $logfile";
            }
            else
            {
              $fh = new FileHandle "> $logfile" or die "Could not open log $logfile"
            }
          }
          else
          {
            $fh = new FileHandle ">> $logfile" or die "Could not open log $logfile";
          }

          $fh->autoflush(1);

          $heap->{logdate} = $logdate;

          $heap->{'log'} = $fh;
        }

        chomp $msg;
        my $now = time2str("%Y-%m-%d %T", $time);
        print $fh "[$now] $msg\n";
        print "[$now] $msg\n" if $flags{debug};
      },

      alert => sub
      {
        my ($kernel, $heap, $args) = @_[ KERNEL, HEAP, ARG0 ];

        my %defaults = 
        (
         smtp    => SMTP,
         To      => SENDTO,
         From    => SENDTO,
         Subject => "SNAG alert from " . HOST_NAME . "!",
         Message => "Default message",
        );

        my %mail = (%defaults, %$args);

        if(OS eq 'Windows')
	      {
	        eval
	        {
	          sendmail(%mail) or die $Mail::Sendmail::error; 
	        };
	        if($@)
	        {
            $kernel->yield('log' => "Could not send alert because of an error.  Error: $@, Subject: $mail{Subject}, Message: $mail{Message}");
	        }
	      }
	      else
	      {
          require POE::Wheel::Run;

          unless($heap->{alert_wheel})
          {
            $heap->{mail_args} = \%mail;

	          $heap->{alert_wheel} = POE::Wheel::Run->new
            (
              Program => sub
              {
                sendmail(%mail) or die $Mail::Sendmail::error; 
              },
              StdioFilter  => POE::Filter::Line->new(),
              StderrFilter => POE::Filter::Line->new(),
              Conduit      => 'pipe',
              StdoutEvent  => 'alert_stdio',
              StderrEvent  => 'alert_stderr',
              CloseEvent   => "alert_close",
            );
          }
          else
          { 
            $kernel->yield('log' => "Could not send alert because an alert wheel is already running.  Subject: $mail{Subject}, Message: $mail{Message}");
          }
        }
      },
    
      alert_stdio => sub
      {
      },
    
      alert_stderr => sub
      {
	      my ($kernel, $heap, $error) = @_[ KERNEL, HEAP, ARG0 ];
        $kernel->yield('log' => "Could not send alert because of an error.  Error: $error, Subject: $heap->{mail_args}->{Subject}, Message: $heap->{mail_args}->{Message}");
      },

      alert_close => sub
      {
	      my ($kernel, $heap) = @_[ KERNEL, HEAP ];
        delete $heap->{alert_wheel};
      },
    }
  );
}

my $dns;
sub dns
{
  require Net::Nslookup;

  ### Only run this session of the dns sub is used
  ###  This session should only be created once; since it sets $dns to an empty hash it will pass the following test every time after the first time
  unless(ref $dns)
  {
    POE::Session->create
    (
      inline_states =>
      {
        _start => sub
        {
          my ($kernel, $heap) = @_[KERNEL, HEAP];
          $kernel->yield('clear');
        },

        clear => sub
        {
          my ($kernel, $heap) = @_[KERNEL, HEAP];
          ## Clear $dns every 6 hours

          $dns = {};

          $kernel->delay('clear' => 21600);
        },
      }
    );
  }

  my $arg = shift;

  if($arg =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/)
  {
    ### It's an IP, return a hostname
    return $dns->{ip}->{$arg} ||= (Net::Nslookup::nslookup(host => $arg, type => 'PTR') || $arg);
  }
  else
  {
    ### It's a hostname, return an IP
    return $dns->{hostname}->{$arg} ||= (Net::Nslookup::nslookup(host => $arg, type => 'A') || $arg);
  }
}


1
