#!/usr/local/bin/perl
# $File: //depot/metalist/plugins/OurNet/Makefile.PL $ $Author: autrijus $
# $Revision: #1 $ $Change: 1962 $ $DateTime: 2001/10/05 23:24:56 $

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME	 => 'Slash::OurNet',
    VERSION_FROM => 'OurNet.pm', # finds $VERSION
    PM		 => {
	'OurNet.pm' => '$(INST_LIBDIR)/OurNet.pm',
    },
    PREREQ_PM    => {
	'OurNet::BBS'	=> '1.6',
	'Slash'		=> '2.0',
    }
);
