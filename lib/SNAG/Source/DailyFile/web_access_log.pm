package SNAG::Source::DailyFile::web_access_log;
use base qw/SNAG::Source::DailyFile/;

use strict;

use POE;
use SNAG;
use Date::Manip;
use Data::Dumper;

my %known_methods =
(
  'get' => 1,
  'head' => 1,
  'put' => 1,
  'post' => 1,
  'delete' => 1,
  'options' => 1,
  'propfind' => 1,
  'proppatch' => 1,
  'mkcol' => 1,
  'copy' => 1,
  'copy' => 1,
  'move' => 1,
  'lock' => 1,
  'unlock' => 1,
  'patch' => 1,
);

my $current;
sub filter
{
  my ($kernel, $heap) = @_[ KERNEL, HEAP ];
  $_ = $_[ ARG0 ];


  if(/\[([^]]+)\] \"?(\w+)/)
  {
    my ($timestamp, $method) = ($1, $2);
    $method = lc($method);

    if($current->{timestamp} ne $timestamp)
    {
      my $minute_epoch = UnixDate($timestamp, "%s");
      while(++$minute_epoch % 60){}

      $current->{minute_epoch} = $minute_epoch;

      $current->{timestamp} = $timestamp;
    }

    my $type = $known_methods{$method} ? 'webacc_' . $method : 'webacc_other';

    $kernel->post('apache_logs' => 'add_msg' => { type => $type, minute => $current->{minute_epoch} } );
  }
}

1;
