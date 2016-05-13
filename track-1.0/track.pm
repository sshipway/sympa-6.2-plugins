#============================================================= -*-Perl-*-
#
# DESCRIPTION
#   Sympa 6.2 list custom action to reporting on tracking plugin.
#   This is installed into custom_actions
#
# AUTHOR
#   Steve Shipway
#
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
# 1.0 : Sympa 6.2 support, changes to custom_actions format
#============================================================================

package track_plugin;
use strict;

our $VERSION   = 1.00;

##########################################################
# These functions are used in web frontend mode

# Fetch the list of all known messages
sub listmsgs($$) {
	my($stashref) = shift;
	my($listname) = shift;
	my($rv) = '';
	my(@messages) = ();
	my($sth,$sql,$ret);
	my(@msg);

	$sql = "SELECT m.`msg_id`,m.`subject`,m.`sent`,count(c.`rcpt_id`) numsent from `tracking_msgs` m,`tracking_clicks` c where m.`list_name` = ? AND c.`msg_id` = m.`msg_id` AND  c.`link_id` = 0 GROUP BY m.`msg_id` ORDER BY m.`sent` DESC LIMIT 1000";
	$sth = SDM::do_prepared_query($sql,$listname);
	if( !$sth ) {
		$stashref->{errmsg} .= "Database error";
		$stashref->{message_sql} = $sql;
		return;
	}
	$ret = $sth->fetchall_arrayref;
	if( !$ret or $sth->err ) {
		$stashref->{errmsg} .= "Query error: ".$sth->errstr;
		$stashref->{message_sql} = $sql;
		return;
	}
	foreach ( @$ret ) { 
		push @messages, { id=>($_->[0]), subject=>($_->[1]), sent=>($_->[2]), num=>($_->[3]) }; 
	}

	$stashref->{message_list} = \@messages;
	$stashref->{message_count} = $#messages + 1;
	$stashref->{message_sql} = $sql;
	return;
}

# Fetch the details for a specific message
sub getmsg($$$) {
	my($stashref,$listname,$msgid) = @_;
	my($rv) = '';
	my(%msgdata) = { id=>$msgid, subject=>'Unknown', sent=>'Unknown', num=>0, seen=>0, rate=>'Unknown' };
	my($sql,$ret,$sth);

	$sql = "SELECT m.`msg_id`,m.`subject`,m.`sent`,(SELECT count(*) from `tracking_clicks` c WHERE c.`msg_id` = m.`msg_id` and c.`link_id` = 0) numsent, (SELECT count(*) from `tracking_clicks` c WHERE c.`msg_id` = m.`msg_id` and c.`link_id` = 0 and c.`clicks`>0) numseen from `tracking_msgs` m WHERE m.`msg_id` = ? LIMIT 1";
	$sth = SDM::do_prepared_query($sql,$msgid);
	if( !$sth ) {
		$stashref->{errmsg} .= "Database error";
		$stashref->{message_sql} = $sql;
		return;
	}
	$ret = $sth->fetchrow_arrayref();
	if($ret and @$ret) {
		$msgdata{id}      = $ret->[0];
		$msgdata{subject} = $ret->[1];
		$msgdata{sent}    = $ret->[2];
		$msgdata{num}     = $ret->[3];
		$msgdata{seen}    = $ret->[4];
		$msgdata{rate}    = $ret->[4]/$ret->[3]*100.0 if($ret->[3]);
	}

	$stashref->{'msg'} = \%msgdata;
	$stashref->{'message_sql'} = $sql;
	return;
}

# Fetch the details for a specific link
sub getlink($$$$) {
	my($stashref,$listname,$msgid,$linkid) = @_;
	my($rv) = '';
	my(%lnkdata) = ();
	my($sql,$ret,$sth);

	$linkid = 0 if($linkid eq 'none');

	$sql = "SELECT l.`link_id`,l.`url`,(SELECT count(*) from `tracking_clicks` c WHERE  c.`msg_id` = ? and c.`link_id` = ? and c.`clicks`>0 ) num from `tracking_links` l WHERE l.`msg_id` = ? and l.`link_id` = ? LIMIT 1";
	$sth = SDM::do_prepared_query($sql,$msgid,$linkid,$msgid,$linkid);
	if( !$sth ) {
		$stashref->{errmsg} .= "Database error";
		$stashref->{message_sql} = $sql;
		return;
	}
	$ret = $sth->fetchrow_arrayref();
	if($ret and @$ret) {
		$lnkdata{id}      = $ret->[0];
		$lnkdata{url}     = $ret->[1];
		$lnkdata{seen}    = $ret->[2];
	}

	$stashref->{message_sql} = $sql;
	$stashref->{'lnk'} = \%lnkdata;
	return;
}

