# $File: //member/autrijus/slash-ournet/ournet.pl $ $Author: autrijus $
# $Revision: #13 $ $Change: 1360 $ $DateTime: 2001/07/01 06:41:24 $

package Slash::OurNet;

our $VERSION = '1.2';
our @ISA = qw/Slash::DB::Utility Slash::DB::MySQL/ if $ENV{SLASH_USER};

use strict;
use warnings;

use Text::Wrap;
use Date::Parse;
use Date::Format;
use OurNet::BBS;

use Slash;
use Slash::DB;
use Slash::Display;
use Slash::Utility;

no warnings qw/once redefine/;

$Text::Wrap::columns = 75;
$OurNet::BBS::Client::NoCache = 1; # avoids bloat

our ($TopClass, $MailBox, $Organization, @Connection, $SecretSigils, 
     $BoardPrefixLength, $GroupPrefixLength, $Strip_ANSI, $Use_RealEmail,
     $Thread_Prev, $Date_Prev, $Thread_Next, $Date_Next);

our %CachedTop;

(my $pathname = $0) =~ s/.pl$/.conf/; do $pathname;

sub new {
    my ($class, $name) = splice(@_, 0, 2);
    no warnings 'once';
    my $self = {
	bbs => $cached::BBS{"@_"} ||= OurNet::BBS->new(@_),
	virtual_user => $name,
    };

    return bless($self, $class);
}

sub article_save {
    my ($self, $group, $board, $child, $artid, $reply, 
        $title, $body, $state, $name, $nick) = @_;

    $child ||= 'articles';
    my $artgrp = $self->{bbs}{boards}{$board};

    # honor 75-column tradition of legacy BBS systems
    $body = wrap('','', $body) if length($body) > 75;

    my $offset = sprintf("%+0.4d", getCurrentUser('off_set') / 36);
    $offset =~ s/([1-9][0-9]|[0-9][1-9])$/$1 * 0.6/e;

    if ($Use_RealEmail) {
	$name = getCurrentUser('realemail');
	$nick = getCurrentUser('nickname');
    }

    # we could ignore the $reply until a Reply-To header is supported
    my $article = {
	header	=> {
	    From    => "$name ($nick)",
	    Subject => $title || '',
	    Board   => $board,
	    Date    => timeCalc(
		scalar localtime, "%a %b %e %H:%M:%S $offset %Y"
	    ),
	},
	body	=> $body || '',
    };

    my $error; # error message

    $error .= 'Please enter a subject.<hr>' unless (length($article->{header}));
    $error = '&nbsp;' unless $state;

    $artgrp->{articles}{$artid || ''} = $article unless $error;

    return ($article, $error);
}

sub article {
    my ($self, $group, $board, $child, $artid, $reply) = @_;
    my (@related, $artgrp, $is_reply);

    # put $reply to $name and set flag for further processing
    $is_reply++ if !defined($artid) and defined($artid = $reply);
    return unless defined $artid; # happens when a new article's made

    $child ||= 'articles';
    $artgrp = $self->{bbs}{($child eq 'mailbox') ? 'users' : 'boards'}{$board};
    
    foreach my $chunk (split('/', $child)) {
	$artgrp = $artgrp->{$chunk};
    }

    my $article	= $artgrp->{$artid};

    my $related = $is_reply ? [] :  $self->related_articles(
	[ group => $group, board => $board, child => $child ],
	$artgrp, $article,
    ); # do not calculate related article during reply

    return ($self->mapArticle(
	$group, $board, $child, $artid, $article, $is_reply
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
	my ($type, $title, $date, $author, $board, $artid);

	if ($_) {
	    $type   = ($_->REF =~ /Group/) ? 'group' : 'article'; 
	    $title  = $_->{title};
	    $title  =~ s/\x1b\[[\d\;]*m//g; 
	    $date   = time2str('%m/%d', $_->mtime);
	    $author = $_->{author};
	    $board  = $board || $_->board;
	    $artid  = $_->name;
	}
	else { # deleted article
	    $type   = 'deleted';
	    $title  = '<< This article has been deleted >>';
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
	    name	=> $artid,
	    recno 	=> $recno,
	    articles_count	=> $type eq 'group' ? $#{$_} : 1,
	}
    } @_ ];
}

sub mapArticle {
    my ($self, $group, $board, $child, $artid, $article, $is_reply) = @_;
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
	name 	=> $artid,
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
	$body =~ s/\n: : ¡° .*//g;
	$body =~ s/: \n+/\n/g;
	$body = "*) $article->{header}{From} wrote:\n: $body";
    }
    elsif ($Strip_ANSI) {
	require HTML::FromText;

        $body =~ s/\x1b\[.*?[mJH]//g;
	$body = HTML::FromText::text2html(
	    $body,
	    metachars => 1,  urls      => 1,
	    email     => 1,  underline => 1,
	    lines     => 1,  spaces    => 1,
	);

	$body = << ".";
<font face="fixedsys, lucida console, terminal, vga, monospace" color="#e9e9e9">
$body
</font>
.
    }
    else {
	require HTML::FromANSI;
        $body = HTML::FromANSI::ansi2html($body);
    }

    return $body;
}

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
