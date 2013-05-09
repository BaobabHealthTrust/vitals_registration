DELIMITER $$
DROP TRIGGER IF EXISTS `person_attribute_after_delete`$$
CREATE TRIGGER `person_attribute_after_delete` AFTER UPDATE 
ON `person_attribute`
FOR EACH ROW

BEGIN

        SET @attribute_type = (SELECT name FROM person_attribute_type WHERE person_attribute_type_id = new.person_attribute_type_id LIMIT 1);
	SET @mother_type = (SELECT relationship_type_id FROM relationship_type WHERE a_is_to_b = "Child" AND b_is_to_a = "Mother" ORDER BY date_created LIMIT 1);
        SET @father_type = (SELECT relationship_type_id FROM relationship_type WHERE a_is_to_b = "Child" AND b_is_to_a = "Father" ORDER By date_created LIMIT 1);
        SET @check = (SELECT person_a FROM relationship WHERE person_b = new.person_id AND relationship = @mother_type OR relationship =@father_type ORDER BY date_created DESC LIMIT 1);

            IF (SELECT COUNT(*) FROM birth_report WHERE patient_id = new.person_id OR patient_id = @check) > 0 THEN
              
                IF UPPER(@attribute_type) = "HEALTH DISTRICT" THEN
                    UPDATE birth_report SET district_of_birth = new.value  WHERE patient_id = new.person_id;
                END IF;
                    
                IF (new.value != "Other" AND  (UPPER(@attribute_type) = "RACE" OR  (UPPER(@attribute_type) = "CITIZENSHIP"))) THEN
                  
                    SET @mother = (SELECT person_b FROM relationship WHERE person_b = new.person_id AND relationship = @mother_type ORDER BY date_created DESC LIMIT 1);
                    SET @father = (SELECT person_b FROM relationship WHERE person_b = new.person_id AND relationship = @father_type ORDER BY date_created DESC LIMIT 1);

                    IF COALESCE(@mother, '') != '' THEN
                        UPDATE birth_report SET nationality_mother = new.value  WHERE patient_id IN (SELECT person_a FROM relationship WHERE relationship = @mother_type);
                    END IF;

                    IF COALESCE(@father, '') != '' THEN
                        UPDATE birth_report SET nationality_father = new.value  WHERE patient_id IN (SELECT person_a FROM relationship WHERE relationship = @father_type);
                    END IF;

                END IF;

            END IF;
 		
END$$

DELIMITER ;
