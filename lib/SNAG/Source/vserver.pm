package SNAG::Source::vserver;
use base qw/SNAG::Source/;

use strict;
use warnings;

use SNAG;
use POE;
use POE::Quickie;
use Storable qw/dclone store retrieve/;
use FreezeThaw qw/freeze thaw/;
use Date::Format;
use URI::Escape;

#################################
sub new
#################################
{
  my $package = shift;
  $package->SUPER::new(@_);

  POE::Session->create(
    inline_states => {
      _start => sub
      {
        my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
	$heap->{'vserver-stat'} = 0;
	$heap->{'vserver-info'} = {};

        $kernel->delay( 'vserver_stat' => 5 );
        $kernel->delay( 'vserver_info' => 10 );
      },

#hipsdns02 / # cat  /proc/self/vinfo
#XID:   157
#BCaps: 00000000344c05ff
#CCaps: 0000000000000101
#CFlags: 0000001402020010
#CIPid: 21246
#hipsdns02 / # cat  /proc/self/ninfo
#NID:   157
#NCaps: 0000000000000100
#NFlags: 0000000402000000
#V4Root[0]:  69.16.185.112/255.255.255.0
#V4Root[bcast]:  0.0.0.0
#vserver06 ~ # cat /proc/virtual/157/info
#ID: 157
#Info:  ffff81013d1db000
#Init:  21246
#
#verver06 ~ # vserver-ips
#127.0.0.1 0 filter02.iad
#69.16.185.72  1 filter02.iad
#69.16.185.112 0 hipsdns02.iad
#69.16.185.45  0 stormshutter01.iad
#69.16.185.58  0 tmp-post02.iad
#
#cat /proc/self/*info
#cat: /proc/self/fdinfo: Is a directory
#75 55 9:3 /search-slave-a / rw,relatime shared:1 - ext3 /dev/md3 rw,errors=continue,user_xattr,acl,barrier=1,data=writeback
#76 75 0:3 / /proc rw,nodev,relatime shared:2 - proc none rw
#77 75 0:10 / /dev/pts rw,relatime shared:3 - devpts none rw,gid=5,mode=620
#78 75 8:33 / /var/solr rw,nodev,noatime shared:4 - ext4 /dev/sdc1 rw,discard,data=ordered
#79 75 9:0 /usr/portage /usr/portage ro,nodev,relatime shared:5 - ext3 /dev/root rw,errors=continue,user_xattr,acl,barrier=1,data=writeback
#80 79 9:0 /usr/portage/distfiles /usr/portage/distfiles rw,nodev,relatime shared:6 - ext3 /dev/root rw,errors=continue,user_xattr,acl,barrier=1,data=writeback
#NID:    211
#NCaps:  0000000000000100
#NFlags: 0000000406000200
#V4Root[bcast]:  255.255.255.255
#V4Root[lback]:  127.0.211.1
#V4Root[0]:      [192.168.25.211-0.0.0.0/255.255.248.0:0010]
#V4Root[1]:      [192.168.25.3-0.0.0.0/255.255.255.255:0010]
#XID:    211
#BCaps:  ffffffffb44c04ff
#CCaps:  0000000000004101
#CFlags: 0000001402020010
#CIPid:  3234


      vserver_stat => sub
      {
        my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];

        local $/ = "\n";

	if ($heap->{'vserver-stat'} == 1)
	{
          #logger
	  $kernel->call('logger' => "log" =>  "SNAG::Source::vserver: vserver_stat still running, skipping");

	}
        elsif ( -e $SNAG::Dispatch::shared_data->{binaries}->{"vserver-stat"} )
        {
	  $kernel->call('logger' => "log" =>  "SNAG::Source::vserver: vserver_stat starting") if $SNAG::flags{debug};

	  quickie_run ( Context => 'vserver-stat',
	                Program => $SNAG::Dispatch::shared_data->{binaries}->{"vserver-stat"},
			ResultEvent => 'vstat_result',
			);
          $heap->{'vserver-stat'} = 1;
	}
			
        $kernel->delay( $_[STATE] => 60 );
      },

      vstat_result => sub
      {
        my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
        my ($pid, $stdout, $stderr, $merged, $status, $context) = @_[ARG0..$#_];
        $heap->{'vserver-stat'} = 0;
	delete $SNAG::Dispatch::shared_data->{vservers};
      
        foreach my $entry (@{$stdout})
        {
          my @stats = split( /[' ']+/, $entry );
          next if $stats[7] =~ /^(root|NAME)/;
          $kernel->post( 'client' => 'sysrrd' => 'load' => join RRD_SEP, ( HOST_NAME, 'processes_' . $stats[7], "1g", time(), $stats[1] ) );
          $kernel->post( 'client' => 'master' => 'heartbeat' => { source => SCRIPT_NAME, host => $stats[7], seen => time2str( "%Y-%m-%d %T", time ) } );
          $SNAG::Dispatch::shared_data->{vservers}->{$stats[7]} = 1;
        } ## end foreach (`/usr/sbin/vserver-stat`...)
	$kernel->call('logger' => "log" =>  "SNAG::Source::vserver: vserver_stat complete") if $SNAG::flags{debug};

      },


      vserver_info => sub
      {
        my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];

	if (scalar keys %{$heap->{'vserver-info'}} > 0)
	{
	  $kernel->call('logger' => "log" =>  "SNAG::Source::vserver: vserver_info [" . join(',', keys %{$heap->{'vserver-info'}}) ."] still running, skipping");
          #logger
	}
        elsif ( -e $SNAG::Dispatch::shared_data->{binaries}->{vserver} )
        {
	  $kernel->call('logger' => "log" =>  "SNAG::Source::vserver: vserver_info starting") if $SNAG::flags{debug};
          foreach my $vs ( sort keys %{ $SNAG::Dispatch::shared_data->{vservers} } )
          {
	    quickie_run ( Context => "$vs",
	                  Program => "$SNAG::Dispatch::shared_data->{binaries}->{vserver} $vs exec ifconfig -a",
			  ResultEvent => 'vinfo_result',
	          	);
            $heap->{'vserver-info'}->{$vs} = 1;
	  }
	  $kernel->call('logger' => "log" =>  "SNAG::Source::vserver: vserver_info [" . join(',', keys %{$heap->{'vserver-info'}}) ."] started") if $SNAG::flags{debug};
	}
			
        $kernel->delay( $_[STATE] => 3600 );
      },

      vinfo_result => sub
      {
        my ( $kernel, $heap ) = @_[ KERNEL, HEAP ];
        my ($pid, $stdout, $stderr, $merged, $status, $context) = @_[ARG0..$#_];
        delete $heap->{'vserver-info'}->{$context};

        foreach my $entry (@{$stdout})
        {
          my $name;
          if ($entry =~ m/^([\w:]+)\s+/)
          {
            $name = $1;
          }
          next unless defined $name && $name =~ /.*0$/;    # we want en0 or eth0 or whatever our primary is

          if ($entry =~ m/inet addr:\s+([\d.]+)/)
          {
            $SNAG::Dispatch::shared_data->{vs}->{$context}->{ip} = $1;
          }
        } 
	$kernel->call('logger' => "log" =>  "SNAG::Source::vserver: vserver_info complete") if $SNAG::flags{debug} && scalar keys %{$heap->{'vserver-info'}} == 0;
      },
    },
  );
} ## end sub new


1;

