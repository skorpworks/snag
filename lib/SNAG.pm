package SNAG;

our @ISA = qw(Exporter);

our @EXPORT = qw( VERSION PARCEL_SEP REC_SEP LOG_DIR LINE_SEP RRD_SEP INFO_SEP SCRIPT_NAME CHECK_HOST_NAME HOST_NAME BASE_DIR CFG_DIR STATE_DIR MOD_DIR OS OSDIST OSVER OSLONG SITE_PERL logger daemonize already_running TMP_DIR SMTP SENDTO CONF CLIENT_CONF SET_HOST_NAME SET_UUID UUID);

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

our $VERSION = '4.25';
sub VERSION { $VERSION };

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
    my $filler;
    if(($dist, $filler, $ver) = ($release =~ /^(\w+) Base System (version|release) ([\.\d]+)/))
    {
      $ver =~ s/\./-/g;
    }    
  }
  elsif(-e '/etc/lsb-release')
  {
    {
      local $/;

      open FILE, '/etc/lsb-release';
      $release = <FILE>;
      close FILE;
    }
    #DISTRIB_ID=Ubuntu
    #DISTRIB_RELEASE=10.04
    #DISTRIB_CODENAME=lucid
    #DISTRIB_DESCRIPTION="Ubuntu 10.04.1 LTS"
    ($dist) = ($release =~ m/DISTRIB_ID=(?=(.*))\b/);
    ($ver)  = ($release =~ m/DISTRIB_RELEASE=(?=(.*))\b/);
    ($long) = ($release =~ m/DISTRIB_DESCRIPTION=\"(.*)\"/);
    $ver =~ s/\./-/g;
  }

  elsif(-e '/etc/issue')
  {
    {
      local $/;

      open FILE, "/etc/issue";
      $release = <FILE>;
      close FILE;
    }

    $long = $release;
    $dist = 'na';
    $ver = '00';
    chomp $long;

    #
    #Ubuntu 10.04.1 LTS
    if($release =~ /Ubuntu ([\.\d]+)/)
    {
      #($ver = $1) =~ s/\.//g;
      $dist = "Ubuntu";
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

# Try and guess where our conf file is
my @path = qw(/opt/snag /etc/ ./..);
my $conf;
eval
{
  %$conf = ParseConfig(-ConfigFile => "snag.conf", -ConfigPath => \@path);
};
if($@ && $opt{debug})
{
  print "snag.conf not found!  This will result in many constants not working.\n";
}

sub CONF { $conf };

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
my $uuid = 0;

sub HOST_NAME { $host_name };
sub CLIENT_CONF { return $conf->{directory}->{log_dir} . '/client.conf'; };

sub SET_HOST_NAME
{
  my $new = shift || $host_name;
  $host_name = $new;
}

sub SET_UUID
{
  my $u = shift || 0;
  $uuid = $u; 
}

sub UUID { return $uuid };
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

    my $full_script = "^($^X |perl |.{0,0})$0";

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
              Program => sub { sendmail(%mail) or die $Mail::Sendmail::error; },
              StdioFilter  => POE::Filter::Line->new(),
              StderrFilter => POE::Filter::Line->new(),
              StdoutEvent  => 'alert_stdio',
              StderrEvent  => 'alert_stderr',
              CloseEvent   => "alert_close",
              CloseOnCall  => 1,
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

1;
__END__

=head1 NAME

SNAG - [One line description of module's purpose here]


=head1 VERSION

This document describes SNAG version 0.0.1


=head1 SYNOPSIS

    use SNAG;

=for author to fill in:
    Brief code example(s) here showing commonest usage(s).
    This section will be as far as many users bother reading
    so make it as educational and exeplary as possible.
  
  
=head1 DESCRIPTION

=for author to fill in:
    Write a full description of the module and its features here.
    Use subsections (=head2, =head3) as appropriate.


=head1 INTERFACE 

=for author to fill in:
    Write a separate section listing the public components of the modules
    interface. These normally consist of either subroutines that may be
    exported, or methods that may be called on objects belonging to the
    classes provided by the module.


=head1 DIAGNOSTICS

=for author to fill in:
    List every single error and warning message that the module can
    generate (even the ones that will "never happen"), with a full
    explanation of each problem, one or more likely causes, and any
    suggested remedies.

=over

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=item C<< Another error message here >>

[Description of error here]

[Et cetera, et cetera]

=back


=head1 CONFIGURATION AND ENVIRONMENT

=for author to fill in:
    A full explanation of any configuration system(s) used by the
    module, including the names and locations of any configuration
    files, and the meaning of any environment variables or properties
    that can be set. These descriptions must also include details of any
    configuration language used.
  
SNAG requires no configuration files or environment variables.


=head1 DEPENDENCIES

=for author to fill in:
    A list of all the other modules that this module relies upon,
    including any restrictions on versions, and an indication whether
    the module is part of the standard Perl distribution, part of the
    module's distribution, or must be installed separately. ]

None.


=head1 INCOMPATIBILITIES

=for author to fill in:
    A list of any modules that this module cannot be used in conjunction
    with. This may be due to name conflicts in the interface, or
    competition for system or program resources, or due to internal
    limitations of Perl (for example, many modules that use source code
    filters are mutually incompatible).

None reported.


=head1 BUGS AND LIMITATIONS

=for author to fill in:
    A list of known problems with the module, together with some
    indication Whether they are likely to be fixed in an upcoming
    release. Also a list of restrictions on the features the module
    does provide: data types that cannot be handled, performance issues
    and the circumstances in which they may arise, practical
    limitations on the size of data sets, special cases that are not
    (yet) handled, etc.

No bugs have been reported.

Please report any bugs or feature requests to
C<bug-snag@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.


=head1 AUTHOR

Skorpworks  C<< <skorpworks@gmail.com> >>


=head1 LICENCE AND COPYRIGHT

Copyright (c) 2010, Skorpworks C<< <skorpworks@gmail.com> >>. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.


=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
SUCH DAMAGES.
