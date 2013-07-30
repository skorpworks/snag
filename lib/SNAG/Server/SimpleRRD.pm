package SNAG::Server::SimpleRRD; 
use base qw(SNAG::Server);

use strict;
use SNAG;
use Time::HiRes;
use POE;
use Carp qw(carp croak);

use FileHandle;
use Data::Dumper;
use File::Basename;
use RRDs;

my $debug = $SNAG::flags{debug};

################################
sub new
################################
{
  my $type = shift;
  $type->SUPER::new(@_);

  my %params = @_;
  my $args    = delete $params{Args};

  croak "Args must be a hashref" if ref $args ne 'HASH';
  croak "Args must contain values for 'dir', 'dsn', 'user', and 'pw'" unless ($args->{dir} && $args->{dsn} && $args->{user} && $args->{pw});

  my $rrd_base_dir = $args->{dir};
  $rrd_base_dir =~ s/\/$//;  ### REMOVE TRAILING SLASH ON DIR TO AVOID PROBLEMS
   
  my $rrd;

  POE::Session->create
  (
    inline_states =>
    {
      _start => sub
      {
        my ($heap, $kernel) = @_[HEAP, KERNEL];
        $kernel->alias_set('object');

        unless(-d $rrd_base_dir)
        {
          mkdir $rrd_base_dir, 0770 and $kernel->call('logger' => "log" => "START: Creating $rrd_base_dir");
          system "chgrp nobody $rrd_base_dir";
        }

      },
      
      load => sub
      {
        my ($heap, $kernel, $parcel) = @_[HEAP, KERNEL, ARG0];

        my ($host, $ds, $type, $time, $value);
        my ($hostkey, $multival, $rrd_dir, $err);
        foreach my $row (@$parcel)
        {
          print "LOAD: $row\n" if $debug;

          ($host, $ds, $type, $time, $value) = split /:/, $row;
          if ( $host =~ s/\[(.+)\]$//)  
          { 
            $multival = $1; 
            $rrd_dir = $rrd_base_dir . "/" . $host . "/" . $multival;
          }
          else 
          {
            $rrd_dir = $rrd_base_dir . "/" . $host;
          }

          eval
          {
            RRDs::update ("$rrd_dir/$ds.rrd", "$time:$value");
            $err=RRDs::error;
            die "$err\n" if $err;
          };
          if($@)
          {
            if($@ =~ /Can\'t call method \"update\" on an undefined value/ || $@ =~ /No such file or directory at/) 
            {
              $kernel->call('logger' => 'log' => "LOAD: RRD does not exist, skipping \'$row\' :: $rrd_dir/$ds.rrd");
            }
            else
            {
              $kernel->call('logger' => 'log' => "LOAD: Failed loading \'$row\', $@");
            }
          }
        }
        return 0;
      },
    }
  );
}

1;
