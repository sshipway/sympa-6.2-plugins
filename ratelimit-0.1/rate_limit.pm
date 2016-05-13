#!/usr/bin/perl
#
# This function returns TRUE if the message should be dropped
# Params:
#   listname, subscriber (optional), max per timewindow (Day), unique param
#
# CustomCondition::rate_limit([listname],[sender],10,[header->Message-ID]) smtp,dkim,smime reject(tt2=rate_limit)
#
# Version 0.3
#
# History
# 0.1 - first release
# 0.2 - standardised field names.  Fixed insert test to work correctly
# 0.3 - changed time window to be 1 day, not 1 hour.  Makes much more sense.
#       Note that boundary is midnight GMT, not local time.
# 1.0 - Update for Sympa 6.2

package CustomCondition::rate_limit;
use strict;
use Sympa::Log; 
use Sympa::DatabaseManager;
my($DEBUG) = 'debug2'; 
my($WINDOW) = 86400; # seconds (one day)

sub verify {
  my($listname,$sender,$maxrate) = @_;
  my($count);
  my($sql,$sdm,$sth,$rows,$ret,$lastmsg);
  my($now) = time();

  if($sender) {
    do_log ($DEBUG, "rate_limit: Rate limit for list $listname, subscriber $sender is $maxrate per day");
  } else {
    $sender = '';
    do_log ($DEBUG, "rate_limit: Rate limit for list $listname is $maxrate per day");
  }
  $sdm = Sympa::DatabaseManager->instance;
  if(!$sdm) {
    do_log ('err', "rate_limit: Unable to connect to database");
    return undef;
  }
  # obtain current number
  $count = 0; $lastmsg = 0;
  $sql  = "SELECT `count_rate`,UNIX_TIMESTAMP(`last_rate`) FROM `rate_limit` WHERE `name_rate` = ? AND `user_rate` = ? LIMIT 1 ";
  $sth  = $sdm->do_prepared_query($sql,$listname,$sender);
  if(!$sth or $sth->err) {
    do_log ('warning', "rate_limit: Cannot search database: (".$sdm->err.") ",$sdm->errstr) if($sdm->err);
    $sql = "CREATE TABLE IF NOT EXISTS `rate_limit` ( `name_rate` VARCHAR(100) NOT NULL, `user_rate` VARCHAR(100) DEFAULT NULL, `count_rate` INTEGER, `last_rate` DATETIME, PRIMARY KEY( `name_rate`, `user_rate` ) ) ";
    $ret = $sdm->do_query($sql);
    do_log ('err', "rate_limit: Cannot create table: ",$sdm->errstr)
	if(!$ret);
  } else {
    $rows = $sth->fetchall_arrayref();
    if( @$rows ) {
      $count = $rows->[0][0];
      $lastmsg = $rows->[0][1];
      do_log ($DEBUG, "rate_limit: Current count for list $listname, subscriber $sender is $count at time ".localtime($lastmsg));
    }
  }
  # increment count or create new record
  # set to 0 if new hour
  if(!$count) {
    $count = 1;
  } else {
    if( int($now / $WINDOW) != int($lastmsg / $WINDOW) ) {
      # different day
      $count = 1; 
    } else {
      $count += 1;
    }
  }
  # update database
  $sql = "UPDATE `rate_limit` SET `count_rate` = ?, `last_rate` = FROM_UNIXTIME( ? ) WHERE `name_rate` = ? AND `user_rate` = ?";
  $sth  = $sdm->do_prepared_query($sql,$count,$now,$listname,$sender);
  do_log ($DEBUG, "rate_limit: Updating for list $listname, subscriber $sender with $count at time ".localtime($now));
  if(!$sth or !$sth->rows) {
    do_log ($DEBUG, "rate_limit: Trying to create record for $listname, $sender");
    $sql = "INSERT INTO `rate_limit` (`count_rate`,`last_rate`,`name_rate`,`user_rate`) VALUES( ?, FROM_UNIXTIME( ? ), ?, ? )";
    $sth  = $sdm->do_prepared_query($sql,$count,$now,$listname,$sender);
    if(!$sth or $sth->err) {
      do_log ('err', "rate_limit: Cannot update database: (".$sdm->err.") ",$sdm->errstr);
    }
  } else {
    do_log ($DEBUG, "rate_limit: Updated ".$sth->rows." rows");
  }

  $sdm->disconnect();
 
  # Threshold 
  return 1 if($count > $maxrate);
  return 0; # pass
}
## Packages must return true.
1;
