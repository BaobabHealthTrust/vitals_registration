delimiter $$

CREATE TABLE `serial_number` (
  `serial_number` int(11) NOT NULL,
  `national_id` varchar(30) DEFAULT NULL,
  `date_assigned` datetime DEFAULT NULL, 
  `date_created` datetime DEFAULT NULL, 
  `creator` int(11) DEFAULT NULL,
  `voided` tinyint(1) NOT NULL DEFAULT '0',
  `voided_by` int(11) DEFAULT NULL,  
  PRIMARY KEY (`serial_number`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COMMENT='Link between person and issued serial number'$$;

