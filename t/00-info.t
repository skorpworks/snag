#!/usr/bin/env perl

use warnings; 
use strict;

use Test::More tests => 1;

use_ok("SNAG");

diag
(
  "Testing SNAG $SNAG::VERSION, Perl $], $^X ",
  "Perl $], ",
  "$^X on $^O"
);

## More goes here?
## TODO


