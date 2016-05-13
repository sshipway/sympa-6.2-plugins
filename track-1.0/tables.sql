CREATE TABLE IF NOT EXISTS `tracking_clicks` (
  `msg_id` varchar(32) NOT NULL,
  `link_id` int(11) NOT NULL,
  `rcpt_id` varchar(32) NOT NULL,
  `clicks` int(11) NOT NULL DEFAULT '0',
  `first_click` datetime DEFAULT NULL,
  `last_click` datetime DEFAULT NULL,
  UNIQUE KEY `msg_id` (`msg_id`,`link_id`,`rcpt_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

CREATE TABLE IF NOT EXISTS `tracking_links` (
  `msg_id` varchar(32) NOT NULL,
  `link_id` int(11) NOT NULL,
  `url` varchar(256) NOT NULL,
  UNIQUE KEY `msg_id` (`msg_id`,`link_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

CREATE TABLE IF NOT EXISTS `tracking_msgs` (
  `msg_id` varchar(32) NOT NULL,
  `subject` varchar(64) NOT NULL DEFAULT 'None',
  `list_name` varchar(64) NOT NULL,
  `sent` datetime NOT NULL,
  UNIQUE KEY `msg_id` (`msg_id`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

