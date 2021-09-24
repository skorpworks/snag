#!/usr/bin/env perl

use strict;

use FindBin;
use lib "/opt/snag/lib/perl5";

use POE;

use SNAG;
use SNAG::Server;
use SNAG::Client;

use Getopt::Long;
use Data::Dumper;

foreach my $arg (@ARGV) {
    $arg =~ s/^\-{1,2}//;
    $SNAG::flags{$arg} = 1;
}

if ( $SNAG::flags{compile} ) {
    unless ( $ENV{PAR_SPAWNED} ) {
        die "PP_INCLUDES environment variable not set.\n"    unless $ENV{PP_INCLUDES};
        die "SNAGS_INCLUDES environment variable not set.\n" unless $ENV{SNAGS_INCLUDES};
        print "Compiling $0 to snags ... ";
        my $includes;
        for my $include_file ( $ENV{PP_INCLUDES}, $ENV{SNAGS_INCLUDES} ) {
            unless ( -r $include_file ) {
                warn "$include_file does not exist - skipping\n";
                next;
            }
            open( my $fh, '<', $include_file ) || die "Could not open $include_file - $!\n";
            while (<$fh>) {
                chomp;
                next unless (/\w+/);
                $includes .= " -M $_";
            }
            close($fh);
        }
        my $cmd = "pp $0 --compile --execute --bundle" . $includes . " -a /opt/snag/snag.conf -o snags";

        print "with cmd $cmd\n";
        my $out = '';
        open LOG, "$cmd |" || die "DIED: $!\n";
        while (<LOG>) {
            print $_;
            $out .= $_;
        }

        print "Done!\n";

        if ( $out =~ /\w/ ) {
            print "=================== DEBUG ==================\n";
            print $out;
        }
    }
    else {
        print "This is already a compile binary!\n";
    }

    exit;
}

### Get rid of this once all sources are converted to dispatching
my %options;
GetOptions( \%options, 'debug', 'verbose' );

my $scriptname = SCRIPT_NAME;
exit if already_running();

die "Invalid usage of snags.pl!" unless ( split /_/, $scriptname ) == 2;
my ($type) = ( split /_/, $scriptname )[0];

my ( $login, $pass, $uid, $gid ) = getpwnam('snag');
if ( defined $uid ) {
    $) = $gid;
    $> = $uid;
}

umask(0027);

logger();
daemonize() unless $SNAG::flags{debug};

my $confin = CONF;

my $server = $confin->{server}->{$type} or die "Server type $type does not exist in snag.conf!";

my $mod_file = $server->{module};
$mod_file =~ s/::/\//g;
$mod_file .= ".pm";
require $mod_file;

$server->{module}->new(
                        Alias   => $type,
                        Port    => $server->{port},
                        Key     => $server->{key},
                        Args    => $server->{args},
                        Options => \%options,
                      );

SNAG::Client->new( $confin->{client} );

$SIG{INT} = $SIG{TERM} = sub {
    $poe_kernel->call( 'logger' => 'log' => "Killed" );
    exit;
};

$poe_kernel->run;
