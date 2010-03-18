#!/usr/bin/env perl

use warnings; 
use strict;

use Test::More tests => 3;

use_ok("SNAG");
use_ok("SNAG::Client");
use_ok("SNAG::Server");

diag
(
  "Testing SNAG $SNAG::VERSION, Perl $], $^X ",
  "Perl $], ",
  "$^X on $^O"
);


