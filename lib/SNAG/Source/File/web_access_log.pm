package SNAG::Source::File::web_access_log;
use base qw/SNAG::Source::File/;

use strict;

use POE;
use SNAG;
use Date::Parse;
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


  if(/\[([^]]+)\] \"?(\w+) .*? (\d+) /)
  {

    my ($timestamp, $method, $rc) = ($1, $2, $3);
    $method = lc($method);

    if($current->{timestamp} ne $timestamp)
    {
      my $minute_epoch = str2time($timestamp);

      while(++$minute_epoch % 60){}

      $current->{minute_epoch} = $minute_epoch;

      $current->{timestamp} = $timestamp;
    }

    my $type = $known_methods{$method} ? 'webacc_' . $method : 'webacc_other';

    $kernel->post('apache_logs' => 'add_msg' => { type => $type, minute => $current->{minute_epoch} } );
    $kernel->post('apache_logs' => 'add_msg' => { type => "webacc_rc_$rc", minute => $current->{minute_epoch} } );
  }
  elsif(/\[([^]]+)\] \"?(\w+)/)
  {

    my ($timestamp, $method) = ($1, $2);
    $method = lc($method);

    if($current->{timestamp} ne $timestamp)
    {
      my $minute_epoch = str2time($timestamp);
      while(++$minute_epoch % 60){}

      $current->{minute_epoch} = $minute_epoch;

      $current->{timestamp} = $timestamp;
    }

    my $type = $known_methods{$method} ? 'webacc_' . $method : 'webacc_other';

    $kernel->post('apache_logs' => 'add_msg' => { type => $type, minute => $current->{minute_epoch} } );
  }
}

1;
