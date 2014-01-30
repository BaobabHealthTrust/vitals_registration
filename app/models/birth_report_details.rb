class BirthReportDetails < ActiveRecord::Base
	set_table_name "birth_report_details"
	set_primary_key "patient_id"
  include Openmrs

  belongs_to :person, :conditions => {:voided => 0}
  
end
