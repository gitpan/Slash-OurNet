# $File: //depot/metalist/src/plugins/OurNet/OurNet.pm $ $Author: clkao $
# $Revision: #4 $ $Change: 582 $ $DateTime: 2002/08/05 09:52:13 $

package Slash::OurNet;

our $VERSION = '1.3';
our @ISA = qw/Slash::DB::Utility Slash::DB::MySQL/ if $ENV{SLASH_USER};

use strict;
use warnings;
use base 'Locale::Maketext';
use Locale::Maketext::Lexicon {
    en    => [Gettext => 'en.po'],
    zh_tw => [Gettext => 'zh_tw.po'],
};

use Text::Wrap;
use Date::Parse;
use Date::Format;
use OurNet::BBS;

if ($ENV{SLASH_USER}) { eval << '.';
    use Slash;
    use Slash::DB;
    use Slash::Display;
    use Slash::Utility;
.
} else { eval << '.';
    Slash::OurNet::Standalone->import();
    sub timeCalc {
	return scalar localtime;
    }

    sub getCurrentUser {
	my ($self, $key) = @_;
	return unless $key;

	if ($key eq 'is_anon') {
		    return ($key eq $Slash::OurNet::DefaultUser);
	}
	elsif ($key eq 'off_set') {
		    require Time::Local;
		    return ((timegm(localtime) - timegm(gmtime)) / 3600);
	}
    }
.
	die $@ if $@;
}

no warnings qw/once redefine/;

$Text::Wrap::columns = 75;
$OurNet::BBS::Client::NoCache = 1; # avoids bloat

our ($TopClass, $MailBox, $Organization, @Connection, $SecretSigils, 
     $BoardPrefixLength, $GroupPrefixLength, $Strip_ANSI, $Use_RealEmail,
     $Thread_Prev, $Date_Prev, $Thread_Next, $Date_Next, $Language, $Colors,
     $DefaultUser);

our %CachedTop;

(my $pathname = $0) =~ s/.\w+$/.conf/; do $pathname;

sub loc {
    __PACKAGE__->get_handle->maketext(@_);
}

