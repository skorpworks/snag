#!/usr/bin/env perl

use warnings; 
use strict;

use Test::More tests => 2;

SKIP: 
{
  eval { require RRDTool::OO };

  skip "RRDTool::OO not installed.  You must not be running a SNAG RRD server on this isntall", 2 if $@;
  
  use_ok("SNAG::Server::RRD");

  diag
  ( 
    "Testing SNAG::Server::RRD"
  );
}


