#!/usr/bin/perl
#vim:ts=4
#
# track.cgi : Tracking script to go with the tracking TT2 plugin
#
# S. Shipway 2013
#
# Ver 0.1 : initial
#     0.2 : clicking a link sets views to 1 if it was 0
#     0.3 : Handle missing click records
#     1.0 : Support for Sympa 6.2

use strict;
use CGI;
use DBI;
use DBD::mysql;

my($VERSION) = "0.3";

my $q = new CGI;
my($DBHOST) = 'localhost';
my($DBPORT) = 3306;
my($DBNAME) = 'sympa';
my($DBUSER) = 'sympa';
my($DBPASS) = 'put your password here';

sub error_page($) {
	my($msg) = $_[0];
	print $q->header();
	print $q->start_html();
	print $q->h1("Error")."\n";
	print $q->p("The tracking script cannot redirect you: $msg");
	print $q->end_html();
}
# How many views for this message?
sub getviews($$) {
	my($msgid,$rcptid) = @_;
	my($dbh,$sql,$views);

	$dbh = DBI->connect("DBI:mysql:database=$DBNAME;host=$DBHOST;port=$DBPORT", $DBUSER, $DBPASS);
	if(!$dbh) { return 0; }
	$sql = "SELECT `clicks` from `tracking_clicks` WHERE `msg_id` = '$msgid' and `link_id` = 0 and `rcpt_id` = '$rcptid'";
	( $views ) = $dbh->selectrow_array($sql);
	if($dbh->err or !defined $views ) { return 0; }
	return $views;
}

# Fetch the URL to go to, and update click count
sub clickon($$$) {
	my($msgid,$linkid,$rcptid) = @_;
	my($sql,$clicks,$first);
	my($dbh,$url);

	$dbh = DBI->connect("DBI:mysql:database=$DBNAME;host=$DBHOST;port=$DBPORT", $DBUSER, $DBPASS);
	if(!$dbh) {
		error_page("Cannot connect to database");
		exit(0);
	}

	$rcptid =~ s/\@/\%40/;
	$rcptid =~ s/\%0A//ig;
	$rcptid =~ s/\n//g;

	$sql = "SELECT `clicks`,`first_click` from `tracking_clicks` WHERE `msg_id` = '$msgid' and `link_id` = $linkid and `rcpt_id` = '$rcptid'";
	($clicks,$first) = $dbh->selectrow_array($sql);
	if($dbh->err) {
		error_page("Error seeking tracking record: ".$dbh->errstr."<BR>$sql");
		exit(0);
	}
	if(!defined $clicks) {
#		error_page("Cannot find tracking record<BR>$sql");
#		exit(0);
		$sql = "INSERT INTO `tracking_clicks` (`msg_id`,`link_id`,`rcpt_id`,`clicks`,`last_click`,`first_click`) VALUES ('$msgid',$linkid,'$rcptid',1,NOW(),NOW())";
	} else {
	    if($clicks) {
		$sql = "UPDATE `tracking_clicks` SET `clicks`=".($clicks+1).", `last_click`=NOW() WHERE  `msg_id` = '$msgid' and `link_id` = $linkid and `rcpt_id` = '$rcptid'";
	    } else {
		$sql = "UPDATE `tracking_clicks` SET `clicks`=1, `last_click`=NOW(), `first_click`=NOW() WHERE  `msg_id` = '$msgid' and `link_id` = $linkid and `rcpt_id` = '$rcptid'";
	    }
	}
	$dbh->do($sql);
	if($dbh->err) {
		error_page("Cannot find tracking record: ".$dbh->errstr."<BR>$sql");
		exit(0);
	}
	return '' if(!$linkid); # was just read log
	$sql = "SELECT `url` from `tracking_links` WHERE `msg_id` = '$msgid' and `link_id` = $linkid";
	$url = $dbh->selectrow_array($sql);
	return $url;
}

# Resirect to the new place
sub redirect_to($$$) {
	my($msgid,$linkid,$rcptid) = @_;
	my($url) = '';
	my( $views );

	if( getviews($msgid,$rcptid) == 0 ) {
		clickon($msgid,0,$rcptid);
	}

	$url = clickon($msgid,$linkid,$rcptid);

	if($url) {
		print $q->redirect($url);
	} else {
		error_page("Expired link");
	}
}

# Return 1x1px image, and update click count
sub read_count($$) {
	my($msgid,$rcptid) = @_;
	
	clickon($msgid,0,$rcptid);

        print $q->header({ -type=>"image/gif", -expires=>"now" });
	binmode STDOUT;
	print "GIF89a\001\0\001\0\200\0\0\0\0\0\377\377\377!\371\004\0\0\0\377\0,\0\0\0\0\001\0\001\0\0\002\002L\001\0;";
}

###########################################################
# MAIN

if( $q->path_info() =~ /\/?(\S+)\/(\S+)\/(\d+)/ ) {
	redirect_to($1,$3,$2);
} elsif( $q->path_info() =~ /\/?(\S+)\/(\S+)/ ) {
	read_count($1,$2);
} else {
	error_page("Invalid parameters");
}
exit 0;
