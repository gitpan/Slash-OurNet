#!/usr/local/bin/perl
# $File: //depot/metalist/src/plugins/OurNet/Makefile.PL $ $Author: autrijus $
# $Revision: #15 $ $Change: 10250 $ $DateTime: 2004/03/01 10:20:56 $

use strict;
use inc::Module::Install;

author		('Autrijus Tang <autrijus@autrijus.org>');
abstract	('Web Interface for OurNet::BBS');
name		('Slash-OurNet');
version_from	('lib/Slash/OurNet.pm');
include		('ExtUtils::AutoInstall');
license		('perl');

if ($] < 5.008 or prompt(
    "Automatically install Slash::OurNet's prerequisites from CPAN? [y/N]:"
) !~ /[Yy]/) {
    WriteAll( sign => 1, check_nmake => 0 );
    exit;
}

requires(
	'OurNet::BBS'			=> 1.64,
	'Locale::Maketext::Lexicon'	=> 0.32,
	'HTML::FromANSI'		=> 0,
	'HTML::FromText'		=> 0,
	'Template'			=> 0,
	'Date::Format'			=> 0,
	'Date::Parse'			=> 0,
	'Lingua::ZH::Wrap'		=> 0.02,
	'if'				=> 0.3,
	'Devel::Hints'			=> 0.02,
	'PerlIO::via::trap'		=> 0.10,
);
auto_install();

WriteAll( sign => 1, check_nmake => 0 );
