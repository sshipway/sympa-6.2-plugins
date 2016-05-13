#============================================================= -*-Perl-*-
#
# Template::Plugin::Tracking
#
# DESCRIPTION
#   Template Toolkit plugin module for Sympa mailing lists
#   Provide tracking for mailmerge messages
#
# AUTHOR
#   Steve Shipway
#
# This plugin provides both functions for adding the tracking to mailmerged
# messages, and also the functions to query the database used by the web
# frontend.
#
#============================================================================
# 0.1 : first working version
# 0.2 : extra checks for when not in content-type=~/html/ and non-null return
#       more helpful comment code
#       multiple ways to seek out the message-id header content
#       better defaults for base_url etc
#       Tracking.unsubscribe function
# 0.3 : Support Sympa 6.1.21 and later with part.type instead of headers.content-type
# 0.4 : Fix unsubscribe function HTML detection test
# 0.5 : Remove trailing %0A from RCPT_ID
# 1.0 : Sympa 6.2 support
#============================================================================

package Sympa::Template::Plugin::Tracking;
use base 'Template::Plugin';
use Sys::Hostname;
use Digest::MD5;
use URI::Escape;
use strict;

our $VERSION   = 1.00;

sub load {
	my ($class, $context) = @_;
	return $class;
}

sub new {
	my ($class, $context, @args) = @_;

	# This increments by one for each link we track
	my  $LINK_ID = 1;
	# This is the ID for this message
	my  $MSG_ID = '';
	# This is the ID for this recipient
	my  $RCPT_ID = 'default';
	# The base tracking URL
	my  $BASE_URL = '/cgi-bin/track.cgi';
	# The mailing list address
	my  $LIST_NAME = 'default';

	eval { require Sympa::DatabaseManager; };

	if($args[0] and !ref $args[0] and $args[0]=~/^http/) {
		$BASE_URL = $args[0] ;
	} elsif( $context->{STASH}{'wwsympa_url'} ) {
		$BASE_URL = $context->{STASH}{'wwsympa_url'};
		$BASE_URL =~ s/sympa$//;
		$BASE_URL .= 'cgi-bin/track.cgi';
	} else {
		# Set up BASE_URL from info in the stash
		$BASE_URL = 'http://'.hostname().'/cgi-bin/track.cgi';
	}

	# Set up default list name
	if( $context->{STASH}{listname} ) { # for mail context
		$LIST_NAME = $context->{STASH}{listname}.'@'.$context->{STASH}{robot};
	} else {
		$LIST_NAME = "Unknown";
	}

	# Define MSG_ID based on message details as held in
	# the context.
	if($context->{STASH}{headers}{'message-id'}) {
		$MSG_ID = Digest::MD5::md5_base64($context->{STASH}{headers}{'message-id'});
	} elsif($context->{STASH}{'message-id'}) {
		$MSG_ID = Digest::MD5::md5_base64($context->{STASH}{'message-id'});
	} elsif($context->{STASH}{'messageid'}) {
		$MSG_ID = Digest::MD5::md5_base64($context->{STASH}{'messageid'});
	} else {
		$MSG_ID = "Unknown";
	}

	# The message subject
	my $SUBJECT = $context->{STASH}{headers}{'subject'} || 'None';

	if( defined $args[0] and ref $args[0] =~ /HASH/ ) {
		$MSG_ID = $args[0]->{msgid} if($args[0]->{msgid});
		$BASE_URL = $args[0]->{url} if($args[0]->{url});
		$SUBJECT = $args[0]->{subject} if($args[0]->{subject});
		$LIST_NAME = $args[0]->{list}.'@'.$context->{STASH}{robot} if($args[0]->{list});
	}

	$MSG_ID =~ s/[\/&?@%'"\\+]/_/g; # just in case

	# Define RCPT_ID for this recipient based on stash
	$RCPT_ID = $context->{STASH}{user}{escaped_email};
	$RCPT_ID = "unknown" if(!$RCPT_ID);
	$RCPT_ID =~ s/%0A//ig; # remove any trailing newlines

	# IF we are in message mode...
	# If MSG_ID not already in database, then do initial setup for this
	# write msgs=($MSG_ID,$subject,$LIST_NAME,NOW())
	if( $MSG_ID ) {
		my $sql = "INSERT into `tracking_msgs` (`msg_id`,`subject`,`list_name`,`sent`) VALUES(?,?,?,NOW())";
		my( $sdm ) = Sympa::DatabaseManager->instance();
		if( $sdm ) {
			my( $sth ) = $sdm->do_prepared_query($sql,$MSG_ID,$SUBJECT,$LIST_NAME);
		} 

		# Store it here, since filters cant see the object
		$context->{STASH}{Tracking} = { MSG_ID=>$MSG_ID,
		    RCPT_ID=>$RCPT_ID, LINK_ID=>1, BASE_URL=>$BASE_URL };

		# Define a new filter that can be used later
		# This filter handles general replacement of links with tracked links
		$context->define_filter('Tracking', [ \&track_ff => 1 ]);
	}

	return bless { _CONTEXT=>$context, SUBJECT=>$SUBJECT, MSG_ID=>$MSG_ID, 
		RCPT_ID=>$RCPT_ID, BASE_URL=>$BASE_URL, LIST_NAME=>$LIST_NAME, LINK_ID=>$LINK_ID
	}, $class;
}

##########################################################
# The below functions are used when in message mode

# Set up HTML for base tracking - 1px image link, etc
# [% Tracking.base %]
sub base {
	my($obj,@args) = @_;
	my($rv) = '';

	return $rv if(!$obj->{MSG_ID}); # not message mode
	if($obj->{_CONTEXT}{STASH}{'part'}) {
		return $rv if($obj->{_CONTEXT}{STASH}{'part'}{'type'}!~/html/);
	} else {
		return $rv if($obj->{_CONTEXT}{STASH}{'headers'}{'content-type'}!~/html/);
	}

	# Set up database entry for MSG_ID, RCPT_ID
	my $sql = "INSERT into `tracking_clicks` (`msg_id`,`rcpt_id`,`link_id`,`clicks`,`last_click`,`first_click`) VALUES(?,?,0,0,NULL,NULL)";

	my( $sdm ) = Sympa::DatabaseManager->instance();
	if(!$sdm) {
		$rv .= "<!-- ERR: Unable to contact database -->";
	} else {
		my( $sth ) = $sdm->do_prepared_query($sql,$obj->{MSG_ID},$obj->{RCPT_ID});
		if($sth) {
			if(! $sth->rows ) { # returns 0 for error, 0E0 (==true) for no rows affected
				$rv .= "<!-- ERR: Message seems to have already been sent?\n     ".$sth->errstr." -->\n";
			}
		} else {
			$rv .= "<!-- ERR: Unable to run query -->";
		}
	}


	# Base tracking links
	$rv = '<IMG SRC="'.$obj->{BASE_URL}.'/'.$obj->{MSG_ID}.'/'.$obj->{RCPT_ID}."\" WIDTH=1 HEIGHT=1 />\n";

	return $rv;
}
sub unsubscribe {
	my($obj,$msg) = @_;
	my($rv) = '';
	my($url);

	$url = $obj->{_CONTEXT}{STASH}{'wwsympa_url'}.'/auto_signoff/'.$obj->{_CONTEXT}{STASH}{'listname'}.'/'.$obj->{_CONTEXT}{STASH}{'user'}{'escaped_email'};

	return $rv if(!$url);
	if(($obj->{_CONTEXT}{STASH}{'part'} 
		and $obj->{_CONTEXT}{STASH}{'part'}{'type'}=~/html/)
		or $obj->{_CONTEXT}{STASH}{'headers'}{'content-type'}=~/html/) {
	   $msg = "Click here to unsubscribe from this list" if(!$msg);
	   $rv = "<A HREF=\"$url\">$msg</A>";
	} else {
	   $msg = "To unsubscribe from this list, visit" if(!$msg);
	   $rv = "$msg $url";
	}
	return $rv;
}

# Replace links with tracked links
sub _track_links {
	my($text, $context) = @_;
	my($linkdest);
	my(%links) = ();
	my($MSG_ID) = $context->{STASH}{Tracking}{MSG_ID};
	my($RCPT_ID) = $context->{STASH}{Tracking}{RCPT_ID};
	my($linksql)  = "INSERT into `tracking_links`  (`msg_id`,`link_id`,`url`) VALUES(?,?,?)";
	my($clicksql) = "INSERT into `tracking_clicks` (`msg_id`,`link_id`,`rcpt_id`,`clicks`,`last_click`,`first_click`) VALUES(?,?,?,0,NULL,NULL)";
	my($rows) = 0;
	my($LINK_ID) = $context->{STASH}{Tracking}{LINK_ID};
	my($BASE_URL) = $context->{STASH}{Tracking}{BASE_URL};
	my($lsth,$csth) = (undef,undef);

	return $text if(!$MSG_ID or !$RCPT_ID); # not message mode or not supported
	if($context->{STASH}{'part'}) {
		return $text if($context->{STASH}{'part'}{'type'}!~/html/);
	} else {
		return $text if($context->{STASH}{'headers'}{'content-type'}!~/html/);
	}

	# Check we have a working database connection
	my( $sdm ) = Sympa::DatabaseManager->instance();
	if(!$sdm) {
 		$text .= "\n<!-- ERROR: No database connection. -->\n";
		return $text;
	}

	# Identify all the links in the text block
	$LINK_ID = 1 if(!$LINK_ID);
	while( $text =~ s/href="?(https?:\/\/[^\s">]+)"?/href="\001$LINK_ID\001"/i  ) {
		$links{$LINK_ID}=$1;
		$LINK_ID += 1;
	}
	foreach my $lnk ( keys %links ) {
		$linkdest = $links{$lnk};
		#$text .= "<!-- adding $lnk,$linkdest -->\n";
		# Save to database if not already there links=($MSG_ID,$lnk,$linkdest)
		
		$lsth = $sdm->do_prepared_query($linksql,$MSG_ID,$lnk,$linkdest);
		# Save to database clicks=($MSG_ID,$lnk,$RCPT_ID,0,0,0)
		$csth = $sdm->do_prepared_query($clicksql,$MSG_ID,$lnk,$RCPT_ID);
		if($csth) {
			if(! $csth->rows ) {
				$text .= "\n<!-- Error: Cannot write click entry to database: $MSG_ID,$lnk \n     ".$csth->errstr." -->";
			}
		}
		$text =~ s/\001$lnk\001/$BASE_URL\/$MSG_ID\/$RCPT_ID\/$lnk/;
	}
	$context->{STASH}{Tracking}{LINK_ID} = $LINK_ID;
	return $text;
}

# This defines a filter, Tracking, that adds tracking to any URLs in HTML A tags
# [% FILTER Tracking %] <A href=http://foo/>Click here</A> [% END %]
sub track_ff {
	# These are the params passed at plugin load time
	my ($context, @args) = @_;
	return sub {
		# This is the param passed at filter execute time
		my $text = shift;
		_track_links($text, $context, @args);
	}
}

1;

__END__

