#!/usr/local/bin/perl
# $File: //depot/metalist/plugins/OurNet/Makefile.PL $ $Author: autrijus $
# $Revision: #4 $ $Change: 2446 $ $DateTime: 2001/11/28 02:33:56 $

use 5.006;
use strict;
use warnings;

# ExtUtils::AutoInstall Bootstrap Code, version 1.
BEGIN { my $p='ExtUtils::AutoInstall'; eval"use $p 0.21;1" or(print
	"*** Fetching $p.\n"), require CPAN, CPAN::install $p; eval
	"use $p 0.21;1" or die "*** Please install $p manually.\n"}

ExtUtils::AutoInstall->import(
    -version			=> '0.21',
    -core 			=> [
	'OurNet::BBS'		=> '1.6',
	'Slash'			=> '2.0',
    ],
    'ANSI sequence formatting'	=> [
	'HTML::FromANSI'	=> '0.01',
    ],
    'Text sequence formatting'	=> [
	'HTML::FromText'	=> '1.0',
    ],
);

WriteMakefile(
    AUTHOR          => 'Autrijus Tang (autrijus@autrijus.org)',
    ABSTRACT        => 'OurNet::BBS Connectivity',
    NAME	    => 'Slash::OurNet',
    VERSION_FROM    => 'OurNet.pm',
    DISTNAME        => 'Slash-OurNet',
    BINARY_LOCATION => 'x86/Slash-OurNet.tar.gz',

    PM		 => {
	'OurNet.pm' => '$(INST_LIBDIR)/OurNet.pm',
    },

    dist            => {
        COMPRESS    => 'gzip',
        SUFFIX      => '.gz',
    }
);
