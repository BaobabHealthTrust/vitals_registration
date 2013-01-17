class SerialNumber < ActiveRecord::Base
  set_table_name "serial_number"
  set_primary_key "serial_number"
  include Openmrs
  	def self.set_national_id(serial_numb, national_id)
      serial_numb.national_id = national_id 
      serial_numb.save
    end
end