sub new {
    return unless @_; # to satisfy pudge's automation scripts
    my ($class, $name) = splice(@_, 0, 2);

    no warnings 'once';
    my $self = {
	bbs => OurNet::BBS->new(@_),
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
    $body = wrap('','', $body) if $body and length($body) > 75;

	no warnings 'uninitialized';
    my $offset = sprintf("%+0.4d", getCurrentUser('off_set') / 36);
    $offset =~ s/([1-9][0-9]|[0-9][1-9])$/$1 * 0.6/e;

    if ($Use_RealEmail and $ENV{SLASH_USER}) {
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

    $error .= loc('Please enter a subject.<hr>')
	unless (length($article->{header}));
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
	$artgrp = ($chunk =~ /^\d+$/ ? $artgrp->[$chunk] : $artgrp->{$chunk});
    }

    # number OR name
    my $article	= ($artid =~ /^\d+$/ ? $artgrp->[$artid] : $artgrp->{$artid});

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
	next if $i > $size - 1;
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
    $board = (split('/', $group))[-1] unless $board;
    my $boards = $self->{bbs}{groups}{$board}{groups};

    my ($thisgroup, $title, $bm, $etc);

    if ($board eq $TopClass) {
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
    my $title2 = substr($title, $GroupPrefixLength);
    $title2 =~ s|^[^/]+/\s+||; # XXX: melix special case

    my $message = "| $board | ".
		    ( $title2 || $Organization) .
		($bm ? " | $bm |<hr>" : ' |<hr>');
    $message .= $etc if defined $etc;

#    $boards->refresh;

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

	if (UNIVERSAL::isa($_, 'UNIVERSAL')) {
	    $type   = ($_->REF =~ /Group/) ? 'group' : 'article'; 
	    $title  = $_->{title};
	    $title  =~ s/\x1b\[[\d\;]*m//g; 
	    $date   = $_->{date},
	    $author = $_->{author};
	    $author =~ s/(?:\.bbs)?\@.+//;
	    $board  = $board || $_->board;
	    $artid  = $_->name;
	}
	else { # deleted article
	    $type   = 'deleted';
	    $title  = loc('<< This article has been deleted >>');
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
	    $board = $_->board or next;
	    if ($etc = $_->{etc_brief}) {
		$etc = (split(/\n\n+/, $etc, 2))[1];
		$etc =~ s/\n+/\n/g;
	    }
	    $bm = $_->{bm},
	    $title = substr($_->{title}, $BoardPrefixLength) or next;
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
	$body = sprintf(loc("*) %s wrote:")."\n: %s", $article->{header}{From}, $body);
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

	$body =~ s/<TT><A&nbsp;HREF/<A HREF/g;
	$body =~ s/<\/TT>//g;

	$body = << ".";
<font face="fixedsys, lucida console, terminal, vga, monospace">
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

require CGI;
use base 'Exporter';

our @EXPORT = qw(
    getCurrentVirtualUser getCurrentForm getCurrentStatic slashDisplay
    getCurrentDB getUser getCurrentUser createEnvironment header
    titlebar footer SetCookie
);

our %Sessions;

sub header {
    print "<title>@_</title>";
}

sub footer {
    print "<hr>@_</body></html>";
}

sub titlebar {
    shift;
    print "<h3>@_</h3>";
}
sub getCurrentVirtualUser {
    return 'guest';
}

sub getCurrentForm {
    my $flavor = 'OurNetBBS';
    my ($cookie);

    require SDBM_File;
    if (!%Sessions) {
	use Fcntl;
	tie(%Sessions, 'SDBM_File', 'ournet.db', O_RDWR|O_CREAT, 0666);
    }

    require CGI::Cookie;

    my $CGI = CGI->new;
    my $vars = {%{$CGI->Vars}};
    $CGI->delete_all;

    if (exists $vars->{op} and $vars->{op} eq 'userlogin') {
	my ($uid, $pwd) = @{$vars}{qw/unickname upasswd/};
	unless ( (scalar keys %{Slash::OurNet::ALLBBS})) {
	    warn "no available bbs object";
    		$Slash::OurNet::ALLBBS{guest} ||= Slash::OurNet->new(
		    getCurrentVirtualUser(), (@Connection,  () ));
	}

	my $bbs = (values(%{Slash::OurNet::ALLBBS}))[0]->{bbs}; # XXX
	if (exists $bbs->{users}{$uid}) {
	    my $user = $bbs->{users}{$uid};
	    my $crypted = $user->{passwd};
	    if (crypt($pwd, $crypted) eq $crypted) {
		my $val = SetCookie();
		$Sessions{$val} = $vars->{unickname};
		$cookie = CGI::Cookie->new(-value => $val);
	    }
	}
    }
    else {
	my %cookies = CGI::Cookie->fetch;
	$cookie = $cookies{$flavor} if exists $cookies{$flavor};
    }

    if (ref($cookie) and $Sessions{$cookie->value}) {
        if (exists $vars->{op} and $vars->{op} eq 'userclose') {
	    delete $Sessions{$cookie->value};
        }
	else {
	    my $sescook = CGI::Cookie->new(
		-name    => $flavor,
		-value   =>  $cookie->value,
		-expires =>  '+1h',
		-domain  =>  $cookie->domain
	    );

	    print "Set-Cookie: $sescook\n";
	    $vars->{uid} = $Sessions{$cookie->value};
	}
    }

    print "Content-Type: text/html";
    print "; charset=big5" if $Slash::OurNet::Language eq 'zh_TW';
    print "\n\n";

    return $vars;
}

sub getCurrentStatic {
}

sub getCurrentDB {
    my $a;
    return bless \$a, __PACKAGE__;
}

sub getUser {
    my ($self, $uid, $key) = @_;

    return $uid if $key eq 'nickname';
    if ($key eq 'fakeemail') {
	my $bbs = $Slash::OurNet::ALLBBS{$uid}{bbs};
	my $user = $bbs->{users}{$uid};
	return $user->{username};
    }
}

sub getCurrentUser {
    my ($self, $key) = @_;
    return unless $key;

    if ($key eq 'is_anon') {
		return ($key eq $Slash::OurNet::DefaultUser);
    }
    elsif ($key eq 'off_set') {
		require Time::Local;
		return ((timegm(localtime) - timegm(gmtime)) / 3600);
    }
}

my $template;

sub slashDisplay {
    my ($file, $vars) = @_;
    my $path = exists $ENV{SCRIPT_FILENAME} ? $ENV{SCRIPT_FILENAME} : $0;
    $path =~ s|[\\/][^\\/]+$|/templates| or $path = './templates';
    $path = "$path/$file;ournet;default";

    $vars->{user} = $Slash::OurNet::Colors;
    $vars->{user}{nickname} = $vars->{username};
    $vars->{user}{fakeemail} = $vars->{usernick};
    $vars->{user}{is_anon}  = ($vars->{username} eq $DefaultUser);

    local $/;
    open my $fh, $path or die "cannot open template: $path ($!)";
    my $text = <$fh>;
    $text =~ s/.*\n__template__\n//s;
    $text =~ s/__seclev__\n.*//s;

    my $ah = Slash::OurNet->get_handle;

    require Template;
    $template ||= Template->new(
	FILTERS		=> {
	    l		=> [ sub { $ah->maketext(@_) } ],
	},
	VARIABLES	=> {
	    loc		=> sub { $ah->maketext(@_) },
	},
    );
    return $template->process(\$text, $vars) || die($template->error);
}

sub createEnvironment {
}

sub SetCookie {
    my $flavor  = shift || 'OurNetBBS';
    my $sescook = CGI::Cookie->new(
	-name    => $flavor,
        -value   =>  crypt(time, substr(CGI::remote_host(), -2)),
        -expires =>  '+1h'
    );

    print "Set-Cookie: $sescook\n";
    return $sescook->value;
}

1;
