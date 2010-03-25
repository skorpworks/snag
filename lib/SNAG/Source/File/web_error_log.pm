package SNAG::Source::File::web_error_log;
use base qw/SNAG::Source::File/;

use strict;

use POE;
use SNAG;
use Date::Parse;
use Data::Dumper;

my $del = REC_SEP;


my $keepers =
[
  {
    desc => 'Apache restart',
    #type  => 'weberr_start',
    regexp => qr/resuming normal operations/,
  },

  {
    desc => 'MaxClients limit reached',
    #type  => 'weberr_max',
    regexp => qr/server reached MaxClients setting/,
  },

  {
    desc => 'Apache restart',
    #type  => 'weberr_unclean',
    regexp => qr/overwritten \-\- Unclean shutdown of previous Apache run/,
  },

  { 
    desc => 'Apache restart',
    #type  => 'weberr_stop',
    regexp => qr/Graceful restart requested\, doing restart/,
  },
];

sub filter
{
  my ($kernel, $heap) = @_[ KERNEL, HEAP ];
  $_ = $_[ ARG0 ];


  if(/^\[([^\]]+)\]\s+\[([^\]]+)\]/)
  {
    my ($timestamp, $level) = ($1, $2);

    my $minute_epoch = str2time($timestamp);
    while(++$minute_epoch % 60){}

    foreach my $hashref (@$keepers)
    {
      if($_ =~ /$hashref->{regexp}/)
      {
        if($hashref->{type})
        {
          $kernel->post('apache_logs' => 'add_msg' => { type => $hashref->{type}, minute => $minute_epoch } );
        }

        if($hashref->{desc})
        {
          my @t = strptime($timestamp);
          my $seen = "$t[5]-$t[4]-$t[3] $t[2]:$t[1]:$t[0]";
          $kernel->post('client' => 'dashboard' => 'load' => join $del, ('events', HOST_NAME, 'apache', 'error_log', $hashref->{desc}, $_, '', $seen));
        }

        last; ## Shouldn't match more than once
      }
    }

    $kernel->post('apache_logs' => 'add_msg' => { type => 'weberr_' . $level, minute => $minute_epoch } );
  }
}


1;
