#!/usr/bin/perl -w
# $File: //depot/metalist/plugins/OurNet/t/use.t $ $Author: autrijus $
# $Revision: #1 $ $Change: 2427 $ $DateTime: 2001/11/26 08:16:42 $

use strict;
use Test;

# use a BEGIN block so we print our plan before MyModule is loaded

BEGIN { plan tests => 1 };

# Load BBS
use Slash::OurNet;

ok(1);