# List all links for a specific message
sub listlinks($$$) { 
	my($stashref,$listname,$msgid) = @_;
	my($rv) = '';
	my(@links) = ();
	my($sql,$ret,$sth);

	$sql = "SELECT l.`link_id`, l.`url`, ( SELECT count(*) from `tracking_clicks` c where c.`msg_id` = ? and c.`link_id` = l.`link_id` and c.`clicks` > 0 ) clickers "
	."FROM `tracking_links` l "
	."WHERE l.`msg_id` = ? and l.`link_id` > 0 "
	."ORDER BY l.`link_id` LIMIT 1000 " ;
	$sth = SDM::do_prepared_query($sql,$msgid,$msgid);
	if( !$sth ) {
		$stashref->{errmsg} .= "Database error";
		$stashref->{message_sql} = $sql;
		return;
	}
	$ret = $sth->fetchall_arrayref();
	if( !$ret or $sth->err ) {
		$rv = "Database error: ".$sth->errstr;
		$stashref->{message_sql} = $sql;
		$stashref->{'errstr'} .= $rv;
		return;
	}
	foreach ( @$ret ) { 
		push @links, { id=>($_->[0]), url=>($_->[1]), rcpt=>($_->[2]), first=>($_->[3]) }; 
	}

	$stashref->{link_list} = \@links;
	$stashref->{message_sql} = $sql;
	return;
}

# List all clicks on a message/link
# If link is null then for message
sub listclicks($$$$) {
	my($stashref,$listname,$msgid,$linkid) = @_;
	my($rv) = '';
	my(@clicks) = ();
	my($sql,$ret,$sth);

	$linkid = 0 if(!defined $linkid or $linkid eq 'none');

	$sql = "SELECT c.`rcpt_id`,c.`clicks`,c.`first_click`,c.`last_click` from `tracking_clicks` c where c.`msg_id` = ? and c.`link_id` = ? and c.`clicks` > 0 ";
	$sth = SDM::do_prepared_query($sql,$msgid,$linkid);
	if( !$sth ) {
		$stashref->{errmsg} .= "Database error";
		$stashref->{message_sql} = $sql;
		return;
	}

	$ret = $sth->fetchall_arrayref();
	if( !$ret or $sth->err ) {
		$rv = "Database error: ".$sth->errstr;
		$stashref->{message_sql} = $sql;
		$stashref->{'errmsg'} .= $rv;
		return;
	}
	foreach ( @$ret ) { 
		my $rcpt = $_->[0];
		$rcpt =~ s/\%40/\@/g;
		push @clicks, { rcpt=>$rcpt, count=>($_->[1]), first=>($_->[2]), last=>($_->[3]) }; 
	}

	$stashref->{click_list} = \@clicks;
	$stashref->{message_sql} = $sql;
	return;
}
# Delete a message entirely from the database, by messageid
# Maybe this should ensure the message relates to this list?
sub delmsg($$$) {
	my($stashref,$listname,$msgid) = @_;
	my($rv) = '';
	my($sql,$sth);
	my(@sql) = ();

	@sql = ( 
		"DELETE from `tracking_clicks` where `msg_id` = ?",
		"DELETE from `tracking_links`  where `msg_id` = ?",
		"DELETE from `tracking_msgs`   where `msg_id` = ?",
	);
	foreach $sql ( @sql ) {
	  $sth = SDM::do_prepared_query($sql,$msgid);
	  if( !$sth ) {
		$stashref->{errmsg} .= "Database error";
		$stashref->{message_sql} = $sql;
		return;
	  }
	  if( $sth->err ) {
		$rv = "Database error: ".$sth->errstr;
		$stashref->{message_sql} = $sql;
		$stashref->{'errmsg'} .= $rv;
		return;
	  }
	}

	return;
}

####################################################################

sub process {
	my( $listref ) = shift; # reference to list object
	my( $action ) = shift;  # sub-action for this lca
	my( $track_msgid ) = shift;
	my( $track_linkid ) = shift;
	my( %stash ) = ();
	my( $listname );
	my($rv);

	return 'home' if(!ref $listref);

	$listname = $listref->{'name'}.'@'.$listref->{'domain'};
	$action = 'list' if(!$action or $action!~/^(list|show|delete|csv)$/);
	$stash{'track_cmd'} = $action;
	$track_linkid = '' if($track_linkid eq 'none');
	$track_msgid = '' if($track_msgid eq 'none');
	$stash{'track_msgid'} = $track_msgid if($track_msgid);
	$stash{'track_linkid'} = $track_linkid if(defined $track_linkid);
	$stash{'errmsg'} = "";
	$stash{next_action} = "lca:track";

	eval { require SDM; };
	
	# Identify what our status is.
	if( $action eq 'delete' ) {
		delmsg(\%stash,$listname,$track_msgid) if($track_msgid);
		listmsgs(\%stash,$listname);
	} else {
		if($track_msgid) {
			getmsg(\%stash,$listname,$track_msgid);
			if($track_linkid) {
				getlink(\%stash,$listname,$track_msgid,$track_linkid);
				listclicks(\%stash,$listname,$track_msgid,$track_linkid);
			} elsif( $action eq 'list' ) {
				listlinks(\%stash,$listname,$track_msgid);
			} else {
				listclicks(\%stash,$listname,$track_msgid,0);
			}
		} else {
			listmsgs(\%stash,$listname);
		}
	}

	return \%stash;
}

1;

