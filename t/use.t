#!/usr/bin/perl -w
# $File: //depot/metalist/src/plugins/OurNet/t/use.t $ $Author: werther $
# $Revision: #2 $ $Change: 876 $ $DateTime: 2002/09/11 15:11:54 $

use strict;
use Test;

# use a BEGIN block so we print our plan before MyModule is loaded

BEGIN { plan tests => 1 };

# Load BBS
use Slash::OurNet;

ok(1);
