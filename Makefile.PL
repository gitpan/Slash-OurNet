#!/usr/local/bin/perl
# $File: //depot/metalist/src/plugins/OurNet/Makefile.PL $ $Author: autrijus $
# $Revision: #1 $ $Change: 1 $ $DateTime: 2002/06/11 08:35:12 $

use 5.006;
use strict;
use warnings;

# ExtUtils::AutoInstall Bootstrap Code, version 4.
BEGIN{my$p='ExtUtils::AutoInstall';my$v=.21;eval"use $p $v;1"or
($ENV{PERL_EXTUTILS_AUTOINSTALL}!~/--(?:default|skip|testonly)/
and(-t STDIN)or eval"use ExtUtils::MakeMaker;WriteMakefile('PR'
.'EREQ_PM'=>{'$p',$v});1"and exit)and print"==> $p $v needed. "
."Install it from CPAN? [Y/n] "and<STDIN>!~/^n/i and print"***"
." Fetching $p\n"and do{eval{require CPANPLUS;CPANPLUS::install
$p};eval"use $p $v;1"or eval{require CPAN;CPAN::install$p};eval
"use $p $v;1"or die"Please install $p $v manually first...\n"}}

ExtUtils::AutoInstall->import(
    -version			=> '0.21',
    -core 			=> [
	'OurNet::BBS'		=> '1.63',
    ],
    'Slash Framework'	=> [
	-default		=> 0,
	'Slash'			=> '2.0',
    ],
    'Localization Framework'	=> [
	'Locale::Maketext'	=> 0,
	'Locale::Maketext::Lexicon'	=> 0,
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
	map { $_ => "\$(INST_LIBDIR)/OurNet/" . substr($_, 3) } <po/*>,
    },

    dist            => {
        COMPRESS    => 'gzip -9',
        SUFFIX      => '.gz',
    }
);
