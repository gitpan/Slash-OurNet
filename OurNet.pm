# $File: //member/autrijus/slash-ournet/ournet.pl $ $Author: autrijus $
# $Revision: #13 $ $Change: 1360 $ $DateTime: 2001/07/01 06:41:24 $

package Slash::OurNet;

our $VERSION = '1.0';
our @ISA = qw/Slash::DB::Utility Slash::DB::MySQL/ if $ENV{SLASH_USER};

use strict;
use warnings;

use Text::Wrap;
use Date::Parse;
use Date::Format;
# use HTML::FromText;
use OurNet::BBS;

$OurNet::BBS::Client::NoCache =
$OurNet::BBS::Client::NoCache = 1; # avoids bloat

no warnings 'redefine';

our ($TopClass, $MailBox, $Organization, @Connection, $SecretSigils, 
     $BoardPrefixLength, $GroupPrefixLength, $Strip_ANSI,
     $Thread_Prev, $Date_Prev, $Thread_Next, $Date_Next);

$Text::Wrap::columns = 75;

our %CachedTop;

(my $pathname = $0) =~ s/[^\/]+$//;
$pathname ||= '.';
do "$pathname/ournet.conf";

sub new {
    my ($class, $user) = splice(@_, 0, 2);
    no warnings 'once';
    my $self = {
	bbs => $cached::BBS{"@_"} ||= OurNet::BBS->new(@_),
	virtual_user => $user,
    };

    return bless($self, $class);
}

sub article_save {
    my ($self, $group, $board, $child, $name, $reply, 
        $title, $body, $state, $user, $nick) = @_;

    $child ||= 'articles';
    my $artgrp = $self->{bbs}{boards}{$board};

    # honor 75-column tradition of legacy BBS systems
    $body = wrap('','', $body) if length($body) > 75;

    # we could ignore the $reply until a Reply-To header is supported
    my $article = {
	header	=> {
	    From    => "$user ($nick)",
	    Subject => $title || '',
	    Board   => $board,
	    # XXX GMT error! oh my god they killed kenny!
	    Date    => (scalar localtime(time+28800)),
	},
	body	=> $body || '',
    };

    my $error; # error message

    $error .= '請輸入標題.<hr>' unless (length($article->{header}));
    $error = '&nbsp;' unless $state;

    $artgrp->{articles}{$name || ''} = $article unless $error;

    return ($article, $error);
}

sub article {
    my ($self, $group, $board, $child, $name, $reply) = @_;
    my (@related, $artgrp, $is_reply);

    # put $reply to $name and set flag for further processing
    $is_reply++ if !defined($name) and defined($name = $reply);
    return unless defined $name; # happens when a new article's made

    $child ||= 'articles';
    $artgrp = $self->{bbs}{($child eq 'mailbox') ? 'users' : 'boards'}{$board};
    
    foreach my $chunk (split('/', $child)) {
	$artgrp = $artgrp->{$chunk};
    }

    my $article	= $artgrp->{$name};

    my $related = $is_reply ? [] :  $self->related_articles(
	[ group => $group, board => $board, child => $child ],
	$artgrp, $article,
    ); # do not calculate related article during reply

    return ($self->mapArticle(
	$group, $board, $child, $name, $article, $is_reply
    ), $related);
}

sub related_articles {
    my ($self, $params, $artgrp, $article) = @_;
    my $header	= $article->{header};
    my $recno	= $article->recno;
    my $size	= $#{$artgrp};
    my $title	= $header->{Subject};
    my $related = [];

    $title = "Re: $title" unless substr($title, 0, 4) eq 'Re: ';

    my %cache;
    # grepping for thread_prev
    if ($Thread_Prev) { foreach my $i (reverse(($recno - 5) .. ($recno - 1))) {
	next if $i < 0;
	my $art = $artgrp->[$i];
	my $title2 = $art->{header}->{Subject};
	next unless $title eq $title2 or $title eq "Re: $title2";
	pushy(\%cache, $related, $params, $Thread_Prev, $art);
	last;
    } }

    pushy(\%cache, $related, $params, $Date_Prev, $artgrp->[$recno - 1]) 
	if $Date_Prev and $recno;

    if ($Thread_Next) { foreach my $i (($recno + 1) .. ($recno + 5)) {
	next if $i > $size;
	my $art = $artgrp->[$i];
	my $title2 = $art->{header}{Subject};
	next unless $title eq $title2 or $title eq "Re: $title2";
	pushy(\%cache, $related, $params, $Thread_Next, $art);
	last;
    } }

    pushy(\%cache, $related, $params, $Date_Next, $artgrp->[$recno + 1])
	if $Date_Next and $recno < $size - 1;

    return $related;
}

sub pushy {
    my ($cache, $self, $params, $relation, $art) = @_;
    return unless defined $art;

    my $name = $art->name;
    return if $cache->{$name}++;
    my $header = $art->{header};
    my $author = $art->{author};
    $author =~ s/(?:\.\.?bbs)?\@.+/\./;

    push @{$self}, {
	@{$params}, 
	relation => $relation, name => $name, header => $header,
	author => $author
    } unless $params->[5] ne 'articles' and $art->REF =~ /Group/;
}

