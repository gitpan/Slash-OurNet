# $File: //member/autrijus/slash-ournet/ournet.pl $ $Author: autrijus $
# $Revision: #13 $ $Change: 1360 $ $DateTime: 2001/07/01 06:41:24 $

use strict;
use warnings;
use Slash::OurNet;

no warnings 'redefine';

local $| = 1;

if ($ENV{SLASH_USER}) { eval << '.';
    use Slash;
    use Slash::DB;
    use Slash::Display;
    use Slash::Utility;
.
} else { eval << '.';
    Slash::OurNet::Standalone->import();
.
}

our ($TopClass, $TopArticles, $NewId, $MailBox, $Customize, $BugReport,
     $MainMenu, $Organization, @Connection, $RootDisplay, $DefaultUser,
     $DefaultNick, $Login);

(my $pathname = $0) =~ s/.pl$/.conf/; do $pathname;

our $bbs;

sub main {
    my %ops = (
	login 		=> \&displayLogin,
	newid		=> \&displayNewId,
	group		=> \&displayGroup,
	board		=> \&displayBoard,
	article		=> \&displayArticle,
	article_edit	=> \&editArticle,
	default		=> \&displayDefault,
	reply		=> \&editArticle,
    );

    $ops{mail} = \&displayMailBox if $MailBox;
    $ops{top}  = \&displayTop	  if $TopArticles;

    my %safe = map { $_ => 1 } 
	qw/login newid group board article top default/;

    $bbs ||= $cached::bbs ||=
	Slash::OurNet->new(getCurrentVirtualUser(), @Connection);

    my $form = getCurrentForm();
    my $constants = getCurrentStatic();

    my $op = $form->{'op'};
    $op = 'default' unless defined $op and $ops{$op};

    if (getCurrentUser('is_anon')) {
	$op = 'default' unless $safe{$op};
    }

    my $uid = $form->{'uid'};
    my $slashdb = getCurrentDB();
    my $name = $slashdb->getUser($form->{uid}, 'nickname') 
	if $form->{uid};
    $name ||= getCurrentUser('nickname');
    $name ||= $DefaultUser;

    my $nick = $slashdb->getUser($form->{uid}, 'fakeemail') 
	if $form->{uid};
    $nick ||= getCurrentUser('fakeemail');
    $nick ||= $DefaultNick;

    header("$Organization - $name");
    titlebar("100%","$Organization - $name");

    slashDisplay('navigation', { 
	user       => $name,
	newid	   => $NewId,
	login	   => $Login,
	mailbox    => $MailBox,
	bugreport  => $BugReport,
	customize  => $Customize,
	topclass   => $TopClass,
	slash_user => $ENV{SLASH_USER},
    });

    $ops{$op}->($form, $bbs, $constants, $name, $nick);

    footer();
}

sub displayLogin {
    if ($ENV{SLASH_USER}) {
	# shouldn't be here unless Anonymous Coward is turned off.
	print "You haven't logged in. Please press login in the left side bar.";
    }
    else {
	slashDisplay('login', {});
    }
}

sub displayDefault {
    displayGroup(@_, '', $TopClass);

    if ($TopArticles) {
	print "<hr>";
	displayTop(@_);
    }
}

sub displayTop {
    my ($form, $bbs, $constants, $name) = @_;
    my $articles = $bbs->top;

    slashDisplay('board', {
	articles => $articles, 
	display  => 'top',
	message  => $TopArticles,
	topclass => $TopClass,
    });
}

sub displayGroup {
    my ($form, $bbs, $constants, $name, $nick, $group, $board) = @_;
    $group ||= $form->{group};
    $board ||= $form->{board};

    my ($boards, $message) = $bbs->group($group, $board);

    slashDisplay('group', { 
	board	=> $board,
	group	=> $group,
	boards	=> $boards, 
	display	=> ($form->{board} || $RootDisplay),
	message	=> (
	    ($form->{board} and $form->{board} ne $TopClass) 
		? $message : $MainMenu,
	),
	topclass => $TopClass,
    });
}

sub displayBoard {
    my ($form, $bbs, $constants, $name) = @_;
    unless ($bbs->{bbs}{boards}{$form->{board}}) {
	print 'No such board.<hr>';
	print '<div align="center">[ <a href="ournet.pl">Back to main menu</a> ]</div>';
	return;
    }

    my $brd = $bbs->{bbs}{boards}{$form->{board}};
    $form->{child} ||= 'articles';

    my ($message, $pages, $articles) 
	= $bbs->board(@{$form}{qw/group board child begin/});

    slashDisplay('board', { 
	group	 => $form->{group},
	child	 => $form->{child},
	board	 => $form->{board},
	articles => $articles, 
	pages    => $pages, 
	display	 => $form->{board},
	message  => $message,
	topclass => $TopClass,
	archives_count => $#{$brd->{archives}},
	articles_count => $#{$brd->{articles}},
    });
}

sub displayMailBox {
    my ($form, $bbs, $constants, $name) = @_;
    my ($message, $pages, $articles) 
	= $bbs->board('', $name, 'mailbox', $form->{begin});
    
    slashDisplay('board', {
	group	 => '',
	child	 => 'mailbox',
	board	 => $name,
	articles => $articles, 
	pages    => $pages, 
	display	 => 'mailbox',
	message  => $message,
	topclass => $TopClass,
	archives_count => 0,
    });
}

sub editArticle {
    my ($form, $bbs, $constants, $name, $nick) = @_;
    my $message = '';
    my $article;

    my $mode = $form->{reply} ? 'reply' : $form->{name} ? 'edit' : 'new';

    if ($form->{state} or $mode eq 'new') {
	# insert it, take message, return to board
	($article, $message) = $bbs->article_save(
	    @{$form}{qw/group board child name reply title body state/}, 
	    $name, $nick,
	);

	# back to board if nothing's wrong, otherwise fall through
	return displayBoard(@_) unless $message; 
    }
    else {
	$article = ($bbs->article(
	    @{$form}{qw/group board child name reply/})
	)[0]; # ignore related

	$article->{header}{From} = "$name ($nick)";

	my $offset = sprintf("%+0.4d", getCurrentUser('off_set') / 36);
	$offset =~ s/([1-9][0-9]|[0-9][1-9])$/$1 * 0.6/e;
	$article->{header}{Date} = timeCalc(
	    scalar localtime, "%a %b %e %H:%M:%S $offset %Y"
	);
    }

    $article->{header}{Subject} =~ s/^(?!Re:)/Re: / if $mode eq 'reply';

    slashDisplay('article', {
	group	=> $form->{group},
	child	=> $form->{child},
	board   => $form->{board},
	name   	=> $form->{name},
	article => $article, # undef if $mode eq 'new'
	message	=> $message,
	display	=> 'edit',
    });
}

sub displayArticle {
    my ($form, $bbs, $constants) = @_;

    my ($article, $related)
	= $bbs->article(@{$form}{qw/group board child name/});

    slashDisplay('article', {
	group	=> $form->{group},
	child	=> $form->{child},
	board   => $form->{board},
	name   	=> $form->{name},
	article => $article, 
	display	=> 'display',
	related	=> $related,
    });
}

createEnvironment();
main();

1;

