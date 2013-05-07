DELIMITER $$
DROP TRIGGER IF EXISTS `person_attribute_after_delete`$$
CREATE TRIGGER `person_attribute_after_delete` AFTER UPDATE 
ON `person_attribute`
FOR EACH ROW

BEGIN

		SET @attribute_type = (SELECT name FROM person_attribute_type WHERE person_attribute_type_id = new.person_attribute_type_id LIMIT 1);
		
		IF (SELECT COUNT(*) FROM birth_report WHERE patient_id = new.person_id) > 0 THEN
		
				IF UPPER(@attribute_type) = "HEALTH DISTRICT" THEN
 						UPDATE birth_report SET district_of_birth = new.value  WHERE patient_id = new.person_id;
 				END IF; 				
 				
 		END IF;
 		
END$$

DELIMITER ;