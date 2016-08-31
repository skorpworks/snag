package SNAG::Source::xen;
use base qw/SNAG::Source/;

use strict;
use warnings;

use SNAG;
use POE;
use Storable qw/dclone store retrieve/;
use FreezeThaw	qw/freeze thaw/;
use Date::Format;
use URI::Escape;

my $shared_data = $SNAG::Dispatch::shared_data;

#################################
sub new
#################################
{
	my $package = shift;
	$package->SUPER::new(@_);

	POE::Session->create
	(
		inline_states =>
		{
			_start => sub
			{
				my ($kernel, $heap) = @_[KERNEL, HEAP];

				$kernel->sig( CHLD => 'catch_sigchld' );

				$kernel->delay('xen_host' => 5);
				$kernel->delay('bridge_poll' => 10);
			},

			xen_host => sub
			{
				my ($kernel, $heap) = @_[KERNEL, HEAP];

				local $/ = "\n";

				my ($info, $xen_dom0);

				if( $shared_data->{binaries}->{xl} )
				{
					if( -e $shared_data->{binaries}->{xl} )
					{
# syd-12283e ~ # xl list -v
# Name                                        ID   Mem VCPUs      State   Time(s)   UUID                            Reason-Code   Security Label
# Domain-0                                     0   512    12     r-----  9268651.1 00000000-0000-0000-0000-000000000000        -                -
# ns1-syd.netprotect.com                       1  8192     6     -b----  667659.3 517a36ea-8b5f-4084-945c-20d08ca24d00        -                -
# syd-a03.ipvanish.com                         3  6144     4     r-----  18631439.3 e6227342-0f9c-4100-b1ba-ce95cef4532f        -                -
# syd-a06.ipvanish.com                         8  6144     4     r-----  4725531.9 3da732a1-b3d8-4cad-8a82-eac9bd576421        -                -
# rmt01                                       10   256     1     -b----   13085.8 6df6d187-8b0d-4a60-8c56-56ef8d3af9cd        -                -

						open my $cmd, $shared_data->{binaries}->{xl} . ' list -v |';
						while( my $line = <$cmd> )
						{
							chomp $line;

							my @fields = split /\s+/, $line;

							next if $fields[0] eq 'Name';
							next if $fields[1]  == 0;

							push @$xen_dom0, { uuid => $fields[6], domid => $fields[1], name => $fields[0] };
						}
						close $cmd;
					}
				}
				elsif(-e '/usr/sbin/xm')
				{
					#(domain
					#			 (domid 0)
					#			 (uuid 00000000-0000-0000-0000-000000000000)
					#			 (ssidref 0)
					#			 (vcpus 4)
					#			 (cpu_weight 1.0)
					#			 (memory 11678)
					#			 (maxmem 15595)
					#			 (name Domain-0)
					my $vals;
					foreach my $line (`/usr/sbin/xm list --long`)
					{
						chomp $line;
		
						if($line =~ /^\(domain\s*$/)
						{
							undef $vals;
						}
						elsif($line =~ /^\)\s*$/)
						{
							### Ignore dom0 itself
							unless($vals->{domid} eq '0')
							{
								push @$xen_dom0, { uuid => $vals->{uuid}, domid => $vals->{domid}, name => $vals->{name} };
							}
		
							undef $vals;
						}
						elsif($line =~ /^\s*\(domid (\w+)\)\s*$/)
						{
							$vals->{domid} = $1;
						}
						elsif($line =~ /^\s*\(uuid ([\w\-]+)\)\s*$/)
						{
							$vals->{uuid} = $1 unless $vals->{uuid};
						}
						elsif($line =~ /^\s*\(name ([^)]+)\)\s*$/)
						{
							$vals->{name} = $1;
						}
					}
				}
				elsif(-e '/usr/bin/xe')
				{
					#[root@xen4test ~]# xe vm-list
					#uuid ( RO)					 : c4da921f-5042-2356-ae29-2fe63c372a6d
					#		 name-label ( RW): RHEL51-64-GOLD
					#		power-state ( RO): running
					
					
					#uuid ( RO)					 : b5cb213a-0dca-4057-8385-863956236ef7
					#		 name-label ( RW): Control domain on host: xen4test
					#		power-state ( RO): running
					#
					#
					#uuid ( RO)					 : 3082ee91-ff83-7981-6f97-751b081751f7
					#		 name-label ( RW): RHEL46-64-GOLD
					#		power-state ( RO): running
	
					my ($uuid, $args);
					if (-r '/etc/xensource-inventory')
					{
						open my $xe, '<', "</etc/xensource-inventory";
						while(<$xe>)
						{
							chomp;
							s/\'//g;
							my ($key,$val) = split /=/;
							$info->{xen_inventory}->{product_version} = $val if $key =~ m/PRODUCT_VERSION/i;
							$info->{xen_inventory}->{xen_build} = $val if $key =~ m/BUILD_NUMBER/i;
							$info->{xen_inventory}->{xen_version} = $val if $key =~ m/XEN_VERSION/i;
							$info->{xen_inventory}->{installed} = $val if $key =~ m/INSTALLATION_DATE/i;
		
							if ($key =~ m/INSTALLATION_UUID/i)
							{
								$info->{xen_inventory}->{uuid} = $val;
								$uuid = $val if $key =~ m/INSTALLATION_UUID/i;
								$args = "resident-on=$val";
							}
						}
						close $xe;
					}

					foreach (`xe pool-list params=all`)
					{
						#uuid ( RO)									: 34995180-d80f-ad80-d15b-b8fd8c4f5e35
											#name-label ( RW): PROD-POOL2
								#name-description ( RW): Production Pool #2 in ISTB1 Rack 8
													#master ( RO): 0c464ff6-c623-4ec3-bb34-bf9b5455e7ef
											#default-SR ( RW): 098c81c0-66cd-0a8a-1f3c-7626ee34f999
									 #crash-dump-SR ( RW): 098c81c0-66cd-0a8a-1f3c-7626ee34f999
								#suspend-image-SR ( RW): 098c81c0-66cd-0a8a-1f3c-7626ee34f999
							#supported-sr-types ( RO): <expensive field>
										#other-config (MRW):
						chomp;
						$info->{xen_pool}->{name} = $1 if (m/^\s*name-label .*?:\s+(.*)/);
						$info->{xen_pool}->{description} = $1 if (m/^\s*name-description.*?:\s+(.*)/);
						$info->{xen_pool}->{master_uuid} = $1 if (m/^\s*master.*?:\s+(.*)/);
						$info->{xen_pool}->{member_uuid} = $uuid;
					}

					if(my $cluster = $info->{xen_pool}->{name})
					{
						$kernel->post('client' => 'master' => 'heartbeat' => { source	=> SCRIPT_NAME, host => $cluster , seen => time2str("%Y-%m-%d %T", time) } );
						#$kernel->post('sysinfo' => 'function' => { function => 'heartbeat', queue_mode => 'replace', host => $cluster, seen => time2str("%Y-%m-%d %T", time) } );
					}

					if (defined $info->{xen_pool}->{master_uuid})
					{
						foreach (`xe host-list uuid=$info->{xen_pool}->{master_uuid}`)
						{
							$info->{xen_pool}->{master_name} = $1 if (m/^\s*name-label .*?:\s+(.*)/);
						}
					}
					$info->{xen_pool}->{master_name} = 'undefined' unless defined $info->{xen_pool}->{master_name};
					$info->{xen_pool}->{name} = uc($info->{xen_pool}->{master_name}) . '-SOLO' unless $info->{xen_pool}->{name} ne '';

					foreach my $line (`xe pif-list params=all host-uuid=$uuid`)
					{
						($_) = ($line =~ m/^\s{0,}([\w\-]+)/);
						if($_ eq 'uuid')
						{
							$line =~ m/([\w\-]+)$/;
							push @{$info->{xen_pif}}, { uuid => $1 };
						}
						if($_ eq 'device')
						{
							$line =~ m/([\w-]+)$/;
							@{$info->{xen_pif}}[$#{$info->{xen_pif}}]->{device} = $1;
						}																																							 
						if($_ eq 'currently-attached')																				
						{																																 
							$line =~ m/([\w-]+)$/;
							@{$info->{xen_pif}}[$#{$info->{xen_pif}}]->{attached} = $1;
						}																				
						if($_ eq 'VLAN')																												
						{																																	 
							$line =~ m/([\w-]+)$/;
							@{$info->{xen_pif}}[$#{$info->{xen_pif}}]->{vlan} = $1;
						}																																	 
						if($_ eq 'bond-master-of')																							
						{																																	 
							$line =~ m/([\w-]+)$/;
							@{$info->{xen_pif}}[$#{$info->{xen_pif}}]->{bond_master_of} = $1 unless $1 =~ m/^bond-master/;
						}																																	 
						if($_ eq 'bond-slave-of')																							 
						{																																	 
							$line =~ m/([\w-]+)$/;
							@{$info->{xen_pif}}[$#{$info->{xen_pif}}]->{bond_slave_of} = $1 unless $1 =~ m/^bond-master/;
						}																																	 
						if($_ eq 'network-uuid')																								
						{																																	 
							$line =~ m/([\w-]+)$/;
							@{$info->{xen_pif}}[$#{$info->{xen_pif}}]->{network_uuid} = $1;
						}																																	 
						if($_ eq 'network-name-label')																					
						{																																	 
							$line =~ m/([\w-]+)$/;
							@{$info->{xen_pif}}[$#{$info->{xen_pif}}]->{network_name_label} = $1;
						}																																			 
					}

					#if ($info->{xen_pool}->{master_uuid} eq $uuid)
					#{
						foreach my $line (`xe sr-list params=all type=nfs`, `xe sr-list params=all type=lvmoiscsi`)									
						{																																			
							($_) = ($line =~ m/^\s{0,}([\w\-]+)/);															 
							if($_ eq 'uuid')																											 
							{																																	
								$line =~ m/([\w\-]+)$/;																					
								push @{$info->{xen_sr}}, { uuid => $1 };												 
							}																																	
							if($_ eq 'host')																					 
							{																																	
								$line =~ m/\): (.*)$/;																					 
								@{$info->{xen_sr}}[$#{$info->{xen_sr}}]->{'owner'} = $1;			
							}																
							if($_ eq 'name-label')																								 
							{																																	
								$line =~ m/([\w-]+)$/;																					 
								@{$info->{xen_sr}}[$#{$info->{xen_sr}}]->{'name'} = $1;			
							}																
							if($_ eq 'type')																											 
							{																																	
								$line =~ m/([\w-]+)$/;																					 
								@{$info->{xen_sr}}[$#{$info->{xen_sr}}]->{'type'} = $1;			
							}																
							if($_ eq 'name-description')																					 
							{																																	
								#WIP 
								# Unmatched ) in regex; marked by <-- HERE in m/\[[(\d\.]+) <-- HERE [\:\s\(]+(\S+)[\]\)]+\]$/ at /opt/local/SNAG/modules/SNAG/Source/xen.pm line 246
								#NFS SR [10.106.152.253:/vol/xennfs1]
								#iSCSI SR [10.106.153.253 (iqn.1992-08.com.netapp:sn.118043982)]
								#$line =~ m/\): (.*)$/;																					 
								#@{$info->{xen_sr}}[$#{$info->{xen_sr}}]->{'description'} = $1;			
								#my ($ip, $ses) = ($line	=~ m/\[[(\d\.]+)[\:\s\(]+(\S+)[\]\)]+\]$/;
								#if (defined $ip, $ses)
								#{
								#	
								#}
							}
						}
					#}

					my $vals;
					foreach my $line (`/usr/bin/xe vm-list params=all $args`)
					{
						chomp $line;
		
						if($line =~ /^uuid.+?: ([\w\-]+)$/)
						{
							if($vals && %$vals && $vals->{domid} != 0)
							{
								push @$xen_dom0, { uuid => $vals->{uuid}, name => $vals->{name}, domid => $vals->{domid} };
								undef $vals;
							}
							$vals->{uuid} = $1;
						}
						else
						{
							if($line =~ /Control domain on host/)
							{
								undef $vals;
							}
							elsif($line =~ /^\s*name\-label.+?: (.+)$/)
							{
								$vals->{name} = $1;
							}
							elsif($line =~ /^\s*dom\-id.+?: (.+)$/)
							{
								$vals->{domid} = $1;
							}
						}
					}
					if($vals && %$vals && $vals->{domid} != 0)
					{
						push @$xen_dom0, { uuid => $vals->{uuid}, name => $vals->{name}, domid => $vals->{domid} };
					}
				}
	
				$info->{xen_dom0} = $xen_dom0;
	 
				my $pruned;
				if(%$info && ( $pruned = SNAG::Source::sysinfo_prune($info) ) )
				{
					$pruned->{host} = HOST_NAME;
					$pruned->{seen} = time2str("%Y-%m-%d %T", time);
 
					if(defined $pruned->{xen_pool})
					{
						my $cluster_info =
						{
							host => $pruned->{xen_pool}->{name},
							seen => $pruned->{seen},
							entity =>
							{
								type => 'cluster',
							}
						};
 
						$kernel->post('client' => 'sysinfo' => 'load' => freeze($cluster_info));
					}
					$kernel->post('client' => 'sysinfo' => 'load' => freeze($pruned));
				}
				$kernel->delay($_[STATE] => 600);
			},
 
			bridge_poll => sub
			{
				my ($kernel, $heap) = @_[KERNEL, HEAP];
				my (@raw, @currbr, @brdata, $info, $pruned);

				@raw = `brctl show`;
				shift @raw;
				@{$SNAG::Dispatch::shared_data->{bridges}} = ();
				
				foreach (@raw)
				{
					@brdata = split /\s+/;
					if (m/^\w/)
					{
						@currbr = split /\s+/;
						next unless defined $currbr[3];	#only care about bridges that have interfaces (also part of primary key in db)
						push @{$info->{bridge}}, {bridge => $currbr[0]};
						@{$info->{bridge}}[$#{$info->{bridge}}]->{interface} = $currbr[3];
						push @{$SNAG::Dispatch::shared_data->{bridges}}, $currbr[0];
					}
					else
					{
						push @{$info->{bridge}}, {bridge => $currbr[0]};
						@{$info->{bridge}}[$#{$info->{bridge}}]->{interface} = $brdata[1];
					}
					@{$info->{bridge}}[$#{$info->{bridge}}]->{id} = $currbr[1];
					@{$info->{bridge}}[$#{$info->{bridge}}]->{stp} = $currbr[2];
				}

				if(%$info && ( $pruned = SNAG::Source::sysinfo_prune($info) ) )
				{
					$pruned->{host} = HOST_NAME;
					$pruned->{seen} = time2str("%Y-%m-%d %T", time);
					$kernel->post('client' => 'sysinfo' => 'load' => freeze($pruned));
				}
				
				$info = {};
				$pruned = {};
				@raw = ();
				@currbr = ();
				@brdata = ();
				foreach my $br (sort @{$SNAG::Dispatch::shared_data->{bridges}})
				{
					print "$br \n";
					@raw = `brctl showmacs $br`;
					shift @raw;
					foreach (sort @raw)
					{
						@brdata = split /\s+/;
						next unless $brdata[3] eq 'yes';
						push @{$info->{brmac}}, {mac => $brdata[2]};
						@{$info->{brmac}}[$#{$info->{brmac}}]->{local} = $brdata[3];
						@{$info->{brmac}}[$#{$info->{brmac}}]->{bridge} = $br;
					}
				}

				if(%$info && ( $pruned = SNAG::Source::sysinfo_prune($info) ) )
				{
					$pruned->{host} = HOST_NAME;
					$pruned->{seen} = time2str("%Y-%m-%d %T", time);
					$kernel->post('client' => 'sysinfo' => 'load' => freeze($pruned));
				}

				$kernel->delay($_[STATE] => 300);
			},
		}
	);
}

1;

