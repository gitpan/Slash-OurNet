#!/usr/bin/perl -w
# $File: //depot/metalist/src/plugins/OurNet/t/use.t $ $Author: autrijus $
# $Revision: #1 $ $Change: 1 $ $DateTime: 2002/06/11 08:35:12 $

use strict;
use Test;

# use a BEGIN block so we print our plan before MyModule is loaded

BEGIN { plan tests => 1 };

# Load BBS
use Slash::OurNet;

ok(1);
