#!/usr/bin/perl -w
# $File: //depot/metalist/plugins/OurNet/test.pl $ $Author: autrijus $
# $Revision: #1 $ $Change: 1965 $ $DateTime: 2001/10/05 23:27:48 $

use strict;
use Test;

# use a BEGIN block so we print our plan before MyModule is loaded

BEGIN { plan tests => 1 };

# Load BBS
use Slash::OurNet;

ok(1);
