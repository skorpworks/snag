#!/usr/bin/env perl

use warnings; 
use strict;

use Test::More qw/no_plan/; 

use_ok("SNAG::Source::vserver");

diag
( 
  "Testing SNAG::Source::vserver"
);





<<STAT;
CTX   PROC    VSZ    RSS  userTIME   sysTIME    UPTIME NAME
0       78 318.4M  46.8M  28m50s40   6h05m32   4d05h14 root server
131     47   1.9G   1.1G   3d04h37   1d01h38   4d05h11 mem-decode-01
151     18 316.7M 131.8M   1d10h45   1d00h51   4d05h11 mem-autopar-01
171      8  32.2M    13M   1d05h12   2h03m43   4d05h09 mem-thumber-01
191     13 695.6M 544.4M  19h06m05   8h54m58   4d05h09 mem-unrar-01
STAT