sub board {
    my ($self, $group, $board, $child, $begin) = @_;
    my ($artgrp, $bm, $title, $etc);

    my $PageSize = 20;
    if ($child eq 'mailbox') {
	$artgrp = $self->{bbs}{users}{$board};
	$bm	= $board;
	$title	= $MailBox;
	$etc	= '';
    }
    else {
	$artgrp	= $self->{bbs}{boards}{$board};
	$bm	= $artgrp->{bm};
	$title	= $artgrp->{title};
	if ($etc = $artgrp->{etc_brief}) {
	    $etc = (split(/\n\n+/, $etc, 2))[1];
	    $etc =~ s/\x1b\[[\d\;]*m//g;
	    $etc =~ s/\n+/<br>/g;
	}
    }
    
    die "no such board" unless $artgrp;
    return unless $artgrp;

    die "permission denied"
        if $child ne 'mailbox' and $SecretSigils and
	    index($SecretSigils, substr($artgrp->{title}, 4, 2)) > -1;

    foreach my $chunk (split('/', $child)) {
	$artgrp = $artgrp->{$chunk};
    }

    my $reversed = ($child eq 'articles' or $child eq 'mailbox');
    my $size = $#{$artgrp};
    $begin = $reversed ? ($size - $PageSize + 1) : 0
	unless defined $begin;

    my @pages;

    foreach my $page (1..(int($size / $PageSize)+1)) {
	my $thisbegin = $reversed
	    ? ($size - ($page * $PageSize) + 1)
	    : (($page - 1) * $PageSize + 1);
	my $iscurpage = ($thisbegin == $begin);
        push @pages, {
            number     => $page,
	    begin      => $thisbegin,
	    iscurpage  => $iscurpage,
        };
    }

    $size = $begin + $PageSize - 1 if ($begin + $PageSize - 1 <= $size);
    $begin = 0 if $begin < 0;

    my $message = "| $board | ".
		(($artgrp->name or $child eq 'mailbox') 
		    ? $title : substr($title, $BoardPrefixLength)).
		" | $bm |<hr>";
    $message .= $etc if defined $etc;

    my @range = $reversed
	? reverse ($begin .. $size) : ($begin.. $size);

    local $_;
    return ($message, ($#pages ? \@pages : undef), $self->mapArticles(
	$group, $board, $child, \@range,
	map { eval { $artgrp->[$_] } || 0 } @range
    ));
}

sub group {
    my ($self, $group, $board) = @_;
    my $boards = $board eq 'Class'
	? $self->{bbs}{groups} : $self->{bbs}{groups}{$board};

    my ($thisgroup, $title, $bm, $etc);

    if ($board eq 'Class') {
	$bm = 'SYSOP';
	$title = 'All Boards';
    }
    elsif ($title = $boards->{title}) {
	$bm = $boards->{bm}; # XXX!
	$bm = $boards->{owner};
	$etc = $self->{bbs}{boards}{$board}{etc_brief}
	    if exists $self->{bbs}{boards}{$board};
    }

    local $_;

    my $message = "| $board | ".
		    (substr($title, $GroupPrefixLength) || $Organization) .
		($bm ? " | $bm |<hr>" : ' |<hr>');
    $message .= $etc if defined $etc;

    $boards->refresh;

    return ($self->mapBoards(
	$board,
	map { 
	    $boards->{$_} 
	} sort {
	    uc($a) cmp uc($b)
	} grep {
	    $_ !~ /^(?:owner|id|title)$/
	} keys (%{$boards}),
    ), $message);
}

sub top {
    my $self = shift;

    # XXX kludge!
    my $top = $self->{bbs}{files}{'@-day'} || $self->{bbs}{files}{day};
    my $brds = $self->{bbs}{boards};
    my @ret;
    
    if (($self->{top} || '') eq $top) {
	@ret = $CachedTop{"@Connection"};
    }
    else { while (
	$top =~ s/^.*?32m([^\s]+).*?33m\s*([^\s]+)\n.*?37m\s*([^\x1b]+?)\x20*\x1b//m
    ) {
	my ($board, $author, $title) = ($1, $2, $3);
	my $artgrp = $brds->{$board}{articles};

	foreach my $art (reverse(0..$#{$artgrp})) {
	    my $article = $artgrp->[$art];
	    next unless ($article->{title} eq $title);
	    push @ret, $article;
	    last;
	}
    } 
	$CachedTop{"@Connection"} = \@ret;
	$self->{top} = $top;
    }

    return $self->mapArticles($TopClass, '', 'articles', [], @ret);
}

sub mapArticles {
    my ($self, $group, $board, $child, $range) = splice(@_, 0, 5);

    local $_; 
    return [ map {
	my $recno = shift(@{$range});
	my ($type, $title, $date, $author, $board, $name);

	if ($_) {
	    $type   = ($_->REF =~ /Group/) ? 'group' : 'article'; 
	    $title  = $_->{title};
	    $title  =~ s/\x1b\[[\d\;]*m//g; 
	    $date   = time2str('%m/%d', $_->mtime);
	    $author = $_->{author};
	    $board  = $board || $_->board;
	    $name   = $_->name;
	}
	else { # deleted article
	    $type   = 'deleted';
	    $title  = '<< 本文章經作者刪除 >>';
	    $board  = $board;
	    $author = '&nbsp;';
	    $date   = '&nbsp;';
	}

	{ 
	    title	=> $title,
	    child	=> $child,
	    group	=> $group,
	    type	=> $type,
	    date	=> $date,
	    author	=> $author,
	    board	=> $board,
	    name	=> $name,
	    recno 	=> $recno,
	    articles_count	=> $type eq 'group' ? $#{$_} : 1,
	}
    } @_ ];
}

sub mapArticle {
    my ($self, $group, $board, $child, $name, $article, $is_reply) = @_;
    my $header = { %{$article->{header}} };
    my $title = $header->{Subject};
    $header->{Subject} =~ s/\x1b\[[\d\;]*m//g; 

    return {
	body	=> txt2html($article, $is_reply),
	header	=> $header,
	title	=> $title,
	board	=> $board,
	group	=> $group,
	child	=> $child,
	name 	=> $name,
    };
}

sub mapBoards {
    my $self  = shift;
    my $group = shift;

    my (@group, @board);
    local $_;
    no strict 'refs';

    foreach (@_) {
	my $type = 'board';
	my $board;
	my $etc;
	my ($title, $date, $bm);

	if ($_->REF =~ /Group$/) {
	    $board = $_->group;

	    if ($title = $_->{title}) {
		$title =~ s|^[^/]+/\s+||;
		$bm = $_->{owner};
		$bm = '' if $bm =~ /\W/; # XXX melix 0.8 bug
	    }

	    $type = 'group';
	}
	else {
	    $board = $_->board;
	    if ($etc = $_->{etc_brief}) {
		$etc = (split(/\n\n+/, $etc, 2))[1];
		$etc =~ s/\n+/\n/g;
	    }
	    $bm = $_->{bm},
	    $title = substr($_->{title}, $BoardPrefixLength);
	}

        next if $SecretSigils and index(
	    $SecretSigils, substr($_->{title}, 4, 2)
	) > -1;

        next if $TopClass and $board eq $TopClass;

	my $entry = {
	    title	=> $title,
	    bm		=> $bm,
	    etc_brief	=> $etc,
	    group	=> $group,
	    board	=> $board,
	    type	=> $type,
	    archives_count => (
		($type eq 'group') ? '' : $#{$_->{archives}}
	    ),
	    articles_count => (
		($type eq 'group') ? '&nbsp;' : $#{$_->{articles}}
	    ),
	};

	if ($type eq 'group') {
	    push @group, $entry;
	}
	else {
	    push @board, $entry;
	}
    }

    return [ @group, @board ];
}

sub txt2html {
    my ($article, $is_reply) = @_;

    # reply mode decorations
    my $body = $article->{body};

    if ($is_reply) {
	$body =~ s/^(.+)\n+--+\n.+/$1/sg;
	$body =~ s/\n+/\n: /g;
	$body =~ s/\n: : : .*//g;
	$body =~ s/\n: : ※ .*//g;
	$body =~ s/: \n+/\n/g;
	$body = "※ 引述《$article->{header}{From}》之銘言：\n: $body";
    }
    else {
        # XXX handle ANSI codes
        $body =~ s/\x1b\[.*?[mJH]//g if $Strip_ANSI;
        $body = ansi2html($body);

	# $body = text2html(
	#     $body,
	#     metachars => 1,  urls      => 1,
	#     email     => 1,  underline => 1,
	#     lines     => 1,  spaces    => 1,
	# );
    }

    return $body;
}

#!/usr/bin/perl -w

# perl script to convert ANSI screens to HTML pages
# copyright 2001, Stephen Hurd (shurd@sk.sympatico.ca)
# patched by Autrijus Tang (autrijus@autrijus.org)
#
# usage: convert.pl infile outfile
# Does not work well with movement codes!
#

no utf8;
use strict;

my ($text, $strpos, $new_text, $line_pos, $char, $ansi_code, $html_style, $html_color, $code_length);
my ($attribute, $attributes, @attributes, $this_line);
my ($attr, $foreground, $background, $blink, $old_style, $old_html_color, %ascii);
my ($spaces, $nbspaces, $backspaces);

my %styles;
my $STYLE;

sub init {
	return if $STYLE;
	$attr = '0';
$foreground='37';
$background='40';
$blink='';
$old_style='';
$old_html_color='';
%ascii = map { $_ => chr($_) } (127..255);

$spaces=' ' x 92;
$nbspaces=$spaces.$spaces;
$backspaces="\x08" x 200;

$STYLE = << '.';
a                               {text-decoration: none;}
a:visited                       {text-decoration: none;}
a:link                          {text-decoration: none;}
.a-0-30-40                      {color: black; background-color: black;}
.a-0-31-40                      {color: #aa0000; background-color: black;}
.a-0-32-40                      {color: #00aa00; background-color: black;}
.a-0-33-40                      {color: #aaaa00; background-color: black;}
.a-0-34-40                      {color: #0000aa; background-color: black;}
.a-0-35-40                      {color: #aa00aa; background-color: black;}
.a-0-36-40                      {color: #00aaaa; background-color: black;}
.a-0-37-40                      {color: #aaaaaa; background-color: black;}
.a-1-30-40                      {color: #444444; background-color: black;}
.a-1-31-40                      {color: #ff4444; background-color: black;}
.a-1-32-40                      {color: #44ff44; background-color: black;}
.a-1-33-40                      {color: #ffff44; background-color: black;}
.a-1-34-40                      {color: #4444ff; background-color: black;}
.a-1-35-40                      {color: #ff44ff; background-color: black;}
.a-1-36-40                      {color: #44ffff; background-color: black;}
.a-1-37-40                      {color: white; background-color: black;}
.a-0-30-41                      {color: black; background-color: #aa0000;}
.a-0-31-41                      {color: #aa0000; background-color: #aa0000;}
.a-0-32-41                      {color: #00aa00; background-color: #aa0000;}
.a-0-33-41                      {color: #aaaa00; background-color: #aa0000;}
.a-0-34-41                      {color: #0000aa; background-color: #aa0000;}
.a-0-35-41                      {color: #aa00aa; background-color: #aa0000;}
.a-0-36-41                      {color: #00aaaa; background-color: #aa0000;}
.a-0-37-41                      {color: #aaaaaa; background-color: #aa0000;}
.a-1-30-41                      {color: #444444; background-color: #aa0000;}
.a-1-31-41                      {color: #ff4444; background-color: #aa0000;}
.a-1-32-41                      {color: #44ff44; background-color: #aa0000;}
.a-1-33-41                      {color: #ffff44; background-color: #aa0000;}
.a-1-34-41                      {color: #4444ff; background-color: #aa0000;}
.a-1-35-41                      {color: #ff44ff; background-color: #aa0000;}
.a-1-36-41                      {color: #44ffff; background-color: #aa0000;}
.a-1-37-41                      {color: white; background-color: #aa0000;}
.a-0-30-42                      {color: black; background-color: #00aa00;}
.a-0-31-42                      {color: #aa0000; background-color: #00aa00;}
.a-0-32-42                      {color: #00aa00; background-color: #00aa00;}
.a-0-33-42                      {color: #aaaa00; background-color: #00aa00;}
.a-0-34-42                      {color: #0000aa; background-color: #00aa00;}
.a-0-35-42                      {color: #aa00aa; background-color: #00aa00;}
.a-0-36-42                      {color: #00aaaa; background-color: #00aa00;}
.a-0-37-42                      {color: #aaaaaa; background-color: #00aa00;}
.a-1-30-42                      {color: #444444; background-color: #00aa00;}
.a-1-31-42                      {color: #ff4444; background-color: #00aa00;}
.a-1-32-42                      {color: #44ff44; background-color: #00aa00;}
.a-1-33-42                      {color: #ffff44; background-color: #00aa00;}
.a-1-34-42                      {color: #4444ff; background-color: #00aa00;}
.a-1-35-42                      {color: #ff44ff; background-color: #00aa00;}
.a-1-36-42                      {color: #44ffff; background-color: #00aa00;}
.a-1-37-42                      {color: white; background-color: #00aa00;}
.a-0-30-43                      {color: black; background-color: #aaaa00;}
.a-0-31-43                      {color: #aa0000; background-color: #aaaa00;}
.a-0-32-43                      {color: #00aa00; background-color: #aaaa00;}
.a-0-33-43                      {color: #aaaa00; background-color: #aaaa00;}
.a-0-34-43                      {color: #0000aa; background-color: #aaaa00;}
.a-0-35-43                      {color: #aa00aa; background-color: #aaaa00;}
.a-0-36-43                      {color: #00aaaa; background-color: #aaaa00;}
.a-0-37-43                      {color: #aaaaaa; background-color: #aaaa00;}
.a-1-30-43                      {color: #444444; background-color: #aaaa00;}
.a-1-31-43                      {color: #ff4444; background-color: #aaaa00;}
.a-1-32-43                      {color: #44ff44; background-color: #aaaa00;}
.a-1-33-43                      {color: #ffff44; background-color: #aaaa00;}
.a-1-34-43                      {color: #4444ff; background-color: #aaaa00;}
.a-1-35-43                      {color: #ff44ff; background-color: #aaaa00;}
.a-1-36-43                      {color: #44ffff; background-color: #aaaa00;}
.a-1-37-43                      {color: white; background-color: #aaaa00;}
.a-0-30-44                      {color: black; background-color: #0000aa;}
.a-0-31-44                      {color: #aa0000; background-color: #0000aa;}
.a-0-32-44                      {color: #00aa00; background-color: #0000aa;}
.a-0-33-44                      {color: #aaaa00; background-color: #0000aa;}
.a-0-34-44                      {color: #0000aa; background-color: #0000aa;}
.a-0-35-44                      {color: #aa00aa; background-color: #0000aa;}
.a-0-36-44                      {color: #00aaaa; background-color: #0000aa;}
.a-0-37-44                      {color: #aaaaaa; background-color: #0000aa;}
.a-1-30-44                      {color: #444444; background-color: #0000aa;}
.a-1-31-44                      {color: #ff4444; background-color: #0000aa;}
.a-1-32-44                      {color: #44ff44; background-color: #0000aa;}
.a-1-33-44                      {color: #ffff44; background-color: #0000aa;}
.a-1-34-44                      {color: #4444ff; background-color: #0000aa;}
.a-1-35-44                      {color: #ff44ff; background-color: #0000aa;}
.a-1-36-44                      {color: #44ffff; background-color: #0000aa;}
.a-1-37-44                      {color: white; background-color: #0000aa;}
.a-0-30-45                      {color: black; background-color: #aa00aa;}
.a-0-31-45                      {color: #aa0000; background-color: #aa00aa;}
.a-0-32-45                      {color: #00aa00; background-color: #aa00aa;}
.a-0-33-45                      {color: #aaaa00; background-color: #aa00aa;}
.a-0-34-45                      {color: #0000aa; background-color: #aa00aa;}
.a-0-35-45                      {color: #aa00aa; background-color: #aa00aa;}
.a-0-36-45                      {color: #00aaaa; background-color: #aa00aa;}
.a-0-37-45                      {color: #aaaaaa; background-color: #aa00aa;}
.a-1-30-45                      {color: #444444; background-color: #aa00aa;}
.a-1-31-45                      {color: #ff4444; background-color: #aa00aa;}
.a-1-32-45                      {color: #44ff44; background-color: #aa00aa;}
.a-1-33-45                      {color: #ffff44; background-color: #aa00aa;}
.a-1-34-45                      {color: #4444ff; background-color: #aa00aa;}
.a-1-35-45                      {color: #ff44ff; background-color: #aa00aa;}
.a-1-36-45                      {color: #44ffff; background-color: #aa00aa;}
.a-1-37-45                      {color: white; background-color: #aa00aa;}
.a-0-30-46                      {color: black; background-color: #44ffff;}
.a-0-31-46                      {color: #aa0000; background-color: #44ffff;}
.a-0-32-46                      {color: #00aa00; background-color: #44ffff;}
.a-0-33-46                      {color: #aaaa00; background-color: #44ffff;}
.a-0-34-46                      {color: #0000aa; background-color: #44ffff;}
.a-0-35-46                      {color: #aa00aa; background-color: #44ffff;}
.a-0-36-46                      {color: #00aaaa; background-color: #44ffff;}
.a-0-37-46                      {color: #aaaaaa; background-color: #44ffff;}
.a-1-30-46                      {color: #444444; background-color: #44ffff;}
.a-1-31-46                      {color: #ff4444; background-color: #44ffff;}
.a-1-32-46                      {color: #44ff44; background-color: #44ffff;}
.a-1-33-46                      {color: #ffff44; background-color: #44ffff;}
.a-1-34-46                      {color: #4444ff; background-color: #44ffff;}
.a-1-35-46                      {color: #ff44ff; background-color: #44ffff;}
.a-1-36-46                      {color: #44ffff; background-color: #44ffff;}
.a-1-37-46                      {color: white; background-color: #44ffff;}
.a-0-30-47                      {color: black; background-color: #aaaaaa;}
.a-0-31-47                      {color: #aa0000; background-color: #aaaaaa;}
.a-0-32-47                      {color: #00aa00; background-color: #aaaaaa;}
.a-0-33-47                      {color: #aaaa00; background-color: #aaaaaa;}
.a-0-34-47                      {color: #0000aa; background-color: #aaaaaa;}
.a-0-35-47                      {color: #aa00aa; background-color: #aaaaaa;}
.a-0-36-47                      {color: #00aaaa; background-color: #aaaaaa;}
.a-0-37-47                      {color: #aaaaaa; background-color: #aaaaaa;}
.a-1-30-47                      {color: #444444; background-color: #aaaaaa;}
.a-1-31-47                      {color: #ff4444; background-color: #aaaaaa;}
.a-1-32-47                      {color: #44ff44; background-color: #aaaaaa;}
.a-1-33-47                      {color: #ffff44; background-color: #aaaaaa;}
.a-1-34-47                      {color: #4444ff; background-color: #aaaaaa;}
.a-1-35-47                      {color: #ff44ff; background-color: #aaaaaa;}
.a-1-36-47                      {color: #44ffff; background-color: #aaaaaa;}
.a-1-37-47                      {color: white; background-color: #aaaaaa;}
.a5-0-30-40                     {text-decoration: blink; color: black; background-color: black;}
.a5-0-31-40                     {text-decoration: blink; color: #aa0000; background-color: black;}
.a5-0-32-40                     {text-decoration: blink; color: #00aa00; background-color: black;}
.a5-0-33-40                     {text-decoration: blink; color: #aaaa00; background-color: black;}
.a5-0-34-40                     {text-decoration: blink; color: #0000aa; background-color: black;}
.a5-0-35-40                     {text-decoration: blink; color: #aa00aa; background-color: black;}
.a5-0-36-40                     {text-decoration: blink; color: #00aaaa; background-color: black;}
.a5-0-37-40                     {text-decoration: blink; color: #aaaaaa; background-color: black;}
.a5-1-30-40                     {text-decoration: blink; color: #444444; background-color: black;}
.a5-1-31-40                     {text-decoration: blink; color: #ff4444; background-color: black;}
.a5-1-32-40                     {text-decoration: blink; color: #44ff44; background-color: black;}
.a5-1-33-40                     {text-decoration: blink; color: #ffff44; background-color: black;}
.a5-1-34-40                     {text-decoration: blink; color: #4444ff; background-color: black;}
.a5-1-35-40                     {text-decoration: blink; color: #ff44ff; background-color: black;}
.a5-1-36-40                     {text-decoration: blink; color: #44ffff; background-color: black;}
.a5-1-37-40                     {text-decoration: blink; color: white; background-color: black;}
.a5-0-30-41                     {text-decoration: blink; color: black; background-color: #aa0000;}
.a5-0-31-41                     {text-decoration: blink; color: #aa0000; background-color: #aa0000;}
.a5-0-32-41                     {text-decoration: blink; color: #00aa00; background-color: #aa0000;}
.a5-0-33-41                     {text-decoration: blink; color: #aaaa00; background-color: #aa0000;}
.a5-0-34-41                     {text-decoration: blink; color: #0000aa; background-color: #aa0000;}
.a5-0-35-41                     {text-decoration: blink; color: #aa00aa; background-color: #aa0000;}
.a5-0-36-41                     {text-decoration: blink; color: #00aaaa; background-color: #aa0000;}
.a5-0-37-41                     {text-decoration: blink; color: #aaaaaa; background-color: #aa0000;}
.a5-1-30-41                     {text-decoration: blink; color: #444444; background-color: #aa0000;}
.a5-1-31-41                     {text-decoration: blink; color: #ff4444; background-color: #aa0000;}
.a5-1-32-41                     {text-decoration: blink; color: #44ff44; background-color: #aa0000;}
.a5-1-33-41                     {text-decoration: blink; color: #ffff44; background-color: #aa0000;}
.a5-1-34-41                     {text-decoration: blink; color: #4444ff; background-color: #aa0000;}
.a5-1-35-41                     {text-decoration: blink; color: #ff44ff; background-color: #aa0000;}
.a5-1-36-41                     {text-decoration: blink; color: #44ffff; background-color: #aa0000;}
.a5-1-37-41                     {text-decoration: blink; color: white; background-color: #aa0000;}
.a5-0-30-42                     {text-decoration: blink; color: black; background-color: #00aa00;}
.a5-0-31-42                     {text-decoration: blink; color: #aa0000; background-color: #00aa00;}
.a5-0-32-42                     {text-decoration: blink; color: #00aa00; background-color: #00aa00;}
.a5-0-33-42                     {text-decoration: blink; color: #aaaa00; background-color: #00aa00;}
.a5-0-34-42                     {text-decoration: blink; color: #0000aa; background-color: #00aa00;}
.a5-0-35-42                     {text-decoration: blink; color: #aa00aa; background-color: #00aa00;}
.a5-0-36-42                     {text-decoration: blink; color: #00aaaa; background-color: #00aa00;}
.a5-0-37-42                     {text-decoration: blink; color: #aaaaaa; background-color: #00aa00;}
.a5-1-30-42                     {text-decoration: blink; color: #444444; background-color: #00aa00;}
.a5-1-31-42                     {text-decoration: blink; color: #ff4444; background-color: #00aa00;}
.a5-1-32-42                     {text-decoration: blink; color: #44ff44; background-color: #00aa00;}
.a5-1-33-42                     {text-decoration: blink; color: #ffff44; background-color: #00aa00;}
.a5-1-34-42                     {text-decoration: blink; color: #4444ff; background-color: #00aa00;}
.a5-1-35-42                     {text-decoration: blink; color: #ff44ff; background-color: #00aa00;}
.a5-1-36-42                     {text-decoration: blink; color: #44ffff; background-color: #00aa00;}
.a5-1-37-42                     {text-decoration: blink; color: white; background-color: #00aa00;}
.a5-0-30-43                     {text-decoration: blink; color: black; background-color: #aaaa00;}
.a5-0-31-43                     {text-decoration: blink; color: #aa0000; background-color: #aaaa00;}
.a5-0-32-43                     {text-decoration: blink; color: #00aa00; background-color: #aaaa00;}
.a5-0-33-43                     {text-decoration: blink; color: #aaaa00; background-color: #aaaa00;}
.a5-0-34-43                     {text-decoration: blink; color: #0000aa; background-color: #aaaa00;}
.a5-0-35-43                     {text-decoration: blink; color: #aa00aa; background-color: #aaaa00;}
.a5-0-36-43                     {text-decoration: blink; color: #00aaaa; background-color: #aaaa00;}
.a5-0-37-43                     {text-decoration: blink; color: #aaaaaa; background-color: #aaaa00;}
.a5-1-30-43                     {text-decoration: blink; color: #444444; background-color: #aaaa00;}
.a5-1-31-43                     {text-decoration: blink; color: #ff4444; background-color: #aaaa00;}
.a5-1-32-43                     {text-decoration: blink; color: #44ff44; background-color: #aaaa00;}
.a5-1-33-43                     {text-decoration: blink; color: #ffff44; background-color: #aaaa00;}
.a5-1-34-43                     {text-decoration: blink; color: #4444ff; background-color: #aaaa00;}
.a5-1-35-43                     {text-decoration: blink; color: #ff44ff; background-color: #aaaa00;}
.a5-1-36-43                     {text-decoration: blink; color: #44ffff; background-color: #aaaa00;}
.a5-1-37-43                     {text-decoration: blink; color: white; background-color: #aaaa00;}
.a5-0-30-44                     {text-decoration: blink; color: black; background-color: #0000aa;}
.a5-0-31-44                     {text-decoration: blink; color: #aa0000; background-color: #0000aa;}
.a5-0-32-44                     {text-decoration: blink; color: #00aa00; background-color: #0000aa;}
.a5-0-33-44                     {text-decoration: blink; color: #aaaa00; background-color: #0000aa;}
.a5-0-34-44                     {text-decoration: blink; color: #0000aa; background-color: #0000aa;}
.a5-0-35-44                     {text-decoration: blink; color: #aa00aa; background-color: #0000aa;}
.a5-0-36-44                     {text-decoration: blink; color: #00aaaa; background-color: #0000aa;}
.a5-0-37-44                     {text-decoration: blink; color: #aaaaaa; background-color: #0000aa;}
.a5-1-30-44                     {text-decoration: blink; color: #444444; background-color: #0000aa;}
.a5-1-31-44                     {text-decoration: blink; color: #ff4444; background-color: #0000aa;}
.a5-1-32-44                     {text-decoration: blink; color: #44ff44; background-color: #0000aa;}
.a5-1-33-44                     {text-decoration: blink; color: #ffff44; background-color: #0000aa;}
.a5-1-34-44                     {text-decoration: blink; color: #4444ff; background-color: #0000aa;}
.a5-1-35-44                     {text-decoration: blink; color: #ff44ff; background-color: #0000aa;}
.a5-1-36-44                     {text-decoration: blink; color: #44ffff; background-color: #0000aa;}
.a5-1-37-44                     {text-decoration: blink; color: white; background-color: #0000aa;}
.a5-0-30-45                     {text-decoration: blink; color: black; background-color: #aa00aa;}
.a5-0-31-45                     {text-decoration: blink; color: #aa0000; background-color: #aa00aa;}
.a5-0-32-45                     {text-decoration: blink; color: #00aa00; background-color: #aa00aa;}
.a5-0-33-45                     {text-decoration: blink; color: #aaaa00; background-color: #aa00aa;}
.a5-0-34-45                     {text-decoration: blink; color: #0000aa; background-color: #aa00aa;}
.a5-0-35-45                     {text-decoration: blink; color: #aa00aa; background-color: #aa00aa;}
.a5-0-36-45                     {text-decoration: blink; color: #00aaaa; background-color: #aa00aa;}
.a5-0-37-45                     {text-decoration: blink; color: #aaaaaa; background-color: #aa00aa;}
.a5-1-30-45                     {text-decoration: blink; color: #444444; background-color: #aa00aa;}
.a5-1-31-45                     {text-decoration: blink; color: #ff4444; background-color: #aa00aa;}
.a5-1-32-45                     {text-decoration: blink; color: #44ff44; background-color: #aa00aa;}
.a5-1-33-45                     {text-decoration: blink; color: #ffff44; background-color: #aa00aa;}
.a5-1-34-45                     {text-decoration: blink; color: #4444ff; background-color: #aa00aa;}
.a5-1-35-45                     {text-decoration: blink; color: #ff44ff; background-color: #aa00aa;}
.a5-1-36-45                     {text-decoration: blink; color: #44ffff; background-color: #aa00aa;}
.a5-1-37-45                     {text-decoration: blink; color: white; background-color: #aa00aa;}
.a5-0-30-46                     {text-decoration: blink; color: black; background-color: #44ffff;}
.a5-0-31-46                     {text-decoration: blink; color: #aa0000; background-color: #44ffff;}
.a5-0-32-46                     {text-decoration: blink; color: #00aa00; background-color: #44ffff;}
.a5-0-33-46                     {text-decoration: blink; color: #aaaa00; background-color: #44ffff;}
.a5-0-34-46                     {text-decoration: blink; color: #0000aa; background-color: #44ffff;}
.a5-0-35-46                     {text-decoration: blink; color: #aa00aa; background-color: #44ffff;}
.a5-0-36-46                     {text-decoration: blink; color: #00aaaa; background-color: #44ffff;}
.a5-0-37-46                     {text-decoration: blink; color: #aaaaaa; background-color: #44ffff;}
.a5-1-30-46                     {text-decoration: blink; color: #444444; background-color: #44ffff;}
.a5-1-31-46                     {text-decoration: blink; color: #ff4444; background-color: #44ffff;}
.a5-1-32-46                     {text-decoration: blink; color: #44ff44; background-color: #44ffff;}
.a5-1-33-46                     {text-decoration: blink; color: #ffff44; background-color: #44ffff;}
.a5-1-34-46                     {text-decoration: blink; color: #4444ff; background-color: #44ffff;}
.a5-1-35-46                     {text-decoration: blink; color: #ff44ff; background-color: #44ffff;}
.a5-1-36-46                     {text-decoration: blink; color: #44ffff; background-color: #44ffff;}
.a5-1-37-46                     {text-decoration: blink; color: white; background-color: #44ffff;}
.a5-0-30-47                     {text-decoration: blink; color: black; background-color: #aaaaaa;}
.a5-0-31-47                     {text-decoration: blink; color: #aa0000; background-color: #aaaaaa;}
.a5-0-32-47                     {text-decoration: blink; color: #00aa00; background-color: #aaaaaa;}
.a5-0-33-47                     {text-decoration: blink; color: #aaaa00; background-color: #aaaaaa;}
.a5-0-34-47                     {text-decoration: blink; color: #0000aa; background-color: #aaaaaa;}
.a5-0-35-47                     {text-decoration: blink; color: #aa00aa; background-color: #aaaaaa;}
.a5-0-36-47                     {text-decoration: blink; color: #00aaaa; background-color: #aaaaaa;}
.a5-0-37-47                     {text-decoration: blink; color: #aaaaaa; background-color: #aaaaaa;}
.a5-1-30-47                     {text-decoration: blink; color: #444444; background-color: #aaaaaa;}
.a5-1-31-47                     {text-decoration: blink; color: #ff4444; background-color: #aaaaaa;}
.a5-1-32-47                     {text-decoration: blink; color: #44ff44; background-color: #aaaaaa;}
.a5-1-33-47                     {text-decoration: blink; color: #ffff44; background-color: #aaaaaa;}
.a5-1-34-47                     {text-decoration: blink; color: #4444ff; background-color: #aaaaaa;}
.a5-1-35-47                     {text-decoration: blink; color: #ff44ff; background-color: #aaaaaa;}
.a5-1-36-47                     {text-decoration: blink; color: #44ffff; background-color: #aaaaaa;}
.a5-1-37-47                     {text-decoration: blink; color: white; background-color: #aaaaaa;}
.

   foreach (split("\n", $STYLE)) {
	s/\x0a?\x0d/\n/g;
	/^([^\s]*)\s*(.*)$/;
	$styles{$1}=$2;
#        $styles{$key}=~s/^\{//;
   }
}

sub ansi2html {
    init();
    return "<PRE><FONT face=\"fixedsys, lucida console, terminal, vga, monospace\"><FONT color=\"#aaaaaa\">".
    "<span style=\"{letter-spacing: 0; font-size: 12pt;}\">".&parseansi(shift)."</span></font></PRE>";
}


sub parseansi  {
	$text=$_[0];
	$strpos=0;
	$new_text='';
	$text=~s/\x0d?\x0a/\x0d/g;
#        $text=~s/\x0a/\x0d/g;
#        $text=~s/\n\x1b\[A\x1b\[[0-9]*C//gs;
	$text=~s/^.*\x1b\[1;1H//gs;
	$text=~s/^.*\x1b\[2J//gs;
	$text=~s/\x1b\[D/\x08/g;
	$text=~s/\x1b\[([0-9]*)D/substr($backspaces,0,$1)/ge;
	# Wrap text at 80 chars... there's gotta be an easier way of doing this
	$line_pos=0;
	while ($strpos<length($text))  {
		$char=substr($text,$strpos,1);
		if ($char=~/\x1b/)  {
			$ansi_code='';
			until ($char =~ /[a-zA-Z]/ or $strpos > length($text))  {
				$ansi_code.=$char;
				$strpos += 1;
				$char=substr($text,$strpos,1);
			}
			$ansi_code.=$char;
			if ($ansi_code=~/\x1b\[([0-9]*)C/)  {
				$line_pos+=$1;
				$this_line.=substr($nbspaces,1,$1);
				$new_text.=substr($nbspaces,1,$1);
			}
			else  {
				$new_text.=$ansi_code;
			}
		}
		elsif ($char=~/\x08/)  {
			$line_pos-=1;
			$new_text.=$char;
		}
		elsif ($char=~/\x0d/)  {
			$strpos+=1;
			if ($strpos<length($text))  {
				$ansi_code='';
				$char=substr($text,$strpos,1);
				if ($char=~/\x1b/)  {
					until ($char =~ /[a-zA-Z]/ or $strpos > length($text))  {
						$ansi_code.=$char;
						$strpos += 1;
						$char=substr($text,$strpos,1);
					}
					$ansi_code.=$char;
					if ($ansi_code eq "\x1b[A")  {
						$ansi_code='';
						$strpos+=1;
						$char=substr($text,$strpos,1);
						if ($char eq "\x1b")  {
#                                                        $new_text.="Bonk!\n";
							until ($char =~ /[a-zA-Z]/ or $strpos > length($text))  {
								$ansi_code.=$char;
								$strpos += 1;
								$char=substr($text,$strpos,1);
							}
							$ansi_code.=$char;
							if ($ansi_code=~/\x1b\[([0-9]+)C/)  {
#                                                                $new_text.="Bork!\n";
								$new_text.=substr($nbspaces,0,$1-$line_pos);
								$line_pos = $1;
							}
							else  {
								$new_text.=$ansi_code;
							}
						}
						else  {
							$this_line=$char;
							$new_text.="\x0d$char";
							$line_pos=1;
						}
					}
					elsif ($ansi_code=~/\x1b\[([0-9]*)C/)  {
						$line_pos=$1;
						$this_line=substr($nbspaces,1,$line_pos);
						$new_text.="\x0d$this_line";
					}
					else  {
						$new_text.="\x0d$ansi_code";
						$line_pos=0;
						$this_line='';
					}
				}
				else  {
					$new_text.="\x0d";
					$line_pos=0;
					$this_line='';
					$strpos-=1;
				}
			}
			else  {
				$new_text.="\x0d";
				$line_pos=0;
				$this_line='';
				$strpos-=1;
			}
		}
		else  {
			$this_line.=$char;
			$line_pos+=1;
			$new_text.=$char;
		}
		if ($line_pos>79)  {
#                        print "$line_pos\n";
#                        print "$this_line\n";
			$this_line='';
			$line_pos=0;
			$new_text.="\x0d";
			$strpos+=1;
			if ($strpos<length($text))  {
				$char=substr($text,$strpos,1);
				if ($char ne "\x0d")  {
					$strpos-=1;
				}
			}
		}
		$strpos+=1;
	}
	$text=$new_text;
	$new_text='';
#        $show_progress=$text;
#        $show_progress=~s/\x0d/\n/g;
#        print $show_progress;
	$text=~s/\x1b\[C/ /g;
	$text=~s/\x1b\[([0-9]*)C/substr($nbspaces,0,$1)/ge;
	while ($text=~s/[^\x0d\x08]\x08//g)  {}
	$text=~s/\x08//g;
	$text=~s/\x0d/\n/g;
	$text=~s/\</&lt;/g;
	$text=~s/\>/&gt;/g;
#        $text=~s/\x1b\[C/$blackspan $endspan/g;
#        $text=~s/\x1b\[([0-9]*)C/$blackspan.substr($nbspaces,0,$1).$endspan/ge;
        $text=~s/ /&nbsp;/g;
	$text=~s/\x1b\[K//g;
	$text=~s/\x1b\[A//g;
	$text=~s/([\x7f-\xff])/$ascii{ord($1)}/ge;
	$text=~s/\x1b\[[^a-zA-Z]*[a-ln-zA-Z]//g;
	$strpos=0;
	while ($strpos<length($text))  {
		$char=substr($text,$strpos,1);
		if ($char ne "\x1b")  {
			if ($char eq '(' && substr($text,$strpos+1,1) ne "'" && substr($text,$strpos+1,1) ne '1')  {
				$styles{".a$blink-$attr-$foreground-$background"}=~/(?<=[\s{])color: ([^;]*); /;
				$html_color=$1;
				$html_style=$styles{".a$blink-$attr-$foreground-$background"};
				$html_style=~s/(?<=[\s{])color: ([^;]*);//g;
				$new_text.="</font><FONT color=\"$html_color\">" if ($old_html_color ne $html_color);
				$new_text.="</SPAN><SPAN style=\"$html_style\">" if ($html_style ne $old_style);
				$old_style=$html_style;
				$old_html_color=$html_color;
			}
			$new_text .= $char;
			$strpos+=1;
		}
		else  {
			$code_length=1;
			while (substr($text,$strpos+$code_length,1) ne 'm' && $strpos+$code_length-2<length($text))  {
#                                print $strpos," - ",$code_length," - ",length($text),"\n";
				$code_length+=1;
			}
			$ansi_code=substr($text,$strpos,$code_length+1);
			$attributes=$ansi_code;
			$attributes=~s/[^0-9;]//g;
			@attributes=split(/;/,$attributes);
			foreach $attribute (@attributes)  {
				if ($attribute eq '0')  {
					$attr='0';
					$foreground='37';
					$background='40';
					$blink='';
				}
				elsif ($attribute eq '1')  {
					$attr='1';
				}
				elsif ($attribute eq '5')  {
					$blink='5';
				}
				elsif ($attribute=~m/^3[0-7]$/)  {
					$foreground=$attribute;
				}
				elsif ($attribute=~m/^4[0-7]$/)  {
					$background=$attribute;
				}
			}
			$styles{".a$blink-$attr-$foreground-$background"}=~/(?<=[\s{])color: ([^;]*);/;
			$html_color=$1;
			$html_style=$styles{".a$blink-$attr-$foreground-$background"};
			$html_style=~s/(?<=[\s{])color: ([^;]*);//g;
                        $new_text.="</font><FONT color=\"$html_color\">" if (defined $html_color && $old_html_color ne $html_color);
			$new_text.="</SPAN><SPAN style=\"$html_style\">" if (defined $html_style && $html_style ne $old_style);
			$old_style=$html_style if defined $html_style;
			$old_html_color=$html_color if defined $html_color;
			$strpos += length($ansi_code);
		}
	}
#        $new_text=~s/\n/&nbsp;<BR>/g;
#        $new_text=~s/\<BR>\<BR>/<BR>&nbsp;<BR>/g;
	$new_text;
}

sub dontparseansi  {
	$text=$_[0];
	return $text;
}

1;

package Slash::OurNet::Standalone;

use CGI;
use base 'Exporter';

our @EXPORT = qw(
    getCurrentVirtualUser getCurrentForm getCurrentStatic slashDisplay
    getCurrentDB getUser getCurrentUser createEnvironment header
    titlebar footer
);

sub header {
    print "Content-Type: text/html\n\n";
    print "<html><head><title>@_</title><body>";
}

sub footer {
    print "<hr>@_</body></html>";
}

sub titlebar {
    print "<h1>@_</h1>";
}
sub getCurrentVirtualUser {
    return 'autrijus';
}

sub getCurrentForm {
    return { CGI->Vars() };
}

sub getCurrentStatic {
}

sub getCurrentDB {
}

sub getUser {
}

sub getCurrentUser {
}

sub slashDisplay {
    print "@_";
}

sub createEnvironment {
}

1;

package Slash::OurNet::Standalone;

use CGI;
use base 'Exporter';

@EXPORT = qw(
    getCurrentVirtualUser getCurrentForm getCurrentStatic slashDisplay
    getCurrentDB getUser getCurrentUser createEnvironment header
    titlebar footer
);

sub header {
    print "Content-Type: text/html\n\n";
    print "<html><head><title>@_</title><body>";
}

sub footer {
    print "<hr>@_</body></html>";
}

sub titlebar {
    print "<h1>@_</h1>";
}
sub getCurrentVirtualUser {
    return 'autrijus';
}

sub getCurrentForm {
    return { CGI->Vars() };
}

sub getCurrentStatic {
}

sub getCurrentDB {
}

sub getUser {
}

sub getCurrentUser {
}

sub slashDisplay {
    print "@_";
}

sub createEnvironment {
}

1;
